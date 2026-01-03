# Project Goldeneye - Technical Requirements
## Engineering Handoff Document

> This document specifies the technical requirements for building **Agents** (codename: Goldeneye). It is intended for handoff to a development team.

---

## System Overview

Goldeneye is a platform for persistent, trustworthy AI agents that integrate with Apple's ecosystem. The system consists of:

1. **AgentKit** - Core Swift library for agent infrastructure (general-purpose)
2. **Agents Runtime** - Agent execution environment with context management
3. **Agents.app** - macOS/iOS app for user interaction
4. **AgentsMCP** - Native Apple framework integrations
5. **Agent Store** - Distribution platform for agents

---

## 1. AgentKit Core Library

### 1.1 Current State (Built)

The following components are implemented:

| Component | Status | Location |
|-----------|--------|----------|
| LLM Provider Protocol | ✅ Complete | `Sources/AgentKit/LLM/` |
| Provider Implementations | ✅ Complete | Anthropic, OpenAI-compat, Ollama, LM Studio, MLX |
| CLI Agent Providers | ✅ Complete | Claude Code, Codex, Gemini wrappers |
| Tool System | ✅ Complete | `Sources/AgentKit/Tools/` |
| A2A Protocol | ✅ Complete | `Sources/AgentKit/A2A/` |
| HITL Approval System | ✅ Complete | `Sources/AgentKit/Approval/` |
| Agent Loop | ✅ Complete | `Sources/AgentKit/Agent/` |

### 1.2 Required Extensions

#### 1.2.1 Agent Identity System

```swift
/// Persistent agent identity
public struct AgentIdentity: Codable, Sendable {
    let id: AgentID
    let name: String
    let createdAt: Date
    let basePrompt: String
    let capabilities: Set<Capability>
    let trustLevel: TrustLevel
    let metadata: AgentMetadata
}

/// Trust level earned through interaction
public enum TrustLevel: Int, Codable, Comparable {
    case observer = 0      // Read-only
    case assistant = 1     // Create artifacts, drafts need approval
    case contributor = 2   // Modify within workspace (staged)
    case trusted = 3       // Direct write, HITL for high-risk
    case autonomous = 4    // Full autonomy within boundaries
}

/// Capability with associated trust requirement
public struct Capability: Codable, Hashable {
    let domain: CapabilityDomain  // calendar, mail, files, etc.
    let action: CapabilityAction  // read, create, modify, delete, send
    let requiredTrust: TrustLevel
}
```

**Implementation Requirements**:
- Store in `~/iCloud/.agents/{agent-id}/identity.json`
- Sync across devices via iCloud
- Version history for rollback

#### 1.2.2 Agent Memory System

```swift
/// Long-term memory for agents
public actor AgentMemory {
    /// Store a memory with semantic embedding
    func store(_ content: String, type: MemoryType, metadata: [String: Any]) async throws

    /// Retrieve relevant memories for context
    func recall(query: String, limit: Int, types: Set<MemoryType>?) async throws -> [Memory]

    /// User corrections that modify agent behavior
    func recordLearning(_ correction: UserCorrection) async throws

    /// Compact memories to manage storage
    func compact(olderThan: Date) async throws
}

public enum MemoryType: String, Codable {
    case interaction    // Past conversations
    case learning       // User corrections
    case preference     // Inferred preferences
    case fact           // Stored facts about user/workspace
}
```

