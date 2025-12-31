# SDK Architecture Comparison: Claude Agent SDK vs Microsoft Agent Framework

## Executive Summary

Both frameworks represent state-of-the-art agent architecture patterns. This document extracts applicable patterns for AgentKit's Swift implementation.

| Aspect | Claude Agent SDK | Microsoft Agent Framework |
|--------|------------------|---------------------------|
| **Philosophy** | Tool-centric (agent = LLM + tools) | Orchestration-centric (agents = graph nodes) |
| **Language** | Python/TypeScript | C#/Python/Java |
| **Tool Protocol** | MCP (Model Context Protocol) | Plugins + MCP support |
| **State Model** | Sessions (resumable, forkable) | AgentThread abstraction |
| **Multi-Agent** | Subagents via Task tool | Orchestration patterns (5 built-in) |
| **License** | Commercial ToS | MIT |

---

## Claude Agent SDK Architecture

### Core Loop Pattern

```
┌─────────────────────────────────────────────────┐
│                  Agent Loop                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ Gather   │→ │  Take    │→ │  Verify  │→ ... │
│  │ Context  │  │  Action  │  │  Work    │      │
│  └──────────┘  └──────────┘  └──────────┘      │
└─────────────────────────────────────────────────┘
```

### Key Abstractions

#### 1. `query()` Function
Simple async generator for one-shot agent execution:
```python
async for message in query(prompt="...", options=options):
    handle(message)
```

#### 2. `ClaudeSDKClient`
Stateful client for multi-turn conversations:
```python
async with ClaudeSDKClient(options) as client:
    await client.query("...")
    async for msg in client.receive_response():
        handle(msg)
```

#### 3. Tools (Built-in)
| Tool | Purpose |
|------|---------|
| Read | Read files |
| Write | Create files |
| Edit | Modify files |
| Bash | Run commands |
| Glob | Find files by pattern |
| Grep | Search file contents |
| WebSearch | Search the web |
| WebFetch | Fetch web content |
| Task | Spawn subagents |

#### 4. Custom Tools via MCP
```python
@tool("name", "description", {"param": type})
async def my_tool(args):
    return {"content": [{"type": "text", "text": "result"}]}
```

#### 5. Hooks System
Lifecycle interception points:
- `PreToolUse` - Before tool execution (can block)
- `PostToolUse` - After tool execution (can log/transform)
- `SessionStart` / `SessionEnd`
- `UserPromptSubmit`
- `Stop`

#### 6. Sessions
- Resumable via `session_id`
- Full context preservation
- Forkable for exploration

### Configuration Model
```python
ClaudeAgentOptions(
    system_prompt="...",
    allowed_tools=["Read", "Write", "Bash"],
    permission_mode="acceptEdits",
    max_turns=10,
    mcp_servers={...},
    hooks={...},
    agents={...}  # Subagent definitions
)
```

---

## Microsoft Agent Framework Architecture

### Core Abstractions

#### 1. Agent (Base Class)
Abstract foundation for all agent types:
```csharp
public abstract class Agent {
    public abstract Task<AgentResponse> InvokeAsync(...);
}
```

#### 2. Agent Types
| Type | Purpose |
|------|---------|
| ChatCompletionAgent | Standard chat-based |
| OpenAIAssistantAgent | OpenAI Assistants API |
| AzureAIAgent | Azure AI services |
| CopilotStudioAgent | Copilot Studio integration |

#### 3. AgentThread
Conversation state abstraction:
- **Stateful**: State stored in service, accessed via ID
- **Stateless**: Full history passed each invocation
- Type-matched: AzureAIAgent requires AzureAIAgentThread

#### 4. Orchestration Patterns
```
┌─────────────────────────────────────────────────┐
│            Orchestration Layer                   │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐     │
│  │Sequential │ │Concurrent │ │  Handoff  │     │
│  └───────────┘ └───────────┘ └───────────┘     │
│  ┌───────────┐ ┌───────────┐                   │
│  │Group Chat │ │ Magentic  │                   │
│  └───────────┘ └───────────┘                   │
└─────────────────────────────────────────────────┘
```

- **Sequential**: Agents execute in order
- **Concurrent**: Agents execute in parallel
- **Handoff**: Agents delegate to each other
- **Group Chat**: Multi-agent collaboration
- **Magentic**: Dynamic pattern selection

#### 5. Plugins & Functions
```csharp
[KernelFunction("search")]
public async Task<string> Search(string query) { ... }
```

#### 6. Message Model
- `ChatHistory` - Conversation container
- `ChatMessageContent` - Individual messages
- `StreamingKernelContent` - Streaming support
- `FileReferenceContent` - File attachments

