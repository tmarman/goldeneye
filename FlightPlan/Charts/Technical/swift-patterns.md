# Swift Patterns for AgentKit

## Concurrency Model

AgentKit uses Swift's structured concurrency throughout. Key patterns:

### Agent as Actor

```swift
actor AgentExecutor {
    private var state: AgentState
    private var currentTask: Task<Void, Never>?

    func execute(_ agentTask: AgentTask) async throws -> TaskResult {
        // Isolated state mutation
        state = .running(agentTask)

        // Structured child tasks for tools
        return try await withTaskGroup(of: ToolResult.self) { group in
            for tool in agentTask.requiredTools {
                group.addTask {
                    try await tool.execute()
                }
            }
            // Aggregate results...
        }
    }

    func cancel() {
        currentTask?.cancel()
    }
}
```

### AsyncSequence for Streaming

```swift
struct AgentOutputStream: AsyncSequence {
    typealias Element = AgentEvent

    // Stream events as agent executes
    // - .thinking(String)
    // - .toolCall(Tool, Parameters)
    // - .toolResult(ToolResult)
    // - .response(String)
    // - .complete(TaskResult)
}
```

## Tool Definition Pattern

Using Swift macros for ergonomic tool definition:

```swift
@Tool("Search the web for information")
func webSearch(
    @Param("Search query") query: String,
    @Param("Maximum results", default: 10) limit: Int
) async throws -> [SearchResult] {
    // Implementation
}
```

Expands to:
```swift
struct WebSearchTool: Tool {
    static let name = "webSearch"
    static let description = "Search the web for information"
    static let parameters: [ToolParameter] = [
        .init(name: "query", type: .string, description: "Search query", required: true),
        .init(name: "limit", type: .integer, description: "Maximum results", default: 10)
    ]

    func execute(with args: [String: Any]) async throws -> ToolResult {
        // Generated implementation wrapper
    }
}
```

## State Persistence Pattern

File-based with Codable:

```swift
struct AgentState: Codable {
    let id: AgentID
    var status: AgentStatus
    var context: AgentContext
    var taskHistory: [CompletedTask]

    // Automatic iCloud persistence
    func save() async throws {
        let url = AgentStorage.url(for: id)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url)
        // iCloud handles sync
    }

    static func load(id: AgentID) async throws -> AgentState {
        let url = AgentStorage.url(for: id)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AgentState.self, from: data)
    }
}
```

## Error Handling Pattern

Typed errors with recovery suggestions:

```swift
enum AgentError: Error {
    case toolFailed(Tool, underlying: Error, recovery: RecoveryStrategy?)
    case contextOverflow(current: Int, max: Int)
    case cancelled
    case timeout(after: Duration)
    case externalAgentUnavailable(AgentCard)
}

enum RecoveryStrategy {
    case retry(after: Duration)
    case fallback(to: Tool)
    case askUser(question: String)
    case abort
}
```

## A2A Message Types

```swift
// Based on A2A spec
struct A2AMessage: Codable {
    let jsonrpc: String = "2.0"
    let id: String
    let method: A2AMethod
    let params: A2AParams
}

enum A2AMethod: String, Codable {
    case sendTask = "tasks/send"
    case getStatus = "tasks/get"
    case cancel = "tasks/cancel"
    case getAgentCard = "agent/card"
}

struct AgentCard: Codable {
    let name: String
    let description: String
    let capabilities: [Capability]
    let endpoint: URL
    let authentication: AuthRequirement?
}
```

## Testing Patterns

```swift
// Mock tools for testing
class MockTool: Tool {
    var callCount = 0
    var lastArgs: [String: Any]?
    var resultToReturn: ToolResult

    func execute(with args: [String: Any]) async throws -> ToolResult {
        callCount += 1
        lastArgs = args
        return resultToReturn
    }
}

// Agent test harness
@MainActor
class AgentTestCase: XCTestCase {
    var agent: TestableAgent!
    var mockLLM: MockLLMProvider!
    var mockStorage: MockStorage!

    override func setUp() {
        mockLLM = MockLLMProvider()
        mockStorage = MockStorage()
        agent = TestableAgent(llm: mockLLM, storage: mockStorage)
    }
}
```
