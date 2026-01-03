# Project Goldeneye
## AgentKit + Agents for iCloud
### Vision Document v0.1

> "The future of personal computing isn't apps you use—it's agents you train."

---

## Executive Summary

**Goldeneye** reimagines personal computing around persistent, trustworthy agents that learn and grow with their users. The project consists of:

- **AgentKit** - Core Swift library for agent infrastructure (general-purpose)
- **Agents** - Apple platform layer + user-facing app (iCloud-synced agents)

Unlike current AI assistants that are stateless and siloed, Agents:

- **Remember and learn** through personalized context that persists across sessions
- **Operate within secure boundaries** using Apple's privacy infrastructure (iCloud, PCC)
- **Earn autonomy over time** like new employees earning trust, not apps requesting permissions
- **Interoperate seamlessly** across local devices and cloud infrastructure
- **Integrate with existing tools** (Calendar, Reminders, Notes, Mail) rather than replacing them

This is not another chatbot. This is the foundation for a new computing paradigm.

---

## AgentKit: The Foundation

AgentKit is the core Swift library that powers Goldeneye. It provides the infrastructure for building, running, and managing AI agents on Apple platforms.

### Design Goals

1. **Native Swift-first**: Built for Apple platforms, not ported from Python/JS
2. **Provider-agnostic**: Same agent code runs on any LLM (local, cloud, CLI)
3. **Protocol-oriented**: Composable, testable, extensible via Swift protocols
4. **Security by default**: Approval system built into the core, not bolted on
5. **Interoperable**: A2A protocol for agent-to-agent communication

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Agents.app                                │
│              (macOS/iOS app, CLI, or headless service)           │
└─────────────────────────────────────────────────────────────────┘
                               │
┌─────────────────────────────────────────────────────────────────┐
│                          AgentKit                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Agent Loop    │  │   Tool System   │  │  Approval Mgr   │  │
│  │                 │  │                 │  │                 │  │
│  │ • Message flow  │  │ • Read/Write    │  │ • Risk levels   │  │
│  │ • Tool dispatch │  │ • Bash/Glob     │  │ • HITL flow     │  │
│  │ • State mgmt    │  │ • Custom tools  │  │ • Policies      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  LLM Providers  │  │   A2A Protocol  │  │   MCP Client    │  │
│  │                 │  │                 │  │                 │  │
│  │ • Anthropic     │  │ • Task routing  │  │ • Server disco  │  │
│  │ • OpenAI-compat │  │ • Agent handoff │  │ • Tool proxy    │  │
│  │ • Exo (cluster) │  │ • State sync    │  │ • Streaming     │  │
│  │ • MLX (local)   │  │                 │  │                 │  │
│  │ • CLI wrappers  │  │                 │  │                 │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                               │
┌─────────────────────────────────────────────────────────────────────────────┐
│                             Compute Layer                                    │
├──────────────────┬──────────────────┬──────────────────┬────────────────────┤
│   Local (MLX)    │   Exo Cluster    │   PCC (Apple)    │   Cloud (APIs)     │
│   Single device  │   Multi-device   │   Private cloud  │   Anthropic/OpenAI │
│   inference      │   distributed    │   compute        │   with encryption  │
└──────────────────┴──────────────────┴──────────────────┴────────────────────┘
```

### Current Implementation Status

| Component | Status | Description |
|-----------|--------|-------------|
| **LLM Provider Protocol** | ✅ Complete | Unified interface for all model providers |
| **Anthropic Provider** | ✅ Complete | Claude API with streaming, tools, vision |
| **OpenAI-Compatible** | ✅ Complete | Works with Ollama, LM Studio, vLLM, etc. |
| **Exo Cluster Provider** | ✅ Complete | Distributed inference across Apple Silicon devices |
| **MLX Provider** | ✅ Complete | Native Apple Silicon inference |
| **CLI Agent Providers** | ✅ Complete | Claude Code, Codex CLI, Gemini CLI wrappers |
| **Tool System** | ✅ Complete | Read, Write, Bash, Glob, Grep, custom tools |
| **A2A Protocol** | ✅ Complete | Agent-to-agent communication |
| **Approval System** | ✅ Complete | Risk-based HITL with policies |
| **Agent Loop** | ✅ Complete | Message processing with tool execution |
| **macOS Console** | ✅ Prototype | Dashboard, approvals, session management |

### LLM Provider Abstraction

The provider system allows the same agent to run on any backend:

```swift
/// Core protocol - all providers implement this
public protocol LLMProvider: Actor {
    var name: String { get }

