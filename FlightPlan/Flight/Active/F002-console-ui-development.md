# F002: Console UI Development

**Status**: Active
**Priority**: P1
**Depends On**: F001-v1-local-runtime
**Started**: 2026-01-12

---

## Goal

Build the macOS management console (AgentKitConsole) with a Craft-like interface for interacting with agents. This is Phase 7 from F001, broken out for focused development.

---

## Current State

### Completed
- [x] Basic SwiftUI app structure
- [x] Main ContentView with sidebar navigation
- [x] AppState for shared state management
- [x] MenuBarView for menu bar extra
- [x] AgentPanelView - slide-out agent interaction panel
- [x] CommandPaletteView - Cmd+K quick actions with fuzzy search
- [x] AgentRecruitmentView - Browse and recruit from 18 agent templates
- [x] AgentBuilderView - Conversational agent creation wizard
- [x] AgentTemplates - 18 predefined agent types

### In Progress
- [ ] **Main window not appearing on launch** - SwiftUI + MenuBarExtra conflict
- [ ] Wire up all sheet presentations from AppState flags

### Blocked
- App runs, menu bar shows, but main window doesn't open
- Multiple approaches tried (see Technical Learnings below)

---

## Technical Learnings

### SwiftUI + MenuBarExtra Window Issue

**Problem**: When a SwiftUI app has both `WindowGroup` (or `Window`) and `MenuBarExtra`, macOS doesn't automatically create the main window on launch.

**Attempted Solutions**:

1. **WindowGroup with .defaultLaunchBehavior(.presented)** - Requires macOS 15+, still didn't work
2. **Window scene type** - Single window, still didn't auto-create
3. **@NSApplicationDelegateAdaptor with applicationDidFinishLaunching** - Delegate methods aren't called when using SwiftUI App lifecycle
4. **Manual NSWindow creation in AppDelegate** - Window created but still not showing

**Root Cause Theory**: SwiftUI's `MenuBarExtra` takes over the app lifecycle and prevents window creation. The `@NSApplicationDelegateAdaptor` callbacks may be skipped or deferred.

**Next Steps to Try**:
- Remove MenuBarExtra temporarily to confirm window works
- Pure AppKit approach with NSApplicationMain
- Different scene ordering (MenuBarExtra before Window)
- Custom window creation after a delay

### Platform Targeting

Updated to macOS 26 / iOS 26 with swift-tools-version: 6.2 to access latest APIs.

### MainActor Isolation

AppDelegate methods like `applicationDidFinishLaunching` need careful handling:
```swift
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // Main actor work here
        }
    }
}
```

---

## UI Components

### 1. Command Palette (CommandPaletteView.swift)
- Cmd+K to open
- Fuzzy search across actions
- Categories: Quick Actions, Navigation, Agents
- Keyboard navigation support

### 2. Agent Recruitment (AgentRecruitmentView.swift)
- Browse 18 agent templates by category
- Categories: Engineering, Research, Creative, Operations, Communication
- Preview agent capabilities before recruiting
- Customization options during recruitment

### 3. Agent Builder (AgentBuilderView.swift)
- Conversational wizard for custom agents
- 4-step flow: Purpose → Capabilities → Boundaries → Name/Confirm
- AI-suggested names based on purpose
- Progressive disclosure of complexity

### 4. Agent Panel (AgentPanelView.swift)
- Slide-out panel for agent interaction
- Task delegation interface
- Status monitoring
- Quick actions

### 5. Menu Bar (MenuBarView.swift)
- Status indicator
- Quick actions dropdown
- Agent status summary
- Window management

---

## Agent Templates (18 total)

| Category | Agents |
|----------|--------|
| Engineering | implementer, reviewer, debugger, architect |
| Research | researcher, analyst, librarian |
| Creative | writer, designer, narrator |
| Operations | orchestrator, deployer, monitor |
| Communication | messenger, translator, summarizer, documenter, presenter |

---

## Package Structure

```
AgentKitConsole/
├── AgentKitConsoleApp.swift    # App entry point
├── Models/
│   ├── AppState.swift          # Global state
│   └── AgentTemplates.swift    # Agent template definitions
└── Views/
    ├── ContentView.swift       # Main layout
    ├── MenuBarView.swift       # Menu bar extra
    ├── AgentPanelView.swift    # Agent interaction
    ├── CommandPaletteView.swift # Cmd+K palette
    ├── AgentRecruitmentView.swift
    ├── AgentBuilderView.swift
    └── ... (other views)
```

---

## Next Steps

1. **Resolve window launch issue** - Critical blocker
2. Wire up sheet presentations to AppState
3. Implement agent delegation flow
4. Connect to AgentKit server via A2A
5. Real-time status updates

---

## Related Documents

- [F001: V1 Local Runtime](./F001-v1-local-runtime.md)
- [UI Design Spec](../../design/UI_DESIGN_SPEC.md)
- [CLI Runner Agent](../../design/cli-runner-agent.md)