### Graph-Based Architecture
```
┌────────────────────────────────────────┐
│           Workflow Graph                │
│    ┌───┐      ┌───┐      ┌───┐        │
│    │ A │ ───→ │ B │ ───→ │ C │        │
│    └───┘      └─┬─┘      └───┘        │
│                 │ (conditional)        │
│                 ↓                      │
│              ┌───┐                     │
│              │ D │                     │
│              └───┘                     │
└────────────────────────────────────────┘
```

---

## Pattern Extraction for AgentKit

### 1. Agent Protocol (from both)

```swift
protocol Agent {
    var id: AgentID { get }
    var configuration: AgentConfiguration { get }

    func execute(_ task: AgentTask) -> AsyncThrowingStream<AgentEvent, Error>
    func pause() async
    func resume() async
    func cancel() async
}
```

### 2. Tool System (from Claude SDK + MCP)

```swift
@Tool("description")
func searchWeb(query: String, limit: Int = 10) async throws -> [SearchResult]

// Expands to:
struct SearchWebTool: Tool {
    static let schema = ToolSchema(
        name: "searchWeb",
        description: "description",
        parameters: [
            .init(name: "query", type: .string, required: true),
            .init(name: "limit", type: .integer, default: 10)
        ]
    )

    func execute(_ input: ToolInput) async throws -> ToolOutput
}
```

### 3. Hook System (from Claude SDK)

```swift
protocol Hook {
    func shouldExecute(for event: HookEvent) -> Bool
    func execute(_ context: HookContext) async throws -> HookResult
}

enum HookEvent {
    case preToolUse(Tool, ToolInput)
    case postToolUse(Tool, ToolOutput)
    case sessionStart(Session)
    case sessionEnd(Session)
    case agentStop(StopReason)
}

enum HookResult {
    case allow
    case deny(reason: String)
    case transform(ToolInput)
}
```

### 4. Orchestration Patterns (from Microsoft)

```swift
protocol Orchestrator {
    func orchestrate(_ agents: [Agent], task: AgentTask) -> AsyncThrowingStream<AgentEvent, Error>
}

struct SequentialOrchestrator: Orchestrator { ... }
struct ConcurrentOrchestrator: Orchestrator { ... }
struct HandoffOrchestrator: Orchestrator { ... }
struct GroupChatOrchestrator: Orchestrator { ... }
```

### 5. Session/Thread Model (hybrid)

```swift
actor AgentSession {
    let id: SessionID
    private(set) var history: [Message]
    private(set) var state: SessionState

    func append(_ message: Message) async
    func fork() async -> AgentSession
    func serialize() async throws -> Data
    static func restore(from data: Data) async throws -> AgentSession
}
```

### 6. Configuration Model (from Claude SDK)

```swift
struct AgentConfiguration {
    var systemPrompt: String?
    var allowedTools: Set<ToolName>
    var disallowedTools: Set<ToolName>
    var permissionMode: PermissionMode
    var maxTurns: Int?
    var mcpServers: [String: MCPServerConfig]
    var hooks: [HookEvent: [Hook]]
    var subagents: [String: AgentDefinition]
}
```

---

## Recommended AgentKit Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AgentKit                                 │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │   Agents    │  │    Tools    │  │   Hooks     │             │
│  │  Protocol   │  │   System    │  │   System    │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
│         │                │                │                     │
│  ┌──────┴────────────────┴────────────────┴──────┐             │
│  │              Agent Runtime                     │             │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐       │             │
│  │  │  Loop   │  │ Context │  │ Session │       │             │
│  │  │ Engine  │  │ Manager │  │ Manager │       │             │
│  │  └─────────┘  └─────────┘  └─────────┘       │             │
│  └──────────────────────────────────────────────┘             │
│                          │                                     │
│  ┌───────────────────────┴───────────────────────┐             │
│  │            Orchestration Layer                 │             │
│  │  Sequential │ Concurrent │ Handoff │ GroupChat│             │
│  └───────────────────────────────────────────────┘             │
│                          │                                     │
│  ┌───────────────────────┴───────────────────────┐             │
│  │            Protocol Adapters                   │             │
│  │         A2A  │  MCP  │  Local                 │             │
│  └───────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Sources

- [Claude Agent SDK Overview](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Claude Agent SDK Python GitHub](https://github.com/anthropics/claude-agent-sdk-python)
- [Microsoft Semantic Kernel Agent Architecture](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-architecture)
- [Microsoft Agent Framework Overview](https://learn.microsoft.com/en-us/agent-framework/overview/agent-framework-overview)
- [Semantic Kernel + AutoGen Merger Announcement](https://visualstudiomagazine.com/articles/2025/10/01/semantic-kernel-autogen--open-source-microsoft-agent-framework.aspx)
