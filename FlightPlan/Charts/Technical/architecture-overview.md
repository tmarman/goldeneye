# AgentKit Architecture Overview

## Runtime Layers

The system operates through three interconnected layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    KNOWLEDGE BACKBONE                        │
│                                                              │
│   WORLD KNOWLEDGE              BUILT UNDERSTANDING           │
│   (what exists)                (what you know)               │
│  ┌────────────────┐          ┌────────────────────┐         │
│  │ Slack, Email,  │          │ ~/.goldeneye/spaces │         │
│  │ Web, Spotlight │─informs─▶│ ├── work/           │         │
│  │ (vectors/index)│          │ │   ├── context.md  │         │
│  └────────────────┘          │ │   └── .git/       │         │
│                              │ └── personal/       │         │
│                              └────────────────────┘         │
└────────────────────────┬────────────────────────────────────┘
                         │ shared context
┌────────────────────────┼────────────────────────────────────┐
│                        ▼                                     │
│                   ENVOY APP                                  │
│          Interactive chat, approvals, coaching               │
└────────────────────────┬────────────────────────────────────┘
                         │ delegated tasks
┌────────────────────────┼────────────────────────────────────┐
│                        ▼                                     │
│               BACKGROUND RUNNERS                             │
│        Autonomous execution on shared context                │
└─────────────────────────────────────────────────────────────┘
```

### Knowledge Backbone

Two complementary systems:

| System | Purpose | Storage | Examples |
|--------|---------|---------|----------|
| **World Knowledge** | What exists in your data | Vector indexes, Spotlight | "What's in my Slack?" |
| **Built Understanding** | What you know | Scoped folders + git | "What do I know about this project?" |

**World Knowledge** is read-only indexing of external data (Slack, email, web, files via Spotlight).

**Built Understanding** is your evolving notes—scoped by folder, versioned by git, human-readable markdown.

### Envoy App

Interactive SwiftUI interface for human-agent collaboration: chat, approvals, knowledge browsing, configuration.

### Background Runners

Autonomous agent execution: task runners, CLI execution, scheduled jobs, watch triggers.

---

## System Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Apple Devices                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │   iPhone     │  │    iPad      │  │     Mac      │           │
│  │   App        │  │    App       │  │     App      │           │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘           │
│         │                 │                 │                    │
│         └─────────────────┼─────────────────┘                    │
│                           │                                      │
│  ┌────────────────────────▼────────────────────────────────┐    │
│  │                    AgentKit SDK                          │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │    │
│  │  │  Tools  │  │ Context │  │ Storage │  │   A2A   │    │    │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘    │    │
│  │                    ┌─────────────┐                      │    │
│  │                    │ Agent Core  │                      │    │
│  │                    └─────────────┘                      │    │
│  └─────────────────────────┬───────────────────────────────┘    │
│                            │                                     │
│         ┌──────────────────┼──────────────────┐                 │
│         │                  │                  │                 │
│         ▼                  ▼                  ▼                 │
│    ┌─────────┐       ┌──────────┐      ┌───────────┐           │
│    │  Local  │       │  iCloud  │      │   PCC     │           │
│    │   LLM   │       │  Drive   │      │  (Apple)  │           │
│    └─────────┘       └──────────┘      └───────────┘           │
└─────────────────────────────────────────────────────────────────┘

                              │ A2A Protocol
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      External Agents                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │ Claude Code  │  │    Codex     │  │   Custom     │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### Agent Core
The execution engine. Manages agent lifecycle, task scheduling, and orchestration.

**Key Responsibilities**:
- Agent instantiation and teardown
- Task queue and priority management
- Execution loop with pause/resume/cancel
- State persistence triggers

### Context Layer
Implements ACE (Agentic Context Engineering) principles for managing agent memory and context.

**Key Responsibilities**:
- Context window management
- Summarization and pruning
- Cross-agent context sharing
- Retrieval for long-term memory

### Tool System
Extensible tool framework for agent capabilities.

**Key Responsibilities**:
- Tool registration and discovery
- Parameter validation
- Result handling
- Error recovery

### Storage Layer
File-based persistence with iCloud sync.

**Key Responsibilities**:
- Agent state serialization
- iCloud container management
- Conflict resolution
- Version history

### A2A Gateway
Protocol adapter for external agent communication.

**Key Responsibilities**:
- A2A message encoding/decoding
- Agent Card management
- Task routing to external agents
- Response aggregation

## Execution Environments

| Environment | Use Case | Latency | Privacy |
|-------------|----------|---------|---------|
| On-Device (Local LLM) | Quick tasks, sensitive data | Low | Maximum |
| iCloud | Storage, sync | Medium | Apple-managed |
| PCC | Heavy compute, large models | Higher | Apple privacy guarantees |
| External (A2A) | Specialized agents | Variable | Third-party |

## Data Flow

1. **User initiates task** → App captures intent
2. **Task submitted** → AgentKit queues task
3. **Agent executes** → Tools called, LLM invoked
4. **State persisted** → iCloud syncs across devices
5. **Result delivered** → App displays to user
6. **If needed** → A2A handoff to external agent
