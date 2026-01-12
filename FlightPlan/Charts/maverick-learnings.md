---
title: Maverick Codebase Learnings
status: reference
created: 2025-01-03
tags: [research, maverick, architecture]
---

# Maverick Codebase Learnings

**What we can learn from the Maverick project for AgentKit.**

## Architecture Patterns Worth Adopting

### 1. FlightPlan Structure

Maverick's folder convention that could inform our `.agentkit/` design:

```
FlightPlan/
├── Manifest/       → Identity & bootstrap (who is this, how to recreate)
├── Skills/         → Agent capabilities (what can agents do)
├── Mission/        → Strategic goals (why are we doing this)
├── Flight/         → Tactical execution (what's active, backlog, done)
│   ├── Active/
│   ├── Backlog/
│   ├── Feed/       → Agent communication
│   ├── Shaping/    → Work being specified
│   └── Shipped/
├── Context/        → Current state & accumulated knowledge
└── Orchestration/  → Agent coordination rules
```

### 2. Momentum Workflow

Task lifecycle that maps well to agent work:

```
Seeding → Shaping → Ready → Active → Shipped → (Paused)
```

This gives structure to "what should agents work on next" decisions.

### 3. Navigator Meta-Agent Pattern

A strategic agent that orchestrates tactical agents:
- Detects skill gaps from correction patterns
- Routes work to appropriate specialists
- Coordinates multi-agent initiatives
- Proposes new capabilities when patterns emerge

### 4. ACE Layers (Agentic Context Engineering)

Three-layer context model:
- **Instructions** (Skills/) - What agents know how to do
- **Context** (Context/) - What agents know about the situation
- **Orchestration** (Orchestration/) - How agents coordinate

## Technical Patterns

### Frontmatter Schema

Maverick skills use consistent frontmatter:

```yaml
---
skillId: navigator
name: Navigator
type: meta-strategic
version: 1.0.0
status: active
capabilities: [...]
dependencies: []
trustLevel: low
autoApprove: false
lastEvolution: 2025-10-18
---
```

### Feed Entry Pattern

Agent-to-agent communication:

```yaml
---
type: handoff | decision | review_request | accomplishment
from: agent-id
to: agent-id
priority: high | medium | low
status: pending | acknowledged | completed
---
```

### Trust Levels

Graduated autonomy:
- **Low**: Always require human approval
- **Medium**: Approve for known patterns
- **High**: Auto-approve most actions

## Gaps to Fill in AgentKit

| Capability | Maverick Has | AgentKit Needs |
|------------|-------------|----------------|
| Folder convention detection | FlightPlan scanner | ContextDiscovery protocol |
| Frontmatter parsing | Custom YAML parser | Swift YAML + parser |
| Agent memory persistence | FlightPlan files | AgentMemory protocol |
| Agent-to-agent comm | Feed system | FeedWriter protocol |
| Skill definitions | SKILL.md format | SkillDefinition type |
| Meta-agent orchestration | Navigator skill | AgentOrchestrator protocol |
| File watching | FileSystemWatcher | FSEvents integration |
| Correction tracking | Evolution logs | Correction type + storage |

## Technology Choices

### What Maverick Uses

- **.NET 10 + MAUI Blazor** - Cross-platform with native feel
- **Temporal.io** - Durable workflow orchestration
- **Claude Code CLI** - Subprocess-based agent execution
- **Entity Framework + SQL/Cosmos** - Structured data
- **File system + Git** - Durable context storage

### What We Could Use (Swift/Apple)

- **SwiftUI + AppKit** - Native macOS
- **Swift Concurrency** - Actor-based agents
- **CloudKit** - Real-time sync + structured queries
- **iCloud Drive** - File sync
- **FSEvents** - File watching
- **SwiftData** - Local structured storage (if needed)

## Integration Points to Consider

### MCP (Model Context Protocol)

Maverick exposes tools via MCP server so external agents (Claude Code, Goose) can use Maverick capabilities. We could:
- Expose AgentKit tools via MCP
- Consume MCP servers as tool sources

### A2A Protocol

Maverick has informal agent-to-agent via files. The formal A2A protocol we're implementing could be the structured version of this.

### Agent Providers

Maverick abstracts over multiple agent backends:
- Claude Code CLI
- Anthropic API direct
- OpenAI
- Ollama (local)
- Exo cluster

Our LLM provider abstraction already supports this pattern.

## Key Insights

1. **Files are the API** - The FlightPlan folder *is* the interface. Agents read/write files. No complex RPC needed.

2. **Scope = Folders** - Context narrows as you go deeper in the folder hierarchy. Global → Project → Task.

3. **Correction patterns = Learning** - Track when humans correct agents, detect patterns, evolve skills.

4. **Meta-agents orchestrate** - One agent (Navigator) coordinates others rather than central scheduler.

5. **Trust evolves** - Start with low trust, increase as agent proves reliable in domain.

## What We Should Build Next

1. **ContextDiscovery** - Find and parse `.agentkit/` folders
2. **FrontmatterParser** - Extract YAML from markdown files
3. **AgentMemory** - Persist learned context to files
4. **FeedSystem** - Agent-to-agent communication files
5. **FileWatcher** - React to context changes in real-time

These are foundational and would enable building Maverick-like experiences on AgentKit.
