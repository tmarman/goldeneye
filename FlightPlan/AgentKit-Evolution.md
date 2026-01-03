# AgentKit Evolution Path
## From Foundation to Agents Platform (Codename: Goldeneye)

This document describes how AgentKit evolves to support the Agents vision, while remaining a general-purpose agent infrastructure library.

---

## Relationship: AgentKit vs Agents

```
┌─────────────────────────────────────────────────────────────────┐
│                      Agents (Goldeneye)                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Agents.app (macOS/iOS)                                     │  │
│  │ • Chat UI, Workspaces, Agent Training, Approvals           │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Agents Runtime                                             │  │
│  │ • Agent Identity & Memory                                  │  │
│  │ • Trust Management                                         │  │
│  │ • Workspace & Context System                               │  │
│  │ • Compute Routing (Local/PCC/Cloud)                        │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ AgentsMCP (Apple Frameworks)                               │  │
│  │ • Calendar, Reminders, Notes, Mail, Files                  │  │
│  │ • AppIntent Proxy                                          │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                               │
                               │ Uses
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                         AgentKit                                 │
│  (General-purpose agent infrastructure)                          │
│                                                                  │
│  • LLM Provider abstraction                                      │
│  • Tool system & execution                                       │
│  • Approval system (HITL)                                        │
│  • Agent loop (message → tool → response)                        │
│  • A2A protocol                                                  │
│  • MCP client                                                    │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight**: AgentKit is to Agents what UIKit is to an iOS app. AgentKit provides primitives; Agents builds a specific product on top.

---

## Current Package Structure

```
AgentKit/
├── Package.swift
├── Sources/
│   ├── AgentKit/                    # Core library
│   │   ├── Agent/                   # Agent loop, configuration
│   │   ├── Approval/                # HITL approval system
│   │   ├── A2A/                     # Agent-to-agent protocol
│   │   ├── LLM/                     # Provider abstraction
│   │   │   ├── Providers/           # Concrete implementations
│   │   │   └── LLMProvider.swift    # Core protocol
│   │   ├── Tools/                   # Tool system
│   │   └── Core/                    # Shared types
│   │
│   ├── AgentKitServer/              # HTTP server executable
│   ├── AgentKitCLI/                 # Command-line tool
│   └── AgentKitConsole/             # macOS dashboard app
│
└── Tests/
```

---

## Proposed Evolution

### Phase 1: Extend AgentKit Core

Add general-purpose primitives that Agents needs but that are useful to any agent:

```
AgentKit/
├── Sources/
│   ├── AgentKit/
│   │   ├── Agent/
│   │   ├── Approval/
│   │   ├── A2A/
│   │   ├── LLM/
│   │   ├── Tools/
│   │   ├── Core/
│   │   │
│   │   ├── Identity/                # NEW: Agent identity
│   │   │   ├── AgentIdentity.swift
│   │   │   ├── IdentityStore.swift
│   │   │   └── Capabilities.swift
│   │   │
│   │   ├── Memory/                  # NEW: Agent memory
│   │   │   ├── Memory.swift
│   │   │   ├── MemoryStore.swift
│   │   │   ├── VectorStore.swift
│   │   │   └── Embeddings.swift
│   │   │
│   │   ├── Trust/                   # NEW: Trust system
│   │   │   ├── TrustLevel.swift
│   │   │   ├── TrustManager.swift
│   │   │   └── TrustMetrics.swift
│   │   │
│   │   └── Context/                 # NEW: Context management
│   │       ├── ContextAssembler.swift
│   │       ├── ContextSource.swift
│   │       └── ContextEncryption.swift
```

**Why in AgentKit**: These are general agent concepts. Any agent system needs identity, memory, and trust. Not specific to Apple/Agents.

### Phase 2: Create Agents Package

A separate package that depends on AgentKit and adds Apple-specific functionality:

```
AgentKit/
├── Package.swift                    # Updated with Agents targets
├── Sources/
│   ├── AgentKit/                    # Core (unchanged API)
│   │
│   ├── Agents/                         # NEW: Agents runtime
│   │   ├── Runtime/
│   │   │   ├── AgentsRuntime.swift
│   │   │   ├── SessionManager.swift
│   │   │   └── ComputeRouter.swift
│   │   │
│   │   ├── Workspace/
│   │   │   ├── Workspace.swift
│   │   │   ├── WorkspaceManager.swift
│   │   │   ├── StagingManager.swift
│   │   │   └── HistoryManager.swift
│   │   │
│   │   ├── iCloud/
│   │   │   ├── iCloudSync.swift
│   │   │   └── AgentStorage.swift
│   │   │
│   │   └── PCC/                     # Private Cloud Compute
│   │       ├── PCCProvider.swift
│   │       └── PCCContextHandoff.swift
│   │
│   ├── AgentsMCP/                      # NEW: Apple MCP servers
│   │   ├── CalendarMCP/
│   │   ├── RemindersMCP/
│   │   ├── NotesMCP/
│   │   ├── MailMCP/
│   │   ├── FilesMCP/
│   │   └── AppIntentProxy/
│   │
│   ├── Agents.app/                      # NEW: macOS/iOS app
│   │   ├── App/
│   │   ├── Views/
│   │   │   ├── ChatView/
│   │   │   ├── WorkspaceBrowser/
│   │   │   ├── AgentManager/
│   │   │   ├── ApprovalQueue/
│   │   │   └── Settings/
│   │   └── ViewModels/
│   │
│   ├── AgentKitServer/              # Existing (may merge with Agents)
│   ├── AgentKitCLI/                 # Existing
│   └── AgentKitConsole/             # Existing → evolves into Agents.app
```

### Phase 3: Package.swift Evolution

```swift
// Package.swift
let package = Package(
    name: "AgentKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Core library - general purpose, no Apple dependencies
        .library(name: "AgentKit", targets: ["AgentKit"]),

        // Agents runtime - adds Apple-specific functionality
        .library(name: "Agents", targets: ["Agents"]),

        // MCP servers for Apple frameworks
        .library(name: "AgentsMCP", targets: ["AgentsMCP"]),

        // Full Agents app
        .executable(name: "Agents.app", targets: ["Agents.app"]),

        // Existing executables
        .executable(name: "AgentKitServer", targets: ["AgentKitServer"]),
        .executable(name: "AgentKitCLI", targets: ["AgentKitCLI"]),
    ],
    dependencies: [
        // Existing
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "2.29.0"),

        // New for Agents
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),  // SQLite for memory
    ],
    targets: [
        // Core AgentKit - no Apple framework dependencies
        .target(
            name: "AgentKit",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
            ]
        ),

        // Agents runtime - depends on AgentKit, adds Apple frameworks
        .target(
            name: "Agents",
            dependencies: [
                "AgentKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),

        // MCP servers - depends on Agents, uses EventKit, etc.
        .target(
            name: "AgentsMCP",
            dependencies: ["Agents"]
        ),

        // Agents.app - full application
        .executableTarget(
            name: "Agents.app",
            dependencies: ["Agents", "AgentsMCP"]
        ),

        // Existing targets...
    ]
)
```

---

## Detailed Component Design

### AgentKit Extensions

#### 1. Identity System (AgentKit/Identity/)

```swift
/// Agent identity - persists across sessions
public struct AgentIdentity: Codable, Sendable, Identifiable {
    public let id: AgentID
    public var name: String
    public var basePrompt: String
    public var capabilities: Set<Capability>
    public var createdAt: Date
    public var metadata: [String: AnyCodable]

