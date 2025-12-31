# AgentKit Technical Specification

**Version**: 0.1.0 (Draft)
**Status**: Design Phase
**Based On**: Claude Agent SDK, Microsoft Agent Framework

---

## Overview

AgentKit is a Swift-native agent framework for Apple platforms. It combines the tool-centric simplicity of Claude's Agent SDK with the orchestration power of Microsoft's Agent Framework, adapted for Swift's concurrency model and Apple's ecosystem.

---

## Core Principles

1. **Swift-First**: Leverage Swift concurrency (actors, async/await, AsyncSequence)
2. **Protocol-Oriented**: Composable via protocols, not inheritance
3. **Type-Safe**: Compile-time guarantees where possible
4. **Apple-Native**: iCloud, AppIntents, Shortcuts integration
5. **Interoperable**: A2A protocol for external agents

---

## Module Structure

```
AgentKit/
├── Core/
│   ├── Agent.swift           # Agent protocol and base types
│   ├── AgentLoop.swift       # Execution loop engine
│   ├── AgentEvent.swift      # Event stream types
│   └── AgentError.swift      # Error types
├── Tools/
│   ├── Tool.swift            # Tool protocol
│   ├── ToolMacro.swift       # @Tool macro
│   ├── ToolRegistry.swift    # Tool discovery and registration
│   └── BuiltIn/              # Built-in tools
│       ├── ReadTool.swift
│       ├── WriteTool.swift
│       ├── BashTool.swift
│       └── ...
├── Context/
│   ├── Context.swift         # Context protocol
│   ├── ContextManager.swift  # Window management, compaction
│   └── Memory.swift          # Long-term memory/RAG
├── Session/
│   ├── Session.swift         # Session actor
│   ├── SessionStore.swift    # Persistence (iCloud)
│   └── Message.swift         # Message types
├── Hooks/
│   ├── Hook.swift            # Hook protocol
│   ├── HookRunner.swift      # Hook execution
│   └── HookEvent.swift       # Event types
├── Orchestration/
│   ├── Orchestrator.swift    # Orchestrator protocol
│   ├── Sequential.swift
│   ├── Concurrent.swift
│   ├── Handoff.swift
│   └── GroupChat.swift
├── Protocols/
│   ├── A2A/                  # Agent-to-Agent protocol
│   │   ├── A2AClient.swift
│   │   ├── A2AServer.swift
│   │   └── AgentCard.swift
│   └── MCP/                  # Model Context Protocol
│       ├── MCPServer.swift
│       └── MCPClient.swift
└── Integration/
    ├── AppIntents/           # Shortcuts integration
    ├── SwiftUI/              # UI components
    └── iCloud/               # Storage
```

---

## Core Types

### Agent Protocol

```swift
/// Core agent abstraction
public protocol Agent: Actor {
    /// Unique identifier
    var id: AgentID { get }

    /// Agent configuration
    var configuration: AgentConfiguration { get }

    /// Execute a task, streaming events
    func execute(_ task: AgentTask) -> AgentEventStream

    /// Lifecycle control
    func pause() async
    func resume() async
    func cancel() async
}

/// Type alias for event stream
public typealias AgentEventStream = AsyncThrowingStream<AgentEvent, Error>
```

### Agent Events

```swift
/// Events emitted during agent execution
public enum AgentEvent: Sendable {
    // Lifecycle
    case started(AgentTask)
    case completed(AgentResult)
    case failed(AgentError)
    case cancelled

    // Execution
    case thinking(String)
    case toolCall(ToolCall)
    case toolResult(ToolResult)
    case message(Message)

    // Context
    case contextCompacted(from: Int, to: Int)

    // Subagents
    case subagentSpawned(AgentID, AgentTask)
    case subagentCompleted(AgentID, AgentResult)
}
```

### Agent Configuration

```swift
/// Configuration for agent behavior
public struct AgentConfiguration: Sendable {
    /// System prompt defining agent role
    public var systemPrompt: String?

    /// Tools the agent can use
    public var allowedTools: Set<ToolID>
    public var disallowedTools: Set<ToolID>

    /// Permission mode for tool execution
    public var permissionMode: PermissionMode

    /// Maximum turns before stopping
    public var maxTurns: Int?

    /// Registered hooks
    public var hooks: HookConfiguration

    /// MCP server connections
    public var mcpServers: [String: MCPServerConfiguration]

    /// Subagent definitions
    public var subagents: [String: SubagentDefinition]

    /// LLM provider configuration
    public var llmProvider: LLMProvider
}

public enum PermissionMode: Sendable {
    case ask           // Ask user for each tool use
    case acceptReads   // Auto-approve read operations
    case acceptEdits   // Auto-approve read and write
    case bypass        // No permission checks
}
```

---

## Tool System

### Tool Protocol

