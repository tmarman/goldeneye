# F007: Native Integrations Enhancement

**Status**: Backlog
**Priority**: P1 - High Impact
**Depends On**: F001 Local Runtime
**Related**: M002 Apple Integration

## Summary

Enhance AgentKit's native integration layer to provide first-class Apple ecosystem and third-party service connectivity without external MCP server dependencies.

## Current State

### What We Have

| Integration | Status | Location |
|-------------|--------|----------|
| **Slack** | Partial - Bot tokens only | `MCP/Integrations/SlackIntegration.swift` |
| **Quip** | Implemented | `MCP/Integrations/QuipIntegration.swift` |
| **Calendar** | Implemented via EventKit | `Events/EventKitSource.swift` |
| **Safari** | Implemented | `Memory/SafariIntegration.swift` |
| **AppIntents** | Scaffold only | `Extensions/AppIntentsTool.swift` |
| **Notes** | Not implemented | - |
| **Messages** | Not implemented | - |
| **Mail** | Not implemented | - |
| **Reminders** | Not implemented | - |

### Architecture

```
NativeIntegrationManager (actor)
├── SlackIntegration
├── QuipIntegration
└── [Future integrations]

ToolRegistry
└── addNativeIntegrations(from: manager)
```

## Proposed Enhancements

### 1. Slack User Tokens (xoxp-)

**Problem**: Current implementation only supports bot tokens (xoxb-), limiting access to:
- User's private DMs
- Channels the bot isn't invited to
- Actions that need to appear "from" the user

**Solution**: Support both token types in parallel with automatic routing:

```swift
public actor SlackIntegration {
    private let botToken: String?      // xoxb-... for bot operations
    private let userToken: String?     // xoxp-... for user-scoped operations

    // Route based on operation type
    func apiCall(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        let token = selectToken(for: method)
        // ...
    }

    private func selectToken(for method: String) -> String {
        // User token for: search.messages, conversations.history (DMs), users.profile.set
        // Bot token for: chat.postMessage (as bot), reactions.add
    }
}
```

**UI Changes** in SettingsView:
- Add second secure field for user token
- Link to Slack OAuth flow for user token generation
- Display which token is being used for operations

### 2. Calendar/EventKit Health Issues

**Problems Identified**:
1. Health check returns `{"status": "ok"}` without verifying EventKit access
2. Permission dialog may not trigger on first run
3. macOS 14+ requires `requestFullAccessToEvents()` which needs explicit entitlement

**Solution**:

```swift
// Enhanced health check
public func checkEventKitHealth() async -> HealthStatus {
    let authStatus = EKEventStore.authorizationStatus(for: .event)

    switch authStatus {
    case .authorized, .fullAccess:
        // Actually try to fetch events
        let store = EKEventStore()
        let calendars = store.calendars(for: .event)
        return calendars.isEmpty
            ? .warning("No calendars found")
            : .healthy("\(calendars.count) calendars accessible")
    case .notDetermined:
        return .warning("Calendar access not requested")
    case .restricted, .denied:
        return .error("Calendar access denied - enable in System Settings > Privacy")
    @unknown default:
        return .unknown
    }
}
```

### 3. Apple Notes Integration

**Approach**: Use AppleScript bridge (same as apple-mcp npm package)

```swift
public actor AppleNotesIntegration {
    public var tools: [MCPTool] {
        [
            MCPTool(name: "notes_create", description: "Create a new Apple Note"),
            MCPTool(name: "notes_search", description: "Search notes by title/content"),
            MCPTool(name: "notes_get", description: "Get note content by title"),
            MCPTool(name: "notes_list_folders", description: "List note folders"),
            MCPTool(name: "notes_append", description: "Append content to existing note")
        ]
    }

    private func runAppleScript(_ script: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        // ...
    }

    func createNote(title: String, body: String, folder: String?) async throws -> String {
        let folderClause = folder.map { "in folder \"\($0)\"" } ?? ""
        let script = """
        tell application "Notes"
            make new note at folder "Notes" \(folderClause) with properties {name:"\(title)", body:"\(body)"}
        end tell
        """
        return try await runAppleScript(script)
    }
}
```

### 4. Messages Integration

**Note**: Sending iMessages programmatically requires user interaction (security restriction)