    public init(name: String, basePrompt: String, capabilities: Set<Capability> = [])
}

/// What an agent can do
public struct Capability: Codable, Hashable, Sendable {
    public let domain: String      // "calendar", "files", "custom.myapp"
    public let action: String      // "read", "write", "execute"

    public static let calendarRead = Capability(domain: "calendar", action: "read")
    public static let calendarWrite = Capability(domain: "calendar", action: "write")
    // ... predefined capabilities
}

/// Storage for agent identities
public protocol IdentityStore: Actor {
    func save(_ identity: AgentIdentity) async throws
    func load(id: AgentID) async throws -> AgentIdentity?
    func delete(id: AgentID) async throws
    func list() async throws -> [AgentIdentity]
}

/// File-based implementation (can be extended for iCloud in Agents)
public actor FileIdentityStore: IdentityStore {
    private let directory: URL

    public init(directory: URL)
}
```

#### 2. Memory System (AgentKit/Memory/)

```swift
/// A single memory entry
public struct Memory: Codable, Identifiable, Sendable {
    public let id: MemoryID
    public let content: String
    public let type: MemoryType
    public let embedding: [Float]?  // For semantic search
    public let createdAt: Date
    public let metadata: [String: AnyCodable]
}

public enum MemoryType: String, Codable, Sendable {
    case interaction      // Past conversation
    case learning         // User correction
    case fact             // Stored fact
    case summary          // Compressed context
}