```swift
/// A capability that agents can invoke
public protocol Tool: Sendable {
    /// Tool identifier
    static var id: ToolID { get }

    /// Human-readable description
    static var description: String { get }

    /// Parameter schema for validation
    static var parameters: ToolParameters { get }

    /// Execute the tool with given input
    func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput
}

/// Tool input/output types
public struct ToolInput: Sendable {
    public let parameters: [String: ToolValue]
}

public struct ToolOutput: Sendable {
    public let content: [ToolContent]
    public let metadata: [String: String]?
}

public enum ToolContent: Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case file(URL)
    case structured([String: ToolValue])
}
```

### @Tool Macro

```swift
/// Macro for declarative tool definition
@attached(peer, names: suffixed(Tool))
@attached(extension, conformances: Tool)
public macro Tool(_ description: String) = #externalMacro(...)

// Usage:
@Tool("Search the web for information")
func webSearch(
    @Param("Search query") query: String,
    @Param("Maximum results") limit: Int = 10
) async throws -> [SearchResult] {
    // Implementation
}

// Expands to:
struct WebSearchTool: Tool {
    static let id: ToolID = "webSearch"
    static let description = "Search the web for information"
    static let parameters = ToolParameters([
        .init(name: "query", type: .string, description: "Search query", required: true),
        .init(name: "limit", type: .int, description: "Maximum results", default: .int(10))
    ])

    func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let query = try input.require("query", as: String.self)
        let limit = input.get("limit", default: 10)
        let results = try await webSearch(query: query, limit: limit)
        return ToolOutput(content: [.structured(results.encoded)])
    }
}
```

### Built-in Tools

| Tool | Description | Apple Integration |
|------|-------------|-------------------|
| `Read` | Read file contents | FileManager, iCloud |
| `Write` | Create/overwrite files | FileManager, iCloud |
| `Edit` | Precise file edits | FileManager |
| `Bash` | Run shell commands | Process |
| `Glob` | Find files by pattern | FileManager |
| `Grep` | Search file contents | NSRegularExpression |
| `WebSearch` | Search the web | URLSession |
| `WebFetch` | Fetch web content | URLSession |
| `Task` | Spawn subagent | AgentKit |

---

## Hook System

### Hook Protocol

```swift
/// Lifecycle hook for intercepting agent behavior
public protocol Hook: Sendable {
    /// Events this hook responds to
    var events: Set<HookEventType> { get }

    /// Optional matcher for filtering (e.g., specific tools)
    var matcher: HookMatcher? { get }

    /// Execute the hook
    func execute(_ event: HookEvent, context: HookContext) async throws -> HookResult
}

public enum HookEventType: Sendable {
    case preToolUse
    case postToolUse
    case sessionStart
    case sessionEnd
    case agentStop
    case userPromptSubmit
    case preCompact
}

public enum HookResult: Sendable {
    case allow
    case deny(reason: String)
    case transform(ToolInput)
    case skip  // Skip remaining hooks
}
```

### Hook Configuration

```swift
public struct HookConfiguration: Sendable {
    public var preToolUse: [Hook]
    public var postToolUse: [Hook]
    public var sessionStart: [Hook]
    public var sessionEnd: [Hook]
    public var agentStop: [Hook]

    public static let empty = HookConfiguration(...)
}

// Usage example:
let auditHook = AuditHook(logFile: auditURL)
let config = AgentConfiguration(
    hooks: HookConfiguration(
        postToolUse: [auditHook]
    )
)
```

---

## Session Management

### Session Actor

```swift
/// Manages conversation state for an agent
public actor AgentSession {
    public let id: SessionID
    public private(set) var messages: [Message]
    public private(set) var state: SessionState

    /// Create a new session
    public init(id: SessionID = .init())

    /// Append a message
    public func append(_ message: Message)

    /// Fork session for exploration
    public func fork() -> AgentSession

    /// Serialize for persistence
    public func serialize() throws -> Data

    /// Restore from serialized data
    public static func restore(from data: Data) throws -> AgentSession
}

public enum SessionState: Sendable {
    case idle
    case running(AgentTask)
    case paused(AgentTask)
    case completed(AgentResult)
    case failed(AgentError)
}
```

### iCloud Persistence

```swift
/// Session store backed by iCloud
public actor SessionStore {
    private let container: URL  // iCloud container

    /// Save session to iCloud
    public func save(_ session: AgentSession) async throws

    /// Load session from iCloud
    public func load(id: SessionID) async throws -> AgentSession?

    /// List all sessions
    public func list() async throws -> [SessionID]

    /// Delete session
    public func delete(id: SessionID) async throws
}
```

---

## Orchestration

### Orchestrator Protocol