    func complete(
        _ messages: [Message],
        tools: [ToolDefinition],
        options: CompletionOptions
    ) async throws -> AsyncThrowingStream<LLMEvent, Error>

    func isAvailable() async -> Bool
}

/// Events streamed from providers
public enum LLMEvent {
    case textDelta(String)           // Streaming text
    case toolCall(ToolCall)          // Model wants to use a tool
    case usage(LLMUsage)             // Token counts
    case done                        // Completion finished
    case error(LLMError)             // Error occurred
}
```

**Implemented Providers**:

| Provider | Backend | Use Case |
|----------|---------|----------|
| `AnthropicProvider` | Claude API | Cloud inference, most capable |
| `OpenAICompatibleProvider` | Any OpenAI-compatible API | Ollama, LM Studio, vLLM |
| `OllamaProvider` | Ollama server | Local models via Ollama |
| `LMStudioProvider` | LM Studio | Local models via LM Studio |
| `MLXProvider` | Native MLX | Direct Apple Silicon inference |
| `FoundationModelsProvider` | Apple Intelligence | On-device Apple models |
| `ClaudeCodeProvider` | Claude Code CLI | Wraps Claude Code as provider |
| `CodexCLIProvider` | Codex CLI | Wraps OpenAI Codex CLI |
| `GeminiCLIProvider` | Gemini CLI | Wraps Google Gemini CLI |

### Tool System

Tools are capabilities that agents can use. Each tool has a defined schema and risk level:

```swift
public protocol Tool {
    var name: String { get }
    var description: String { get }
    var inputSchema: JSONSchema { get }
    var riskLevel: RiskLevel { get }

    func execute(_ input: ToolInput) async throws -> ToolOutput
}

public enum RiskLevel: Int, Comparable {
    case safe = 0       // Read-only, no side effects
    case low = 1        // Minor side effects
    case medium = 2     // Reversible changes
    case high = 3       // Significant changes
    case critical = 4   // Destructive or irreversible
}
```

**Built-in Tools**: Read, Write, Edit, Bash, Glob, Grep, WebFetch

### Approval System

The approval manager enforces human-in-the-loop based on risk:

```swift
public actor ApprovalManager {
    /// Check if action requires approval
    func requiresApproval(
        _ action: ApprovalRequest,
        policy: ApprovalPolicy
    ) -> Bool

    /// Request approval (may be async if user interaction needed)
    func requestApproval(
        _ request: ApprovalRequest
    ) async throws -> ApprovalDecision
}

public struct ApprovalPolicy {
    /// Minimum risk level that requires approval
    var approvalThreshold: RiskLevel

    /// Auto-approve patterns (trusted commands)
    var autoApprovePatterns: [String]

    /// Never approve patterns (dangerous)
    var neverApprovePatterns: [String]
}
```

### A2A Protocol

Agent-to-Agent communication for task delegation:

```swift
/// Task sent between agents
public struct A2ATask: Codable {
    let id: TaskID
    let from: AgentID
    let to: AgentID?  // nil = broadcast
    let type: TaskType
    let payload: TaskPayload
    let state: TaskState
}

/// A2A server for receiving tasks
public actor A2AServer {
    func handleTask(_ task: A2ATask) async throws -> TaskResult
    func delegateTask(_ task: A2ATask, to agent: AgentID) async throws
}
```

### Why Swift?

1. **Performance**: Native compilation, no runtime overhead
2. **Concurrency**: Swift actors for safe concurrent agent execution
3. **Integration**: Direct access to Apple frameworks (EventKit, CloudKit, etc.)
4. **Memory safety**: No GC pauses during inference
5. **Distribution**: Single binary, no dependency management for users

---

## Core Architecture

### 1. Agent Identity & Memory

Each agent has its own persistent identity and memory:

```
~/Library/Mobile Documents/com~apple~CloudDocs/
└── .agents/
    ├── {agent-id}/
    │   ├── identity.json      # Agent configuration, capabilities, trust level
    │   ├── memory/            # Long-term memory (vector store, summaries)
    │   ├── learnings/         # User corrections, preferences, patterns
    │   └── context/           # Active working context
    └── shared/
        └── user-profile.json  # Cross-agent user preferences