/// Memory storage and retrieval
public protocol MemoryStore: Actor {
    /// Store a new memory
    func store(_ memory: Memory) async throws

    /// Recall memories by semantic similarity
    func recall(query: String, limit: Int, types: Set<MemoryType>?) async throws -> [Memory]

    /// Get all memories of a type
    func list(type: MemoryType?, limit: Int) async throws -> [Memory]

    /// Delete old memories
    func prune(olderThan: Date) async throws -> Int
}

/// Embedding provider for semantic search
public protocol EmbeddingProvider: Actor {
    func embed(_ text: String) async throws -> [Float]
    func embed(_ texts: [String]) async throws -> [[Float]]
}

/// Local embedding using MLX
public actor MLXEmbeddingProvider: EmbeddingProvider {
    // Uses a small embedding model like all-MiniLM-L6-v2
}
```

#### 3. Trust System (AgentKit/Trust/)

```swift
/// Trust level for agent autonomy
public enum TrustLevel: Int, Codable, Comparable, Sendable {
    case observer = 0      // Read-only
    case assistant = 1     // Create with approval
    case contributor = 2   // Modify with staging
    case trusted = 3       // Direct write, HITL for high-risk
    case autonomous = 4    // Full autonomy

    public static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Trust metrics for an agent
public struct TrustMetrics: Codable, Sendable {
    public var level: TrustLevel
    public var totalInteractions: Int
    public var successfulInteractions: Int
    public var corrections: Int
    public var domainLevels: [String: TrustLevel]  // Per-domain trust
    public var lastUpdated: Date

    public var successRate: Double {
        guard totalInteractions > 0 else { return 0 }
        return Double(successfulInteractions) / Double(totalInteractions)
    }

    public var errorRate: Double {
        guard totalInteractions > 0 else { return 0 }
        return Double(corrections) / Double(totalInteractions)
    }
}

/// Manages trust levels and decisions
public actor TrustManager {
    private var metrics: [AgentID: TrustMetrics] = [:]

    /// Check if agent can perform action
    public func canPerform(
        _ capability: Capability,
        agent: AgentID,
        requiredLevel: TrustLevel
    ) -> Bool

    /// Record interaction outcome
    public func recordOutcome(
        _ outcome: InteractionOutcome,
        agent: AgentID
    )

    /// Get trust metrics
    public func metrics(for agent: AgentID) -> TrustMetrics?

    /// Manually adjust trust
    public func setLevel(
        _ level: TrustLevel,
        for agent: AgentID,
        domain: String?
    )
}

public enum InteractionOutcome: Sendable {
    case success
    case failure(reason: String)
    case correction(what: String)
}
```

#### 4. Context System (AgentKit/Context/)

```swift
/// Source of context for an agent
public protocol ContextSource: Sendable {
    var name: String { get }
    var priority: Int { get }  // Higher = more important

