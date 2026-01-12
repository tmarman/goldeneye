# AgentKit + iCloud Agents

## What We're Building

**AgentKit** is a Swift framework for building AI agents on Apple platforms. **iCloud Agents** is a consumer product built on AgentKit—workspaces for complex, ongoing projects like trip planning, product strategy, or home renovation.

## The Opportunity

Apple has all the pieces: EventKit, MessageUI, FileProvider, MLX, PCC, AppIntents, Handoff, iCloud. What's missing is the orchestration layer that ties them together into a coherent agent platform.

Siri handles immediate tasks ("Set a timer"). iCloud Agents handles ongoing projects that span days or weeks, produce artifacts, and require context across multiple apps.

## Two Deliverables

| | AgentKit | iCloud Agents |
|---|----------|---------------|
| **What** | Swift framework | Consumer product |
| **For** | Developers | Users |
| **Like** | UIKit for agents | Built-in apps that showcase it |

## Core Architecture

```
iCloud Agents App (Chat, Artifacts, Workspaces)
        │
Agents Runtime (Trust, Memory, Orchestration)
        │
    AgentKit (LLM Providers, Tools, A2A, Sessions)
        │
MCP Servers (Calendar, Mail, Notes, Files, AppIntents)
```

## Key Capabilities

- **Trust Model**: Agents earn autonomy over time (Observer → Assistant → Contributor → Trusted → Autonomous)
- **Privacy**: MLX for local inference, PCC for cloud with hardware attestation
- **HITL**: Approvals via Handoff, Live Activities, Siri—works across Mac, iPhone, Watch
- **Artifacts**: Documents, calendar events, email drafts—staged then applied, git-versioned

## Apple-Native Advantages

1. **Continuity-Powered Approvals**: Agent on Mac needs approval; user approves from Watch, hands off to iPhone for detail, edits on Mac
2. **Shortcuts Integration**: Agents expose AppIntents; Shortcuts can orchestrate agents; Siri can invoke and approve
3. **MLX + PCC**: Local-first inference with cloud overflow—Apple controls the entire stack

## Business Model

- **Agent Store**: Distribution for third-party agents (App Store model)
- **iCloud Compute**: PCC subscription tiers (Free/Pro $9.99/Teams $49.99)
- **Model Hosting**: Third-party models on PCC with privacy guarantees

## What We Need

- 10 engineers, 2 designers, 2 PMs
- Framework API access (EventKit, MessageUI, FileProvider)
- Executive sponsorship for cross-team coordination

## Timeline

MVP in 6 months. Full platform with Agent Store in 18-24 months.