```

**Key Insight**: Agents are first-class citizens with their own "home directories" - not ephemeral processes.

### 2. Context Hierarchy

Context flows through three levels:

```
┌─────────────────────────────────────────────────────────┐
│                    USER CONTEXT                          │
│  • User profile, preferences, communication style        │
│  • Cross-agent learnings                                 │
│  • iCloud native stores (Calendar, Reminders, etc.)      │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  WORKSPACE CONTEXT                       │
│  • ~/iCloud/Spaces/{workspace}/                          │
│  • Project-specific documents, artifacts                 │
│  • Shared agent configurations for this workspace        │
│  • Permission scopes (read-only vs read-write)           │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                   AGENT CONTEXT                          │
│  • Agent-specific memory and learnings                   │
│  • Current task state                                    │
│  • Subagent orchestration                                │
└─────────────────────────────────────────────────────────┘
```

### 3. Workspace Structure

Workspaces are the organizing unit for context and collaboration:

```
~/Library/Mobile Documents/com~apple~CloudDocs/
└── Spaces/
    ├── Personal/
    │   ├── .space.json         # Workspace config, agent permissions
    │   ├── .history/           # Git-like history for all artifacts
    │   ├── artifacts/          # Agent-generated outputs
    │   └── context/            # Workspace-level context files
    │
    ├── Work - Project Alpha/
    │   ├── .space.json
    │   ├── .history/
    │   ├── documents/
    │   └── artifacts/
    │
    └── Shared - Family/
        └── ...
```

---

## Native Integration via MCP

### iCloud Native Stores as MCP Servers

Each Apple framework becomes an MCP server, exposing existing data without duplication:

| Store | MCP Server | Capabilities |
|-------|------------|--------------|
| Calendar | `calendar-mcp` | Read/write events, availability |
| Reminders | `reminders-mcp` | Task management, lists |
| Notes | `notes-mcp` | Read/write notes, folders |
| Mail | `mail-mcp` | Read, draft, send (with approval) |
| Messages | `messages-mcp` | Read history, draft (with approval) |
| Photos | `photos-mcp` | Search, albums, metadata |
| Files | `files-mcp` | iCloud Drive access |
| Contacts | `contacts-mcp` | Contact lookup, relationships |

### AppIntent MCP Proxy

Any AppIntent-enabled app becomes agent-accessible:

```swift
// AppIntent exposed as MCP tool
@available(macOS 15.0, *)
struct AppIntentMCPProxy {
    /// Discovers and exposes AppIntents as MCP tools
    /// with transparent approval flow
    func discoverIntents(for bundleId: String) -> [MCPTool]

    /// Executes an intent with HITL approval if required
    func execute(_ intent: AppIntent, approvalLevel: TrustLevel) async throws
}
```

This means agents can interact with *any* app that supports AppIntents, making the agent framework a universal automation layer.

---

## Trust & Autonomy Model

### The Employee Onboarding Metaphor

Agents don't request "permissions" - they earn "trust levels" through demonstrated behavior:

```
┌────────────────────────────────────────────────────────────────┐
│                        TRUST LEVELS                             │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Level 0: OBSERVER                                              │
│  • Read-only access to context                                  │
│  • Cannot modify any data                                       │
│  • All outputs are suggestions only                             │
│                                                                 │
│  Level 1: ASSISTANT                                             │
│  • Can create new artifacts in workspace                        │
│  • Cannot modify existing documents                             │
│  • Drafts require explicit approval                             │
│                                                                 │
│  Level 2: CONTRIBUTOR                                           │
│  • Can modify documents within workspace                        │
│  • Changes written to staging (worktree pattern)                │
│  • Batch approval for related changes                           │
│                                                                 │
│  Level 3: TRUSTED                                               │
│  • Direct write access within workspace                         │
│  • Automatic approval for low-risk operations                   │
│  • HITL only for high-risk (send email, delete, etc.)           │
│                                                                 │
│  Level 4: AUTONOMOUS                                            │
│  • Full autonomy within defined boundaries                      │
│  • Proactive actions allowed                                    │
│  • User notification (not approval) for most actions            │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

### Trust Building Mechanisms

1. **Interaction History**: Track successful vs problematic interactions
2. **User Feedback**: Explicit corrections feed back into agent learning
3. **Outcome Validation**: Did the agent's actions achieve intended results?
4. **Scope Limitation**: Trust is contextual - trusted for calendar, not for email

### Non-Destructive Operations

All agent writes follow a staging model:

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Agent Writes    │────▶│  Staging Area    │────▶│  User's Live     │
│  (worktree)      │     │  (diff visible)  │     │  Documents       │
└──────────────────┘     └──────────────────┘     └──────────────────┘
                                  │
                                  ▼
                         ┌──────────────────┐
                         │  Full History    │
                         │  (git-backed)    │
                         └──────────────────┘