```swift
/// Coordinates multiple agents
public protocol Orchestrator: Sendable {
    func orchestrate(
        _ agents: [any Agent],
        task: AgentTask,
        context: OrchestrationContext
    ) -> AgentEventStream
}
```

### Built-in Orchestrators

```swift
/// Execute agents in sequence, passing output as input
public struct SequentialOrchestrator: Orchestrator {
    public func orchestrate(...) -> AgentEventStream
}

/// Execute agents in parallel, aggregate results
public struct ConcurrentOrchestrator: Orchestrator {
    public let aggregator: ResultAggregator
    public func orchestrate(...) -> AgentEventStream
}

/// Agents can delegate to each other
public struct HandoffOrchestrator: Orchestrator {
    public func orchestrate(...) -> AgentEventStream
}

/// Multi-agent conversation
public struct GroupChatOrchestrator: Orchestrator {
    public let moderator: Moderator?
    public func orchestrate(...) -> AgentEventStream
}
```

---

## A2A Protocol Integration

### Agent Card

```swift
/// A2A Agent Card for capability advertisement
public struct AgentCard: Codable, Sendable {
    public let name: String
    public let description: String
    public let version: String
    public let capabilities: [Capability]
    public let endpoint: URL
    public let authentication: AuthRequirement?
}
```

### A2A Client/Server

```swift
/// Client for calling external A2A agents
public actor A2AClient {
    public func discover(_ endpoint: URL) async throws -> AgentCard
    public func sendTask(_ task: A2ATask, to agent: AgentCard) async throws -> TaskHandle
    public func getStatus(_ handle: TaskHandle) async throws -> TaskStatus
    public func streamResult(_ handle: TaskHandle) -> AsyncThrowingStream<A2AMessage, Error>
    public func cancel(_ handle: TaskHandle) async throws
}

/// Server for receiving A2A tasks
public protocol A2AServer {
    var agentCard: AgentCard { get }
    func handleTask(_ task: A2ATask) async throws -> A2ATaskResult
}
```

---

## Simple API

### One-Shot Query

```swift
import AgentKit

// Simple one-shot query
for try await event in Agent.query("Find and fix the bug in auth.swift") {
    switch event {
    case .message(let msg):
        print(msg.content)
    case .toolCall(let call):
        print("Using tool: \(call.tool)")
    case .completed(let result):
        print("Done: \(result)")
    default:
        break
    }
}
```

### Configured Agent

```swift
let config = AgentConfiguration(
    systemPrompt: "You are a code review expert.",
    allowedTools: [.read, .glob, .grep],
    permissionMode: .acceptReads
)

let agent = ChatAgent(configuration: config)
let session = AgentSession()

for try await event in agent.execute(.init(
    prompt: "Review this codebase for security issues",
    session: session
)) {
    handle(event)
}

// Session persists for follow-up
try await SessionStore.default.save(session)
```

### Custom Tool

```swift
@Tool("Get current weather for a location")
func getWeather(
    @Param("City name") city: String,
    @Param("Temperature unit") unit: TemperatureUnit = .celsius
) async throws -> WeatherReport {
    let response = try await weatherAPI.fetch(city: city)
    return WeatherReport(
        temperature: response.temp.converted(to: unit),
        conditions: response.conditions
    )
}

// Register and use
let config = AgentConfiguration(
    allowedTools: [.read, .custom("getWeather")],
    customTools: [GetWeatherTool()]
)
```

---

## Apple Integration

### AppIntents

```swift
import AppIntents
import AgentKit

struct RunAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Agent Task"

    @Parameter(title: "Task")
    var task: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var result = ""
        for try await event in Agent.query(task) {
            if case .completed(let r) = event {
                result = r.summary
            }
        }
        return .result(value: result)
    }
}
```

### SwiftUI Components

```swift
import SwiftUI
import AgentKitUI

struct AgentChatView: View {
    @StateObject var agent = AgentViewModel()

    var body: some View {
        AgentChat(agent: agent)
            .agentToolbar()
    }
}
```

---

## Open Questions

1. **Error Recovery**: How do we handle partial failures mid-task?
2. **Background Execution**: iOS limits — use BGTaskScheduler?
3. **Cost Attribution**: Track token usage per agent/task?
4. **Sandboxing**: How strict for tool execution?
5. **Local LLM**: Which on-device models to support?

---

## Next Steps

1. Implement `Agent` protocol and basic loop
2. Implement `Tool` protocol and @Tool macro
3. Implement `Session` with iCloud persistence
4. Add built-in tools (Read, Write, Bash, Glob, Grep)
5. Add A2A client for external agent calls

---

## References

- [Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Microsoft Agent Framework](https://learn.microsoft.com/en-us/agent-framework/overview/agent-framework-overview)
- [A2A Protocol](https://github.com/a2aproject/A2A)
- [MCP Specification](https://modelcontextprotocol.io/)
