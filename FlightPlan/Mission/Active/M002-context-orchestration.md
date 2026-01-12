---
title: "M002: Context & Orchestration System"
status: active
priority: P1
created: 2025-01-03
tags: [architecture, context, orchestration, cloudkit]
depends_on: [M001-foundation]
---

# M002: Context & Orchestration System

**Goal**: Enable AgentKit to support building Maverick-like applications. Agents are the new apps.

## Vision

Your agents are *your team* - contextual, personal, evolving. They know:
- Where you are (general chat vs specific project vs detected pattern)
- What they've learned (your preferences, past decisions, corrections)
- Who else is working (other agents, pending handoffs, approvals)

Conversations are ephemeral. Decisions and artifacts are durable.

## Core Principles

1. **Files are the API** - The folder structure *is* the interface
2. **Scope = Folders** - Context narrows through folder hierarchy
3. **Conversations are fleeting** - Only outputs (decisions, artifacts, learnings) persist
4. **Agents have identity** - Stable IDs, personal memory, evolving trust
5. **Hybrid storage** - CloudKit for hot state, files for durable context

## Data Architecture

### Storage Strategy

| Data Type | Storage | Sync | Lifecycle |
|-----------|---------|------|-----------|
| Active conversations | CloudKit | Real-time | Ephemeral (expire/archive) |
| Pending handoffs | CloudKit | Real-time | Until acknowledged |
| Agent status | CloudKit | Real-time | Heartbeat-based |
| Approvals queue | CloudKit | Real-time + Push | Until resolved |
| Decisions | Markdown files | iCloud Drive | Permanent |
| Artifacts | Files | iCloud Drive | Permanent |
| Agent memory | Markdown files | iCloud Drive | Evolving |
| Skills | Markdown files | iCloud Drive | Versioned |
| Archived conversations | Markdown files | iCloud Drive | Reference only |

### Folder Convention

```
~/.agentkit/                          # Global context
├── preferences.md                    # User preferences agents have learned
├── skills/                           # Global skill definitions
│   ├── researcher.md
│   ├── implementer.md
│   └── reviewer.md
└── agents/                           # Per-agent identity & memory
    ├── researcher/
    │   ├── identity.md               # Who is this agent
    │   ├── learnings.md              # Patterns from corrections
    │   └── preferences.md            # Agent-specific preferences
    └── implementer/
        └── ...

~/Projects/foo/
├── .agentkit/                        # Project context
│   ├── context.md                    # Project-specific agent memory
│   ├── decisions/                    # Decisions made in this project
│   │   └── 2025-01-03-hybrid-storage.md
│   ├── conversations/                # Archived valuable conversations
│   │   └── 2025-01-03-architecture-discussion.md
│   └── .state.json                   # Hot state cache (gitignored)
├── FlightPlan/                       # Optional: full FlightPlan structure
│   ├── Mission/
│   ├── Flight/
│   └── ...
└── src/                              # Project files
```

### CloudKit Schema

```swift
// MARK: - Hot State Records

/// Real-time agent status across devices
struct AgentStateRecord {
    let agentId: String
    let deviceId: String
    let status: String              // idle, working, waiting_approval
    let currentTaskId: String?
    let currentProjectPath: String?
    let lastHeartbeat: Date
}

/// Active conversation (ephemeral)
struct ConversationRecord {
    let conversationId: String
    let projectPath: String?
    let agentIds: [String]
    let startedAt: Date
    let lastActivityAt: Date
    let messageCount: Int
    // Messages themselves could be in a child record type
    // or just kept in memory and discarded
}

/// Agent-to-agent handoff
struct HandoffRecord {
    let handoffId: String
    let fromAgentId: String
    let toAgentId: String
    let priority: String            // high, medium, low
    let status: String              // pending, acknowledged, completed
    let projectPath: String?
    let summary: String
    let contextJSON: Data           // Flexible payload
    let createdAt: Date
    let acknowledgedAt: Date?
}

/// Pending approval request
struct ApprovalRecord {
    let approvalId: String
    let agentId: String
    let taskId: String
    let toolName: String
    let description: String
    let riskLevel: String
    let parametersJSON: Data
    let status: String              // pending, approved, denied
    let createdAt: Date
    let resolvedAt: Date?
    let resolvedBy: String?         // device that resolved
}
```

### File Formats

**Decision Document:**
```yaml
---
id: dec-abc123
title: Hybrid Storage Architecture
date: 2025-01-03
agents: [researcher]
status: accepted
supersedes: null
tags: [architecture, cloudkit, storage]
---

# Hybrid Storage Architecture

## Context
Needed to decide how to store agent state, conversations, and artifacts.

## Decision
Use CloudKit for hot/real-time state, iCloud Drive files for durable context.

## Rationale
- CloudKit provides real-time sync and push notifications
- Files remain portable, git-friendly, human-readable
- Hybrid gives best of both worlds

## Consequences
- Need CloudKit schema design
- Need file format conventions
- More complexity than pure-file approach
```

**Archived Conversation:**
```yaml
---
id: conv-xyz789
title: Context Protocol Design Discussion
started: 2025-01-03T10:30:00Z
ended: 2025-01-03T11:45:00Z
agents: [researcher, implementer]
topics: [architecture, cloudkit, context]
outcome: decision-made
decisions:
  - decisions/2025-01-03-hybrid-storage.md
artifacts:
  - Charts/agent-context-protocol.md
  - Charts/maverick-learnings.md
---

## Summary
Discussed agent context architecture after analyzing Maverick codebase.
Decided on hybrid CloudKit + files approach where conversations are
ephemeral but decisions and artifacts persist.

## Key Points
- FlightPlan pattern validated file-based context
- CloudKit needed for real-time cross-device sync
- Conversations are process, only outputs matter
```