```

- Every change is versioned
- Full rollback capability
- Diff view before committing
- Batch operations for related changes

---

## User Experience

### Primary Interface: Artifact-Driven Chat

The desktop app centers on conversation, but produces *artifacts*:

```
┌─────────────────────────────────────────────────────────────────┐
│  ◀ Spaces ▼                              [Search] [+ New Chat]  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ 👤 You                                            9:42 AM │    │
│  │ Can you help me plan the Q2 product launch?              │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ 🤖 Atlas                                          9:42 AM │    │
│  │ I'll help with the Q2 launch. Based on your calendar    │    │
│  │ and last quarter's timeline, here's a draft plan:       │    │
│  │                                                          │    │
│  │ ┌─────────────────────────────────────────────────────┐ │    │
│  │ │ 📄 Q2-Launch-Plan.md                    [Open] [Edit]│ │    │
│  │ │ ─────────────────────────────────────────────────── │ │    │
│  │ │ ## Q2 Product Launch Plan                           │ │    │
│  │ │                                                     │ │    │
│  │ │ ### Timeline                                        │ │    │
│  │ │ - April 1-15: Feature freeze                       │ │    │
│  │ │ - April 16-30: Beta testing                        │ │    │
│  │ │ ...                                                 │ │    │
│  │ └─────────────────────────────────────────────────────┘ │    │
│  │                                                          │    │
│  │ I've also drafted calendar events. Review them?         │    │
│  │ [View Calendar Events] [Add to Calendar]                 │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Message Atlas...                              [Attach] ⏎  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Workspace Sidebar

```
┌────────────────────────┐
│ SPACES                 │
├────────────────────────┤
│ ▼ Personal             │
│   ◦ Daily Planning     │
│   ◦ Health & Fitness   │
│                        │
│ ▼ Work                 │
│   ★ Q2 Launch          │  ← Current
│   ◦ Team Standups      │
│   ◦ 1:1 Notes          │
│                        │
│ ▶ Family               │
│ ▶ Side Projects        │
│                        │
├────────────────────────┤
│ AGENTS                 │
├────────────────────────┤
│ 🤖 Atlas (Primary)     │
│    Trust: ████░░ L3    │
│                        │
│ 📊 Analyst             │
│    Trust: ██░░░░ L1    │
│                        │
│ ✍️ Writer              │
│    Trust: █████░ L4    │
│                        │
│ [+ Add Agent]          │
└────────────────────────┘
```

### Agent Training View

```
┌─────────────────────────────────────────────────────────────────┐
│  🤖 Atlas                                    [Settings] [Reset] │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  TRUST LEVEL                                                     │
│  ████████████████░░░░░░░░ Level 3: Trusted                      │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ CAPABILITIES                              TRUST    STATUS  │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ Read Calendar                             L0       ✓       │  │
│  │ Create Calendar Events                    L2       ✓       │  │
│  │ Modify Calendar Events                    L3       ✓       │  │
│  │ Read Email                                L1       ✓       │  │
│  │ Draft Email                               L2       ✓       │  │
│  │ Send Email                                L4       ○       │  │
│  │ Read Documents                            L0       ✓       │  │
│  │ Create Documents                          L1       ✓       │  │
│  │ Modify Documents                          L3       ✓       │  │
│  │ Delete Documents                          L4       ○       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  RECENT LEARNINGS                                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ • Prefers bullet points over paragraphs                   │  │
│  │ • Morning meetings should block 15min buffer after        │  │
│  │ • "Quick call" means 15 minutes                           │  │
│  │ • Never schedule over lunch (12-1pm)                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  INTERACTION STATS                                               │
│  • 847 successful interactions                                   │
│  • 12 corrections received (1.4% error rate)                    │
│  • Active for 45 days                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Compute Architecture

### The Privacy Guarantee

> **Your data can be used by agents, but never seen by anyone else.**

The key insight: MCP servers run *locally* on your device, accessing your Calendar, Mail, Notes directly via Apple frameworks. But the *context* assembled from that data can flow to private compute infrastructure for LLM processing:

```
┌─────────────────────────────────────────────────────────────────┐
│                        YOUR DEVICE                               │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    MCP Servers                           │    │
│  │   Calendar │ Mail │ Notes │ Files │ Reminders │ Apps    │    │
│  │            (Direct access to Apple frameworks)           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                             │                                    │
│                    Context Assembly                              │
│                             │                                    │
│                    ┌────────▼────────┐                          │
│                    │  Your Context   │                          │
│                    │  (assembled)    │                          │
│                    └────────┬────────┘                          │
└─────────────────────────────┼───────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Local      │    │   PCC        │    │   Private    │
│   (MLX)      │    │   (Apple)    │    │   Cloud      │
│              │    │              │    │   (future)   │
│  On-device   │    │  Encrypted   │    │  Encrypted   │
│  inference   │    │  in transit  │    │  E2E         │
│              │    │  & at rest   │    │              │
└──────────────┘    └──────────────┘    └──────────────┘
     100%                 100%              Varies by
    private             private             provider
