# Project Goldeneye

**The future of personal computing isn't apps you use—it's agents you train.**

Goldeneye is an AI agent platform for Apple devices, built on top of **AgentKit**, a Swift-native agent framework. The platform enables persistent, trustworthy AI agents that learn and grow alongside you.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Goldeneye                              │
│         (Application Layer + Primary Agent)                 │
├─────────────────────────────────────────────────────────────┤
│                       AgentKit                              │
│              (Swift Agent Framework)                        │
├─────────────────────────────────────────────────────────────┤
│                    Compute Layer                            │
│        (Local MLX / Private Cloud Compute / APIs)           │
└─────────────────────────────────────────────────────────────┘
```

### AgentKit

AgentKit is the foundational Swift framework that provides:

- **Agent Execution Engine** — The observe-think-act loop that powers all agents
- **LLM Provider Abstraction** — Unified interface for any backend (local MLX, Claude, OpenAI-compatible, CLI tools)
- **Tool System** — Extensible capabilities with risk-based approval
- **Human-in-the-Loop (HITL)** — Approval workflows for high-risk operations
- **Agent-to-Agent Protocol (A2A)** — Communication layer for agent delegation
- **Session Management** — Git-backed context and audit trails

### Goldeneye

Goldeneye is the application layer that orchestrates the agent experience through a **Primary Agent** architecture.

## The Primary Agent: Chief of Staff

At the heart of Goldeneye is a single **Primary Agent**—think of it as your Chief of Staff. This agent is the primary interface between you and the system.

### Responsibilities

1. **Intake** — All user interactions flow through the Primary Agent first
2. **Direct Handling** — Handles straightforward requests directly via chat
3. **Delegation** — Routes complex or specialized tasks to appropriate subagents
4. **Quality Control** — Reviews work completed by subagents before presenting to the user
5. **Opportunity Identification** — Recognizes patterns that warrant creating new specialized subagents

### The Bootstrap Problem

Every system needs a starting point. The Primary Agent solves the bootstrap problem by being:

- The **first** agent in the system (everything else grows from here)
- The **always-on** interface (you're always talking to the Chief of Staff)
- The **trust anchor** (new subagents inherit trust boundaries from delegation context)

```
┌─────────────────────────────────────────────────────────┐
│                    Primary Agent                        │
│                  "Chief of Staff"                       │
│                                                         │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │
│   │   Intake    │  │   Review    │  │  Identify   │   │
│   │   & Chat    │  │   & QC      │  │   Growth    │   │
│   └─────────────┘  └─────────────┘  └─────────────┘   │
│                          │                             │
└──────────────────────────┼─────────────────────────────┘
                           │ delegates
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │ Subagent A │  │ Subagent B │  │ Subagent C │
    │  (Email)   │  │  (Code)    │  │ (Research) │
    └────────────┘  └────────────┘  └────────────┘
```

## Managed Subagents

A key differentiator of Goldeneye is **managed subagents**—specialized agents that the Primary Agent identifies, creates, and trains over time.

### How Subagents Emerge

1. **Pattern Recognition** — The Primary Agent notices repeated task types
   - "I keep handling email triage the same way..."
   - "Code review requests follow a consistent pattern..."

2. **Agent Proposal** — The Primary Agent proposes a new subagent
   - Defines the specialization scope
   - Suggests initial capabilities and tools
   - Recommends trust boundaries

3. **User Approval** — You approve (or modify) the subagent creation

4. **Training & Refinement** — The subagent learns from:
   - Initial guidance from the Primary Agent
   - User corrections and feedback
   - Successful task completions

5. **Trust Building** — Subagents earn autonomy through demonstrated competence

### Subagent Lifecycle

```
[Identified] → [Proposed] → [Created] → [Training] → [Active] → [Trusted]
                   │                         │            │
                   └── User Approval ────────┴── Feedback ┴── Autonomy
```

### Growth Strategy

The managed subagent model creates a natural growth path:

| Stage | Description |
|-------|-------------|
| **Week 1** | Just you and the Chief of Staff |
| **Month 1** | 2-3 subagents handling your most common tasks |
| **Month 6** | A small team of specialists, each with earned trust |
| **Year 1** | A personalized workforce that knows how *you* work |

This isn't about replacing you—it's about building a team that amplifies what you can do.

## Trust Model

Agents don't get blanket permissions. They earn trust through demonstrated behavior:

| Level | Name | Capabilities |
|-------|------|--------------|
| 0 | Observer | Read-only, suggestions only |
| 1 | Assistant | Can create drafts, needs approval |
| 2 | Contributor | Can modify, changes are staged |
| 3 | Trusted | Direct execution, HITL for high-risk |
| 4 | Autonomous | Full autonomy within defined boundaries |

Trust is:
- **Contextual** — Trusted for calendar, not for email
- **Earned** — Through successful task completion
- **Revocable** — Mistakes reduce trust level
- **Auditable** — Git-backed history of all actions

## Privacy Architecture

Your data can be used by agents, but never seen by anyone else.

```
YOUR DEVICE (Calendar, Mail, Notes via MCP)
        │
        ▼
YOUR CONTEXT (assembled, encrypted)
        │
    ┌───┴─────────┬──────────────┐
    ▼             ▼              ▼
Local MLX    Private Cloud    Verified
(100%        Compute          Providers
private)     (Apple's         (E2E
             guarantees)      encrypted)
```

## Project Structure

```
goldeneye/
├── AgentKit/                    # Swift framework
│   ├── Sources/
│   │   ├── AgentKit/            # Core library
│   │   ├── AgentKitServer/      # HTTP server
│   │   ├── AgentKitCLI/         # CLI tool
│   │   └── AgentKitConsole/     # macOS app
│   └── Tests/
│
└── FlightPlan/                  # Documentation & planning
    ├── Mission/                 # Strategic objectives
    ├── Flight/                  # Implementation sprints
    └── Charts/                  # Technical specs
```

## Current Status

**Phase**: V1 Local Runtime

Building the foundation for the Primary Agent architecture on macOS with local inference (MLX on Apple Silicon).

See [FlightPlan/Context/current-state.md](FlightPlan/Context/current-state.md) for detailed status.

## Getting Started

```bash
# Build the framework
cd AgentKit
swift build

# Run the CLI
swift run AgentKitCLI

# Run the console app
swift run AgentKitConsole
```

## Key Concepts

| Concept | Description |
|---------|-------------|
| **Primary Agent** | The Chief of Staff—your single point of contact |
| **Managed Subagent** | Specialized agent created and trained by the Primary Agent |
| **AgentKit** | Swift framework providing agent infrastructure |
| **HITL** | Human-in-the-loop approval for high-risk operations |
| **A2A** | Agent-to-agent protocol for delegation |
| **Trust Level** | Earned autonomy through demonstrated competence |

## Documentation

- [Vision Document](FlightPlan/Goldeneye-Vision.md) — Full architectural vision
- [AgentKit Spec](FlightPlan/Charts/Technical/agentkit-spec.md) — Technical specification
- [Architecture Overview](FlightPlan/Charts/Technical/architecture-overview.md) — System design

---

*Built for a future where AI agents are trusted colleagues, not black-box tools.*