```swift
public actor AppleMessagesIntegration {
    public var tools: [MCPTool] {
        [
            MCPTool(name: "messages_compose", description: "Open compose window with pre-filled message"),
            MCPTool(name: "messages_read_recent", description: "Read recent messages (requires Full Disk Access)")
        ]
    }

    func composeMessage(to: String, body: String) async throws {
        // Uses imessage:// URL scheme - opens Messages app
        let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "imessage://\(to)?body=\(encoded)") {
            await NSWorkspace.shared.open(url)
        }
    }
}
```

### 5. Mail Integration

```swift
public actor AppleMailIntegration {
    public var tools: [MCPTool] {
        [
            MCPTool(name: "mail_compose", description: "Compose new email"),
            MCPTool(name: "mail_search", description: "Search emails (AppleScript)"),
            MCPTool(name: "mail_get_unread_count", description: "Get unread email count")
        ]
    }
}
```

### 6. Reminders Integration

Use EventKit's `EKReminder` (already have entitlement):

```swift
public actor RemindersIntegration {
    private let eventStore = EKEventStore()

    public var tools: [MCPTool] {
        [
            MCPTool(name: "reminders_create", description: "Create a reminder"),
            MCPTool(name: "reminders_list", description: "List reminders from a list"),
            MCPTool(name: "reminders_complete", description: "Mark reminder complete"),
            MCPTool(name: "reminders_search", description: "Search reminders")
        ]
    }
}
```

## Implementation Plan

### Phase 1: Quick Wins
1. [ ] Add Slack user token support to `SlackIntegration.swift`
2. [ ] Update `SettingsView.swift` with dual token UI
3. [ ] Fix EventKit health check to actually verify access
4. [ ] Add Reminders via EventKit (already entitled)

### Phase 2: AppleScript Integrations
5. [ ] Create `AppleScriptBridge.swift` utility
6. [ ] Implement `AppleNotesIntegration.swift`
7. [ ] Implement `AppleMailIntegration.swift`
8. [ ] Add Messages compose (URL scheme)

### Phase 3: Enhanced NativeIntegrationManager
9. [ ] Update manager to support all new integrations
10. [ ] Add comprehensive health checks for each
11. [ ] Create unified settings UI section

## Files to Create/Modify

| Action | File |
|--------|------|
| Modify | `AgentKit/Sources/AgentKit/MCP/Integrations/SlackIntegration.swift` |
| Modify | `AgentKit/Sources/Envoy/Views/SettingsView.swift` |
| Create | `AgentKit/Sources/AgentKit/MCP/Integrations/AppleScriptBridge.swift` |
| Create | `AgentKit/Sources/AgentKit/MCP/Integrations/AppleNotesIntegration.swift` |
| Create | `AgentKit/Sources/AgentKit/MCP/Integrations/AppleMailIntegration.swift` |
| Create | `AgentKit/Sources/AgentKit/MCP/Integrations/RemindersIntegration.swift` |
| Modify | `AgentKit/Sources/AgentKit/MCP/Integrations/NativeIntegrationManager.swift` |
| Modify | `AgentKit/Sources/AgentKitServer/main.swift` (health endpoint) |

## Comparison: Native Swift vs apple-mcp NPM

| Aspect | apple-mcp (Node.js) | Native Swift |
|--------|---------------------|--------------|
| **Dependency** | Requires Node/Bun | None |
| **Performance** | Process spawn overhead | Direct API calls |
| **Calendar** | AppleScript | EventKit (native) |
| **Reminders** | AppleScript | EventKit (native) |
| **Notes** | AppleScript | AppleScript (same) |
| **Messages** | AppleScript/URL | URL scheme (same) |
| **Mail** | AppleScript | AppleScript (same) |
| **Maps** | AppleScript | MapKit potential |
| **Integration** | Stdio MCP protocol | Direct tool calls |

**Verdict**: Native Swift is superior for Calendar/Reminders (EventKit), equivalent for Notes/Mail/Messages (both use AppleScript), and eliminates Node.js dependency.

## Open Questions

1. Should we support Contacts via the Contacts framework?
2. MapKit integration for location-based agent tasks?
3. Do we need the apple-mcp in Jasper at all, or deprecate in favor of native?

## Success Criteria

- [ ] Slack user token operations work (search DMs, post as user)
- [ ] EventKit health check accurately reports access status
- [ ] Notes can be created/searched via agent tools
- [ ] All integrations visible in Health Check UI
- [ ] No Node.js/Bun dependency for Apple integrations
