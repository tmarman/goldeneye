---
title: Agent Context Protocol
status: research
created: 2025-01-03
tags: [architecture, context, orchestration, maverick-learnings]
---

# Agent Context Protocol

**Research notes from Maverick codebase analysis and design discussion.**

## Problem Statement

Agents need structured context beyond just a workspace path. They need to understand:
- Where they are (general chat vs specific project vs detected pattern)
- What they've learned (preferences, past decisions, corrections)
- Who else is working (other agents, pending handoffs, approvals)

## Key Insight from Maverick

FlightPlan proves that **file-based, git-native project intelligence** works well:
- Portable: copy folder = copy all context
- Versioned: git history for everything
- Human readable: markdown with YAML frontmatter
- Machine parseable: structured frontmatter for agents

The orchestration between agents isn't complex infrastructure - it's a **protocol** for how agents leave notes for each other.

## Proposed Approach

### File Format: Markdown + YAML Frontmatter

```yaml
---
type: handoff
from: research-agent
to: implementation-agent
priority: high
created: 2025-01-03T10:30:00Z
status: pending
context:
  project: agentkit-context-system
  files_touched: [Agent.swift, Session.swift]
---

## Summary
Human-readable content here...
```

Structure in frontmatter, flexibility in body.

### Future Option: Custom Bundle Format

If we need richer content (embedded images, attachments):

```
item.agentbundle/
├── content.md          # Main content (human readable)
├── metadata.yaml       # Structured data
├── attachments/        # Images, files
└── .state.json         # Hot agent state (frequently changing)
```

Benefits:
- Git-friendly markdown
- Structured metadata separate from content
- Native attachments
- Could register UTType for Finder/QuickLook integration
- RTFD-like but purpose-built

### Alternative: RTFD

macOS native format, TextKit understands it, but:
- Binary RTF isn't git-friendly
- Structured data would need convention
- Less portable outside Apple ecosystem

**Decision**: Start with markdown + frontmatter, evolve to bundle if needed.

## Context Scoping

Context narrows across folder hierarchy:

```
~/.agentkit/                    # Global agent memory
├── preferences.md              # User preferences agents have learned
├── skills/                     # Agent skill definitions
└── agents/                     # Agent-specific learned context

~/Projects/
├── .agentkit/                  # Project-level context
│   ├── context.md              # Project-specific agent memory
│   ├── active/                 # Currently active work
│   └── feed/                   # Agent-to-agent communication
└── src/                        # Project files
```

An agent working in `~/Projects/foo` gets:
1. Global preferences from `~/.agentkit/`
2. Project context from `~/Projects/foo/.agentkit/`
3. Conversation-specific context from session

## What We'd Need to Implement

### Core Protocol (Swift)

```swift
/// Scope levels for agent context
enum ContextScope {
    case global          // ~/.agentkit/
    case project(URL)    // project/.agentkit/
    case conversation    // In-memory session context
}

/// Discovers context from folder structure
protocol ContextDiscovery {
    func discoverScope(for path: URL) -> ContextScope
    func loadContext(scope: ContextScope) async throws -> AgentContext
}

/// Parsed frontmatter + content from markdown files
struct ContextDocument {
    let frontmatter: [String: Any]
    let content: String
    let sourceURL: URL
}

/// Agent memory that persists across sessions
protocol AgentMemory {
    func remember(_ key: String, value: Any, scope: ContextScope) async
    func recall(_ key: String, scope: ContextScope) async -> Any?
    func corrections(for agentId: AgentID) async -> [Correction]
}
```

### Agent-to-Agent Communication

```swift
/// Feed entry for agent handoffs
struct FeedEntry: Codable {
    let id: UUID
    let type: FeedEntryType
    let from: AgentID
    let to: AgentID?
    let created: Date
    let status: FeedStatus
    let summary: String
    let context: [String: AnyCodable]
}

enum FeedEntryType: String, Codable {
    case handoff        // Work passed to another agent
    case decision       // Decision made, for record
    case reviewRequest  // Human review needed
    case accomplishment // Work completed
    case question       // Needs clarification
}

/// Writes to project/.agentkit/feed/
protocol FeedWriter {
    func post(_ entry: FeedEntry) async throws
    func pending(for agent: AgentID) async throws -> [FeedEntry]
    func acknowledge(_ entryId: UUID) async throws
}
```

### Skill/Agent Definitions

```swift
/// Parsed from Skills/*.md frontmatter
struct SkillDefinition: Codable {
    let skillId: String
    let name: String
    let type: SkillType  // meta-strategic, tactical, specialized
    let capabilities: [String]
    let dependencies: [String]
    let trustLevel: TrustLevel
    let autoApprove: Bool
}

enum TrustLevel: String, Codable {
    case low      // Always require approval
    case medium   // Approve for known patterns
    case high     // Auto-approve most actions
}
```

### Data Sync Options

| Layer | Storage | Sync |
|-------|---------|------|
| Hot state (active tasks, feed) | `.state.json` or CloudKit | Real-time |
| Warm context (project memory) | Markdown files | iCloud Drive |
| Cold context (skills, preferences) | Markdown files | iCloud Drive |

Hybrid approach: CloudKit for real-time orchestration, files for durable context.

## Implementation Phases

### Phase 1: Context Discovery
- Detect `.agentkit/` folders in path hierarchy
- Parse markdown frontmatter
- Build scoped context for agent sessions

### Phase 2: Agent Memory
- Write learned preferences/corrections to files
- Load and merge context across scopes
- Expose to agents via context builder

### Phase 3: Feed System
- Agent-to-agent handoff files
- Status tracking (pending/acknowledged/completed)
- File watcher for real-time updates

### Phase 4: Skill Definitions
- Parse SKILL.md files
- Register available skills with orchestrator
- Support skill-based agent spawning

### Phase 5: Multi-Agent Orchestration
- Meta-agent that coordinates child agents
- Handoff protocol implementation
- Trust/approval integration

## Open Questions

1. **CloudKit vs pure files?** - CloudKit enables real-time but adds complexity
2. **Skill evolution** - How do agents propose/refine their own skills?
3. **Cross-device** - How does context sync when working from multiple machines?
4. **Conflict resolution** - What happens when two agents write to same context?

## Related

- Maverick FlightPlan: `/Users/tim/dev/studio/maverick/FlightPlan/`
- Maverick Skills: `/Users/tim/dev/studio/maverick/FlightPlan/Skills/`
- Current AgentKit: `/Users/tim/dev/agents/AgentKit/`