    func provide(for query: String) async throws -> ContextFragment
}

/// A piece of context
public struct ContextFragment: Sendable {
    public let source: String
    public let content: String
    public let tokenEstimate: Int
    public let metadata: [String: String]
}

/// Assembles context from multiple sources
public actor ContextAssembler {
    private var sources: [ContextSource] = []

    public func register(_ source: ContextSource)

    /// Assemble context for a query, respecting token budget
    public func assemble(
        for query: String,
        maxTokens: Int,
        requiredSources: [String]?
    ) async throws -> AssembledContext
}

public struct AssembledContext: Sendable {
    public let fragments: [ContextFragment]
    public let totalTokens: Int

    public var combined: String {
        fragments.map(\.content).joined(separator: "\n\n")
    }
}
```

### Agents-Specific Components

#### 1. Workspace System (Agents/Workspace/)

```swift
/// A workspace containing agent context and artifacts
public struct Workspace: Codable, Identifiable, Sendable {
    public let id: WorkspaceID
    public var name: String
    public var path: URL
    public var agents: [AgentID: WorkspacePermission]
    public var createdAt: Date
}

public struct WorkspacePermission: Codable, Sendable {
    public var canRead: Bool
    public var canCreate: Bool
    public var canModify: Bool
    public var canDelete: Bool
}

/// Manages workspaces
public actor WorkspaceManager {
    public func create(name: String) async throws -> Workspace
    public func list() async throws -> [Workspace]
    public func get(id: WorkspaceID) async throws -> Workspace?
    public func delete(id: WorkspaceID) async throws
    public func grant(_ permission: WorkspacePermission, to agent: AgentID, in workspace: WorkspaceID) async throws
}

/// Staging area for non-destructive writes
public actor StagingManager {
    public func stage(_ change: FileChange, agent: AgentID, workspace: WorkspaceID) async throws -> StagedChange
    public func pending(workspace: WorkspaceID) async -> [StagedChange]
    public func commit(_ changes: [StagedChangeID]) async throws
    public func discard(_ changes: [StagedChangeID]) async throws
}

/// Git-backed history for workspaces
public actor HistoryManager {
    public func record(_ change: CommittedChange, workspace: WorkspaceID) async throws -> CommitID
    public func history(for path: String, in workspace: WorkspaceID) async throws -> [Commit]
    public func restore(path: String, to commit: CommitID, in workspace: WorkspaceID) async throws
}
```

#### 2. MCP Servers (AgentsMCP/)

```swift
/// Base for Apple framework MCP servers
public protocol AppleMCPServer: MCPServer {
    var frameworkName: String { get }
    func checkAccess() async -> Bool
}

/// Calendar MCP
public actor CalendarMCPServer: AppleMCPServer {
    private let eventStore: EKEventStore

    @MCPTool("calendar.list_events")
    public func listEvents(from: Date, to: Date) async throws -> [CalendarEvent]

    @MCPTool("calendar.create_event")
    public func createEvent(_ event: NewEvent) async throws -> CalendarEvent

    // ... other tools
}

/// Reminders MCP
public actor RemindersMCPServer: AppleMCPServer {
    // Similar structure
}

/// AppIntent proxy - exposes any app's intents as MCP tools
public actor AppIntentMCPProxy: MCPServer {
    public func discover(bundleId: String) async throws -> [DiscoveredIntent]
    public func execute(_ intent: String, parameters: [String: Any]) async throws -> IntentResult
}
```

#### 3. Agents Runtime (Agents/Runtime/)

```swift
/// Main Agents runtime - orchestrates everything
public actor AgentsRuntime {
    private let agentKit: AgentLoop
    private let identityStore: IdentityStore
    private let memoryStores: [AgentID: MemoryStore]
    private let trustManager: TrustManager
    private let workspaceManager: WorkspaceManager
    private let contextAssembler: ContextAssembler
    private let mcpServers: [MCPServer]

    /// Start a session with an agent in a workspace
    public func startSession(
        agent: AgentID,
        workspace: WorkspaceID
    ) async throws -> AgentsSession

    /// Send a message to an active session
    public func send(
        _ message: String,
        to session: SessionID,
        attachments: [Attachment]?
    ) async throws -> AsyncThrowingStream<AgentsEvent, Error>

    /// End a session
    public func endSession(_ session: SessionID) async throws
}

/// Events from Agents runtime
public enum AgentsEvent: Sendable {
    case text(String)
    case artifact(Artifact)
    case toolUse(ToolUse)
    case approvalRequired(ApprovalRequest)
    case stagingChange(StagedChange)
    case error(AgentsError)
    case done
}

/// An artifact produced by an agent
public struct Artifact: Codable, Identifiable, Sendable {
    public let id: ArtifactID
    public let type: ArtifactType
    public let title: String
    public let content: String
    public let workspace: WorkspaceID
    public let createdAt: Date
}

public enum ArtifactType: String, Codable, Sendable {
    case document
    case code
    case calendarEvent
    case reminder
    case email
    case file
}
```

---

## Migration Path

### Step 1: Extend AgentKit (Non-Breaking)

Add Identity, Memory, Trust, Context modules to AgentKit. These are additive - existing code continues to work.

```swift
// Before: Using AgentKit directly
let agent = AgentLoop(provider: anthropic, tools: tools)
let response = try await agent.run(messages)

// After: Same API still works
let agent = AgentLoop(provider: anthropic, tools: tools)
let response = try await agent.run(messages)

// New: Can now add identity and memory
let identity = AgentIdentity(name: "Atlas", basePrompt: "You are a helpful assistant")
let memory = SQLiteMemoryStore(path: memoryPath)
let agent = AgentLoop(
    provider: anthropic,
    tools: tools,
    identity: identity,      // NEW
    memory: memory           // NEW
)
```

### Step 2: Create Agents Package

Add Agents, AgentsMCP, Agents.app targets. These are new - don't affect existing users.

### Step 3: Evolve Console to Agents.app

AgentKitConsole becomes Agents.app, adding workspace browser, chat UI, agent training.

---

## Open Design Questions

1. **Package split**: Should Agents be a separate repo, or stay in AgentKit monorepo?
   - Monorepo: Easier development, atomic changes
   - Separate: Clearer boundaries, independent versioning

2. **Memory backend**: SQLite (GRDB) vs custom vector store?
   - SQLite: Simple, works everywhere, JSON + FTS5
   - Vector: Better semantic search, more complex

3. **Embedding model**: Bundle embedding model or require external?
   - Bundle: Works offline, larger binary
   - External: Smaller, requires setup

4. **iCloud sync**: FileProvider vs manual sync?
   - FileProvider: Native integration, complex
   - Manual: Full control, more code

---

## Implementation Priority

### P0: Foundation (4 weeks)
- [ ] Identity module in AgentKit
- [ ] Memory module in AgentKit (SQLite-backed)
- [ ] Trust module in AgentKit
- [ ] Context assembler in AgentKit

### P1: Agents Core (4 weeks)
- [ ] Agents package structure
- [ ] Workspace manager
- [ ] Staging manager
- [ ] History manager (git-backed)

### P2: MCP Servers (4 weeks)
- [ ] Calendar MCP
- [ ] Reminders MCP
- [ ] Notes MCP
- [ ] Files MCP

### P3: Agents.app (6 weeks)
- [ ] Chat view with artifacts
- [ ] Workspace browser
- [ ] Agent manager
- [ ] Approval queue

### P4: Advanced (4 weeks)
- [ ] AppIntent proxy
- [ ] PCC integration
- [ ] iOS companion
- [ ] Agent Store infrastructure

---

*Document Version: 1.0*
*Last Updated: January 2025*