```

### Privacy Tiers

| Tier | Compute Location | Data Guarantee | Use Case |
|------|------------------|----------------|----------|
| **Maximum** | Local only (MLX) | Never leaves device | Sensitive personal data |
| **Private** | Local or PCC | Apple's privacy guarantees | Default for most tasks |
| **Extended** | Private cloud providers | E2E encryption, no training | Complex tasks, verified providers |

**What PCC provides**:
- Your data is encrypted in transit and at rest
- Apple cannot see your data
- No data retention after processing
- Hardware-backed security guarantees
- Auditable by security researchers

This is the key differentiator: unlike cloud AI services where your data becomes training data or is accessible to the provider, PCC ensures your context is *used* but never *seen*.

### Hybrid Execution Model

```
┌─────────────────────────────────────────────────────────────────┐
│                    AGENTS RUNTIME                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   Local      │    │   PCC        │    │   Private    │      │
│  │   (MLX)      │◀──▶│   (Apple)    │◀──▶│   Cloud      │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                   │                   │                │
│         └───────────────────┴───────────────────┘                │
│                             │                                    │
│                    ┌────────▼────────┐                          │
│                    │  Secure Context │                          │
│                    │  (encrypted)    │                          │
│                    └─────────────────┘                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Execution Location Decision**:
- **Local (MLX)**: Fastest, maximum privacy, limited capability (smaller models)
- **PCC (Apple)**: Apple's secure compute, expanded capability, guaranteed privacy
- **Private Cloud**: Most capable models, E2E encryption, verified providers only

**Key Principle**: Context flows to compute, not vice versa. The same agent runs anywhere, with consistent memory and behavior, but your data is always protected.

### Context Handoff Protocol

```swift
struct SecureContextHandoff {
    /// Packages context for secure transmission
    func packageContext(
        agent: AgentIdentity,
        workspace: WorkspaceContext,
        task: TaskContext
    ) -> EncryptedContextBundle

    /// Determines optimal execution location
    func selectRuntime(
        task: TaskRequirements,
        userPreferences: RuntimePreferences
    ) -> RuntimeLocation

    /// Ensures context integrity after remote execution
    func validateAndMerge(
        result: ExecutionResult,
        originalContext: ContextBundle
    ) throws -> MergedContext
}
```

---

## The Agent App Store

### The Paradigm Shift

> **Apps are capabilities. Agents act with those capabilities.**

The app as we know it is really two things bundled together:
1. **Capabilities** - what the software can do (edit photos, manage tasks, send messages)
2. **Interface** - how humans interact with those capabilities

In the agent era, these decouple:
- **Apps become capability libraries** - collections of AppIntents and MCP tools
- **Agents become the actors** - orchestrating capabilities across multiple apps
- **UI becomes optional** - needed for human oversight, not for operation

This is already happening: apps like Shortcuts expose AppIntents, making their capabilities composable. Agents takes this further - every app's capabilities become tools that agents can use, with the app's UI becoming just one way to interact with those capabilities.

### Evolution of an App