**Agent Learning:**
```yaml
---
agentId: implementer
lastUpdated: 2025-01-03
---

# Implementer Learnings

## Code Style Preferences
- User prefers explicit types over inference
- Use MARK comments for section organization
- Keep functions short, extract early

## Correction Patterns
- 2025-01-03: Reminded to run swift build after changes
- 2025-01-02: Corrected to use Edit not Write for existing files
- 2024-12-28: Learned user prefers tabs over spaces (project-specific)

## Trust Evolution
- File operations: high (many successful edits)
- Git operations: medium (occasional amend issues)
- Shell commands: low (still learning preferences)
```

## Implementation Phases

### Phase 1: Context Discovery & Parsing
**Enable agents to understand where they are**

- [ ] Implement folder hierarchy scanning for `.agentkit/`
- [ ] YAML frontmatter parser for markdown files
- [ ] Context scope resolution (global → project → conversation)
- [ ] Merge semantics for layered context

```swift
protocol ContextDiscovery {
    func discoverScope(for path: URL) -> ContextScope
    func loadContext(scope: ContextScope) async throws -> AgentContext
    func mergeContexts(_ scopes: [ContextScope]) -> AgentContext
}
```

### Phase 2: Agent Memory & Identity
**Give agents persistent identity and learning**

- [ ] Stable agent IDs across sessions
- [ ] Per-agent memory storage (learnings, preferences)
- [ ] Correction tracking and pattern detection
- [ ] Trust level evolution based on history

```swift
protocol AgentMemory {
    func remember(_ key: String, value: Any, scope: ContextScope) async
    func recall(_ key: String, scope: ContextScope) async -> Any?
    func recordCorrection(_ correction: Correction) async
    func learnings(for agentId: AgentID) async -> [Learning]
}
```

### Phase 3: CloudKit Integration
**Real-time state sync across devices**

- [ ] CloudKit schema implementation
- [ ] Agent status heartbeat
- [ ] Handoff record CRUD
- [ ] Approval queue with push notifications
- [ ] Subscription to relevant record changes

```swift
protocol CloudStateProvider {
    func updateAgentStatus(_ status: AgentStatus) async throws
    func postHandoff(_ handoff: Handoff) async throws
    func pendingHandoffs(for agentId: AgentID) async throws -> [Handoff]
    func pendingApprovals() async throws -> [Approval]
    func resolveApproval(_ id: ApprovalID, decision: ApprovalDecision) async throws
}
```

### Phase 4: Conversation Lifecycle
**Ephemeral conversations with durable outputs**

- [ ] Active conversation tracking in CloudKit
- [ ] Decision extraction during/after conversation
- [ ] Automatic archival on idle timeout
- [ ] Optional conversation summary generation
- [ ] Link artifacts back to source conversation

```swift
protocol ConversationManager {
    func startConversation(projectPath: URL?) async throws -> ConversationID
    func recordDecision(_ decision: Decision) async throws
    func endConversation(_ id: ConversationID, archive: Bool) async throws
    func archiveToMarkdown(_ id: ConversationID) async throws -> URL
}
```

### Phase 5: Multi-Agent Orchestration
**Agents coordinating with each other**

- [ ] Skill registry from markdown definitions
- [ ] Agent spawning with scoped context
- [ ] Handoff protocol implementation
- [ ] Meta-agent pattern (Navigator-style)
- [ ] Parallel agent execution with merge

```swift
protocol AgentOrchestrator {
    func availableSkills() async -> [SkillDefinition]
    func spawn(skill: SkillID, context: AgentContext) async throws -> AgentID
    func handoff(from: AgentID, to: SkillID, context: HandoffContext) async throws
    func awaitAll(_ agents: [AgentID]) async throws -> [AgentResult]
}
```

### Phase 6: File System Integration
**React to context changes in real-time**

- [ ] FSEvents watcher for `.agentkit/` directories
- [ ] Debounced context reload on changes
- [ ] Conflict detection with CloudKit state
- [ ] External editor support (edit context files in any app)

```swift
protocol ContextWatcher {
    func watch(scope: ContextScope) -> AsyncStream<ContextChange>
    func reload(scope: ContextScope) async throws -> AgentContext
}
```

## Success Criteria

**For Maverick-like apps to be buildable on AgentKit:**

- [ ] Agents can discover and load project context from folder structure
- [ ] Agent identity and memory persists across sessions
- [ ] Real-time handoffs between agents via CloudKit
- [ ] Approvals sync across devices with push notifications
- [ ] Conversations are ephemeral, decisions/artifacts persist
- [ ] Skills defined in markdown, loadable at runtime
- [ ] Meta-agent can orchestrate specialist agents
- [ ] Trust evolves based on correction patterns

## Dependencies

- **M001: Foundation** - Core agent runtime must be solid first
- **CloudKit entitlements** - Need Apple Developer account configured
- **Yams** - Swift YAML parsing library
- **FSEvents** - File system watching (built into macOS)

## Open Questions

1. **Conversation expiry** - How long before idle conversation archives? User preference?
2. **Conflict resolution** - When CloudKit and file state diverge, who wins?
3. **Skill sharing** - Can users share skill definitions? Via CloudKit public database?
4. **Privacy** - What if user wants fully offline? Graceful CloudKit-optional mode?
5. **Migration** - How do we handle schema/format evolution over time?

## Related Documents

- [Agent Context Protocol](../Charts/agent-context-protocol.md)
- [Maverick Learnings](../Charts/maverick-learnings.md)
- [M001: Foundation Phase](./M001-foundation.md)