**Implementation Requirements**:
- Vector store for semantic search (SQLite + custom embeddings, or dedicated vector DB)
- Separate memory per agent: `~/iCloud/.agents/{agent-id}/memory/`
- Incremental sync (don't re-upload entire memory on each change)
- Memory size limits with automatic compaction

#### 1.2.3 Trust Management System

```swift
/// Manages trust levels and capability grants
public actor TrustManager {
    /// Check if agent can perform action
    func canPerform(_ action: CapabilityAction, in domain: CapabilityDomain, agent: AgentID) -> Bool

    /// Record interaction outcome for trust building
    func recordOutcome(_ outcome: InteractionOutcome, agent: AgentID) async

    /// Get current trust metrics for agent
    func trustMetrics(for agent: AgentID) async -> TrustMetrics

    /// Manually adjust trust (user override)
    func setTrustLevel(_ level: TrustLevel, for agent: AgentID, in domain: CapabilityDomain?) async
}

public struct TrustMetrics: Codable {
    let overallLevel: TrustLevel
    let totalInteractions: Int
    let successfulInteractions: Int
    let corrections: Int
    let errorRate: Double
    let domainTrust: [CapabilityDomain: TrustLevel]
    let lastUpdated: Date
}
```

**Trust Building Algorithm**:
```
new_trust = current_trust + (success_rate * interaction_weight) - (error_rate * penalty)

Where:
- success_rate = successful_interactions / total_interactions
- interaction_weight = log(total_interactions + 1) / 10  // More interactions = more confidence
- error_rate = corrections / total_interactions
- penalty = 2.0  // Errors weight more than successes
```

---

## 2. Context & Workspace System

### 2.1 Directory Structure

```
~/Library/Mobile Documents/com~apple~CloudDocs/
├── .agents/                          # Agent home directories
│   ├── {agent-uuid}/
│   │   ├── identity.json             # Agent configuration
│   │   ├── memory/
│   │   │   ├── vectors.sqlite        # Semantic memory store
│   │   │   ├── learnings.json        # User corrections
│   │   │   └── summaries/            # Compressed conversation history
│   │   ├── context/                  # Active working context
│   │   └── trust.json                # Trust metrics and history
│   │
│   └── shared/
│       ├── user-profile.json         # Cross-agent user preferences
│       └── global-learnings.json     # Learnings that apply to all agents
│
└── Spaces/                           # Workspaces
    ├── {workspace-name}/
    │   ├── .space/
    │   │   ├── config.json           # Workspace configuration
    │   │   ├── agents.json           # Agent permissions for this space
    │   │   └── history/              # Git-like change history
    │   │       ├── objects/
    │   │       ├── refs/
    │   │       └── HEAD
    │   │
    │   ├── artifacts/                # Agent-generated content
    │   ├── documents/                # User documents (agent can access)
    │   └── context/                  # Workspace-specific context files
    │
    └── .staging/                     # Agent writes land here first
        └── {agent-id}/
            └── {workspace-name}/
                └── ... (mirror of workspace structure)
```

### 2.2 Workspace Configuration

```swift
public struct WorkspaceConfig: Codable {
    let id: WorkspaceID
    let name: String
    let createdAt: Date

    /// Agent permissions for this workspace
    var agentPermissions: [AgentID: WorkspacePermission]

    /// Folders agents can access (relative paths)
    var accessiblePaths: [AccessPath]

    /// Whether workspace syncs to iCloud
    var syncEnabled: Bool

    /// Custom context files for this workspace
    var contextFiles: [String]
}

public struct WorkspacePermission: Codable {
    let canRead: Bool
    let canCreate: Bool
    let canModify: Bool
    let canDelete: Bool
    let requiresApproval: Set<OperationType>
}

public struct AccessPath: Codable {
    let path: String
    let permission: PathPermission  // read, readWrite
    let includeSubdirectories: Bool
}
```

### 2.3 Staging System (Non-Destructive Writes)

All agent modifications go through staging:

```swift
public actor StagingManager {
    /// Stage a change (doesn't affect user's live files)
    func stage(
        _ change: FileChange,
        agent: AgentID,
        workspace: WorkspaceID
    ) async throws -> StagedChange

    /// Get all pending changes for review
    func pendingChanges(
        workspace: WorkspaceID,
        agent: AgentID?
    ) async -> [StagedChange]

    /// Commit staged changes to live workspace
    func commit(
        _ changes: [StagedChangeID],
        message: String
    ) async throws

    /// Discard staged changes
    func discard(_ changes: [StagedChangeID]) async throws

    /// View diff between staged and live
    func diff(_ change: StagedChangeID) async -> FileDiff
}

public struct StagedChange: Codable, Identifiable {
    let id: StagedChangeID
    let agent: AgentID
    let workspace: WorkspaceID
    let path: String
    let changeType: ChangeType  // create, modify, delete
    let stagedAt: Date
    let preview: String?  // First N characters for UI preview
}
```

### 2.4 History System (Git-backed)

Every workspace maintains full history:

```swift
public actor WorkspaceHistory {
    /// Record a change
    func record(
        _ change: CommittedChange,
        message: String,
        author: AgentID
    ) async throws -> CommitID

    /// Get history for a file
    func history(for path: String, limit: Int) async -> [Commit]

    /// Restore file to previous version
    func restore(path: String, to commit: CommitID) async throws

    /// Get diff between commits
    func diff(from: CommitID, to: CommitID) async -> [FileDiff]
}
```

**Implementation Note**: Use libgit2 or shell out to git. The history format should be compatible with standard git tools for debugging.

---

## 3. MCP Server Implementations

### 3.1 Architecture

Each Apple framework gets an MCP server:

```swift
/// Base protocol for Apple framework MCP servers
public protocol AppleFrameworkMCPServer: MCPServer {
    /// Framework being exposed
    var framework: AppleFramework { get }

    /// Required entitlements/permissions
    var requiredEntitlements: [String] { get }

    /// Check if framework is accessible
    func checkAccess() async -> AccessStatus
}
```

### 3.2 Calendar MCP Server

```swift
public actor CalendarMCPServer: AppleFrameworkMCPServer {
    // Tools exposed
    @MCPTool("calendar.list_events")
    func listEvents(from: Date, to: Date, calendars: [String]?) async throws -> [CalendarEvent]

    @MCPTool("calendar.get_event")
    func getEvent(id: String) async throws -> CalendarEvent

    @MCPTool("calendar.create_event")
    func createEvent(_ event: NewCalendarEvent) async throws -> CalendarEvent

    @MCPTool("calendar.update_event")
    func updateEvent(id: String, updates: EventUpdates) async throws -> CalendarEvent

    @MCPTool("calendar.delete_event")
    func deleteEvent(id: String) async throws

    @MCPTool("calendar.check_availability")
    func checkAvailability(from: Date, to: Date, duration: TimeInterval) async throws -> [TimeSlot]

    @MCPTool("calendar.list_calendars")
    func listCalendars() async throws -> [Calendar]
}
```

### 3.3 Reminders MCP Server

```swift
public actor RemindersMCPServer: AppleFrameworkMCPServer {
    @MCPTool("reminders.list_lists")
    func listLists() async throws -> [ReminderList]

    @MCPTool("reminders.list_reminders")
    func listReminders(list: String?, completed: Bool?) async throws -> [Reminder]

    @MCPTool("reminders.create_reminder")
    func createReminder(_ reminder: NewReminder) async throws -> Reminder

    @MCPTool("reminders.complete_reminder")
    func completeReminder(id: String) async throws

    @MCPTool("reminders.update_reminder")
    func updateReminder(id: String, updates: ReminderUpdates) async throws -> Reminder
}
```

### 3.4 Notes MCP Server

```swift
public actor NotesMCPServer: AppleFrameworkMCPServer {
    @MCPTool("notes.list_folders")
    func listFolders() async throws -> [NotesFolder]

    @MCPTool("notes.list_notes")
    func listNotes(folder: String?, limit: Int?) async throws -> [NoteSummary]

    @MCPTool("notes.get_note")
    func getNote(id: String) async throws -> Note

    @MCPTool("notes.create_note")
    func createNote(title: String, body: String, folder: String?) async throws -> Note

    @MCPTool("notes.update_note")
    func updateNote(id: String, title: String?, body: String?) async throws -> Note

    @MCPTool("notes.search_notes")
    func searchNotes(query: String, limit: Int?) async throws -> [NoteSummary]
}
```

### 3.5 Mail MCP Server

```swift
public actor MailMCPServer: AppleFrameworkMCPServer {
    @MCPTool("mail.list_mailboxes")
    func listMailboxes() async throws -> [Mailbox]

    @MCPTool("mail.list_messages")
    func listMessages(mailbox: String, limit: Int?, unreadOnly: Bool?) async throws -> [MessageSummary]

    @MCPTool("mail.get_message")
    func getMessage(id: String) async throws -> Message

    @MCPTool("mail.search_messages")
    func searchMessages(query: String, mailbox: String?, limit: Int?) async throws -> [MessageSummary]

    @MCPTool("mail.draft_message")  // Creates draft, doesn't send
    func draftMessage(_ draft: NewMessage) async throws -> DraftMessage

    @MCPTool("mail.send_message")  // Requires high trust + approval
    func sendMessage(draftId: String) async throws

    @MCPTool("mail.move_message")
    func moveMessage(id: String, to mailbox: String) async throws
}
```

### 3.6 Files MCP Server (iCloud Drive)

```swift
public actor FilesMCPServer: AppleFrameworkMCPServer {
    @MCPTool("files.list")
    func listFiles(path: String, recursive: Bool?) async throws -> [FileInfo]

    @MCPTool("files.read")
    func readFile(path: String) async throws -> FileContent

    @MCPTool("files.write")  // Goes through staging
    func writeFile(path: String, content: String) async throws -> StagedChange

    @MCPTool("files.search")
    func searchFiles(query: String, path: String?, types: [String]?) async throws -> [FileInfo]

    @MCPTool("files.metadata")
    func getMetadata(path: String) async throws -> FileMetadata
}
```

### 3.7 AppIntent MCP Proxy

Dynamically expose any app's AppIntents as MCP tools:

```swift
public actor AppIntentMCPProxy {
    /// Discover intents from an app
    func discoverIntents(bundleId: String) async throws -> [DiscoveredIntent]

    /// Register app's intents as MCP tools
    func registerApp(_ bundleId: String) async throws

    /// Execute an intent
    func executeIntent(
        bundleId: String,
        intentId: String,
        parameters: [String: Any]
    ) async throws -> IntentResult
}

public struct DiscoveredIntent: Codable {
    let id: String
    let title: String
    let description: String?
    let parameters: [IntentParameter]
    let returnType: String?
}
```

**Implementation Notes**:
- Use `INIntentLibrary` to discover available intents
- Map intent parameters to MCP tool input schema
- All intent executions require approval based on trust level
- Cache intent discovery (apps don't change frequently)

---

## 4. Agents Runtime

### 4.1 Agent Execution Environment

```swift
public actor AgentsRuntime {
    /// Start an agent session
    func startSession(
        agent: AgentID,
        workspace: WorkspaceID,
        context: SessionContext
    ) async throws -> SessionID

    /// Send message to active session
    func sendMessage(
        _ message: String,
        session: SessionID,
        attachments: [Attachment]?
    ) async throws -> AsyncThrowingStream<AgentResponse, Error>

    /// End session (persists memory, context)
    func endSession(_ session: SessionID) async throws

    /// Get session state
    func sessionState(_ session: SessionID) async -> SessionState?
}
```

### 4.2 Context Assembly

```swift
public struct ContextAssembler {
    /// Assemble full context for agent execution
    func assemble(
        agent: AgentIdentity,
        workspace: WorkspaceConfig,
        query: String,
        conversationHistory: [Message]
    ) async throws -> AssembledContext

    struct AssembledContext {
        let systemPrompt: String        // Agent identity + instructions
        let userContext: String         // User preferences, profile
        let workspaceContext: String    // Workspace-specific files
        let relevantMemories: [Memory]  // Semantic search results
        let availableTools: [Tool]      // Based on trust level
        let conversationHistory: [Message]
    }
}
```

### 4.3 Compute Location Selection

```swift
public enum ComputeLocation {
    case local(MLXProvider)           // On-device MLX
    case pcc(PCCProvider)             // Apple Private Cloud Compute
    case cloud(CloudProvider)         // API-based (Anthropic, OpenAI)
}

public actor ComputeRouter {
    /// Select best compute location for task
    func selectCompute(
        task: TaskRequirements,
        preferences: UserPreferences,
        contextSensitivity: ContextSensitivity
    ) async -> ComputeLocation

    struct TaskRequirements {
        let estimatedTokens: Int
        let requiresToolUse: Bool
        let latencyRequirement: LatencyClass
        let capabilityRequirement: CapabilityClass
    }
}
```

**Routing Logic**:
1. If `contextSensitivity == .maximum` → local only
2. If `contextSensitivity == .high` → local or PCC
3. If task requires high capability (complex reasoning) → prefer cloud
4. If low latency required → prefer local
5. User preference overrides

---

## 5. Agents.app Requirements

### 5.1 Core Views

| View | Purpose | Priority |
|------|---------|----------|
| Chat View | Primary interaction, artifact display | P0 |
| Workspace Browser | Navigate spaces, files, artifacts | P0 |
| Agent Manager | View/configure agents, trust levels | P0 |
| Approval Queue | Review pending agent actions | P0 |
| Agent Training | View learnings, adjust trust | P1 |
| Settings | Compute preferences, privacy | P1 |

### 5.2 Chat View Specifications

**Message Types**:
- User message (text, attachments)
- Agent message (text, artifacts, tool calls)
- System message (workspace changes, approvals)

**Artifact Types**:
- Document (markdown, text)
- Code (syntax highlighted)
- Calendar event (visual card)
- Reminder (checklist item)
- File reference (link to workspace file)
- Approval request (action card)

**Artifact Interactions**:
- Inline preview (first N lines)
- Expand to full view
- Edit inline
- Open in app (Calendar, Notes, etc.)
- Save to workspace
- Approve/reject (for pending actions)

### 5.3 Approval Flow UI

```
┌─────────────────────────────────────────────────────────────────┐
│  🔔 Action Requires Approval                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Atlas wants to:                                                 │
│  📅 Create calendar event "Q2 Planning Meeting"                  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Title: Q2 Planning Meeting                                 │  │
│  │ Date: Monday, Jan 6, 2025                                  │  │
│  │ Time: 10:00 AM - 11:00 AM                                  │  │
│  │ Calendar: Work                                             │  │
│  │ Invitees: team@company.com                                 │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ○ Always allow Atlas to create calendar events                 │
│                                                                  │
│           [Deny]                    [Approve]                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5.4 Platform Support

| Platform | Priority | Notes |
|----------|----------|-------|
| macOS | P0 | Primary development platform |
| iOS | P1 | Mobile companion |
| iPadOS | P2 | Extended mobile |
| visionOS | P3 | Future consideration |

---

## 6. Security Requirements

### 6.1 Data Protection

| Data Type | Protection | Notes |
|-----------|------------|-------|
| Agent identity | iCloud encryption | Synced across devices |
| Agent memory | Local encryption + iCloud | Sensitive user data |
| Workspace files | iCloud Drive | Standard iCloud protection |
| Trust metrics | Local + iCloud | Tampering would be problematic |
| Staged changes | Local only | Cleared on commit/discard |

### 6.2 Context Encryption for Remote Compute

When sending context to cloud providers:

```swift
public struct ContextEncryption {
    /// Encrypt context for transmission
    func encrypt(
        _ context: AssembledContext,
        for destination: ComputeLocation
    ) async throws -> EncryptedContext

    /// Validate response hasn't been tampered
    func validateResponse(
        _ response: EncryptedResponse,
        context: EncryptedContext
    ) async throws -> ValidatedResponse
}
```

### 6.3 Entitlements Required

```xml
<!-- Info.plist entitlements -->
<key>com.apple.security.app-sandbox</key>
<true/>

<key>com.apple.security.files.user-selected.read-write</key>
<true/>

<key>com.apple.security.personal-information.calendars</key>
<true/>

<key>com.apple.security.personal-information.reminders</key>
<true/>

<key>com.apple.security.personal-information.addressbook</key>
<true/>

<!-- For Mail access -->
<key>com.apple.security.scripting-targets</key>
<dict>
    <key>com.apple.mail</key>
    <array>
        <string>com.apple.mail.compose</string>
        <string>com.apple.mail.read</string>
    </array>
</dict>
```

---

## 7. Testing Requirements

### 7.1 Unit Tests

- [ ] Agent identity persistence
- [ ] Trust level calculations
- [ ] Memory storage and retrieval
- [ ] Staging system operations
- [ ] History recording and rollback
- [ ] Context assembly
- [ ] Each MCP server tool

### 7.2 Integration Tests

- [ ] Full agent conversation flow
- [ ] Cross-agent communication (A2A)
- [ ] iCloud sync behavior
- [ ] Approval flow end-to-end
- [ ] Compute location handoff

### 7.3 Security Tests

- [ ] Trust level enforcement
- [ ] Staging isolation (agents can't access live files directly)
- [ ] Context encryption
- [ ] Entitlement enforcement

---

## 8. Implementation Phases

### Phase 1: Foundation (4-6 weeks)

- [ ] Agent identity system
- [ ] Agent memory (basic, local only)
- [ ] Trust management
- [ ] Workspace structure
- [ ] Staging system
- [ ] History system (git-backed)

### Phase 2: Native Integration (4-6 weeks)

- [ ] Calendar MCP server
- [ ] Reminders MCP server
- [ ] Notes MCP server
- [ ] Files MCP server (iCloud Drive)
- [ ] AppIntent proxy (basic)

### Phase 3: User Experience (6-8 weeks)

- [ ] Agents macOS app
- [ ] Chat view with artifacts
- [ ] Workspace browser
- [ ] Agent manager
- [ ] Approval flow

### Phase 4: Advanced (4-6 weeks)

- [ ] Mail MCP server
- [ ] Messages MCP server (read-only)
- [ ] Compute routing (local/PCC/cloud)
- [ ] Context encryption
- [ ] iOS companion app

### Phase 5: Polish & Distribution (4+ weeks)

- [ ] Agent packaging format
- [ ] Agent Store infrastructure
- [ ] Review process
- [ ] Public launch

---

## Appendix A: API Reference Stubs

See separate API documentation for detailed type definitions.

## Appendix B: Error Codes

| Code | Domain | Description |
|------|--------|-------------|
| ACE001 | Trust | Insufficient trust level for operation |
| ACE002 | Trust | Trust level downgraded due to errors |
| ACE003 | Context | Workspace not found |
| ACE004 | Context | Agent not permitted in workspace |
| ACE005 | Staging | Conflict with existing staged change |
| ACE006 | Memory | Memory storage full |
| ACE007 | MCP | Framework access denied |
| ACE008 | Compute | No available compute location |

---

*Document Version: 1.0*
*Last Updated: January 2025*
*Status: Ready for Engineering Review*