```
┌─────────────────────────────────────────────────────────────────┐
│                    TODAY'S APP                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                      UI Layer                            │    │
│  │            (Human interacts with buttons)                │    │
│  └─────────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  Capabilities                            │    │
│  │            (Business logic, data, APIs)                  │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘

                              │
                              ▼

┌─────────────────────────────────────────────────────────────────┐
│                    TOMORROW'S APP                                │
│  ┌───────────────────┐  ┌───────────────────────────────────┐   │
│  │    UI Layer       │  │         Agent Interface           │   │
│  │  (Human access)   │  │   (AppIntents / MCP Tools)        │   │
│  └───────────────────┘  └───────────────────────────────────┘   │
│            │                           │                         │
│            └───────────┬───────────────┘                         │
│                        ▼                                         │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  Capabilities                            │    │
│  │            (Business logic, data, APIs)                  │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

Eventually, some apps may be **capability-only** - no UI at all, just a rich set of AppIntents and MCP tools that agents can use.

### Vision

Just as the App Store transformed software distribution, the Agent Store transforms automation:

| App Store | Agent Store |
|-----------|-------------|
| Apps you install | Agents you train |
| Permissions you grant | Trust you build |
| Data stays in apps | Context flows across agents |
| One-time purchase | Relationship over time |
| App does one thing | Agent coordinates many things |
| UI is primary | UI is oversight |

### Agent Marketplace

```
┌─────────────────────────────────────────────────────────────────┐
│  AGENT STORE                                          [Search]  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  FEATURED AGENTS                                                 │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │ 📧 Inbox    │ │ 📅 Schedule │ │ 💰 Finance  │               │
│  │ Zero       │ │ Optimizer  │ │ Tracker    │               │
│  │ ★★★★☆ 4.2  │ │ ★★★★★ 4.8  │ │ ★★★★☆ 4.1  │               │
│  │ [Install]   │ │ [Install]   │ │ [Install]   │               │
│  └─────────────┘ └─────────────┘ └─────────────┘               │
│                                                                  │
│  CATEGORIES                                                      │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Productivity │ Finance │ Health │ Creative │ Developer │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  WHAT MAKES A GOOD AGENT                                         │
│  • Clear capability scope                                        │
│  • Transparent about data access                                 │
│  • Learns from your corrections                                  │
│  • Respects trust boundaries                                     │
│  • Interoperates with other agents                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Agent Development Kit

```swift
// Define an agent for the marketplace
@Agent("inbox-zero")
struct InboxZeroAgent: MarketplaceAgent {
    static let metadata = AgentMetadata(
        name: "Inbox Zero",
        description: "Helps achieve and maintain inbox zero",
        category: .productivity,
        requiredCapabilities: [.mail(.read), .mail(.draft)],
        optionalCapabilities: [.mail(.send), .calendar(.read)]
    )

    // Base personality and instructions
    @SystemPrompt
    var baseInstructions: String {
        """
        You help users achieve inbox zero by:
        - Categorizing emails by urgency and type
        - Drafting quick replies
        - Suggesting emails that can be archived
        - Learning the user's email handling preferences
        """
    }

    // Agent-specific tools
    @Tool
    func categorizeInbox() async -> [EmailCategory]

    @Tool
    func draftReply(to email: Email, style: ReplyStyle) async -> DraftEmail
}
```

---

## Technical Requirements Summary

### Infrastructure (AgentKit)

- [x] LLM Provider abstraction (local, cloud, CLI)
- [x] Tool system with approval levels
- [x] A2A protocol for agent communication
- [x] Human-in-the-loop approval system
- [ ] Agent identity and persistence
- [ ] Context encryption and handoff
- [ ] Trust level management
- [ ] Git-backed artifact history

### Native Integration

- [ ] iCloud MCP servers (Calendar, Reminders, Notes, Mail, etc.)
- [ ] AppIntent MCP proxy
- [ ] Secure workspace management
- [ ] Cross-device sync

### User Experience

- [ ] Desktop app with artifact-driven chat
- [ ] Workspace management UI
- [ ] Agent training and trust visualization
- [ ] Approval flow UI

### Marketplace

- [ ] Agent packaging format
- [ ] Distribution infrastructure
- [ ] Review and safety process
- [ ] Usage analytics and trust metrics

---

## Open Questions

1. **Naming**: What do we call "Spaces"? Alternatives: Contexts, Domains, Scopes, Areas
2. **Trust Granularity**: Per-capability trust or overall agent trust?
3. **Multi-Device**: How do agents coordinate across Mac/iPhone/iPad?
4. **Offline**: How much capability when disconnected?
5. **Sharing**: How do users share agents with learned behaviors?
6. **Enterprise**: How does this extend to organizational use?

---

## Next Steps

1. **Refine Core Concepts**: Validate naming, trust model, context hierarchy
2. **Prototype Key Flows**: Agent training UX, artifact creation, approval flow
3. **Build MCP Servers**: Start with Calendar and Reminders as proof of concept
4. **Security Review**: Context encryption, PCC integration, privacy guarantees
5. **Pitch Deck**: Distill into executive presentation

---

*Document Version: 0.1*
*Last Updated: January 2025*
*Status: Draft for Review*
