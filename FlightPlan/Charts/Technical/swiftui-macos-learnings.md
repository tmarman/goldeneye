# SwiftUI macOS Development Learnings

**Last Updated**: 2026-01-13
**Related**: F002-console-ui-development

---

## Critical Issue: MenuBarExtra + Window Conflict

### The Problem

When a SwiftUI app contains both a `WindowGroup` (or `Window`) and a `MenuBarExtra`, macOS does **not** automatically create the main window on launch. The menu bar icon appears, but no window opens.

### What We Tried (All Failed)

| Approach | Code | Result |
|----------|------|--------|
| WindowGroup basic | `WindowGroup { ContentView() }` | No window |
| Window scene | `Window("Title", id: "main") { ... }` | No window |
| .defaultLaunchBehavior | `.defaultLaunchBehavior(.presented)` | No window (macOS 15+) |
| NSApplicationDelegateAdaptor | `@NSApplicationDelegateAdaptor(AppDelegate.self)` | Delegate not called |
| Manual NSWindow | Create NSWindow in AppDelegate | Window created but not shown |

### Root Cause Analysis

SwiftUI's scene lifecycle with `MenuBarExtra` appears to:
1. Skip or defer `applicationDidFinishLaunching` callbacks
2. Treat `MenuBarExtra` as the primary scene
3. Not instantiate other scene types automatically

### Potential Solutions (To Test)

1. **Remove MenuBarExtra temporarily** - Confirm WindowGroup works in isolation
2. **Pure AppKit entry** - Use `@main` with `NSApplicationMain` instead of SwiftUI App
3. **Delayed window creation** - Use `DispatchQueue.main.asyncAfter` in app init
4. **Scene ordering** - Place MenuBarExtra after WindowGroup
5. **Hybrid approach** - AppKit app with SwiftUI views via NSHostingController

---

## MainActor and AppDelegate

### The Challenge

`NSApplicationDelegate` methods like `applicationDidFinishLaunching` are called from AppKit's run loop, which doesn't guarantee MainActor isolation. But UI work requires MainActor.

### Solution Pattern

```swift
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    // Mark as nonisolated since AppKit calls this
    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        // Hop to MainActor for UI work
        Task { @MainActor in
            createAndShowWindow()
        }
    }

    // This runs on MainActor
    func createAndShowWindow() {
        // Safe to create NSWindow, NSHostingView, etc.
    }
}
```

### Warning
The `Task { @MainActor in }` pattern means work is async. If you need synchronous execution, consider `MainActor.assumeIsolated` (with caution).

---

## Platform Targeting

### macOS 26 / iOS 26 Requirements

To use the latest APIs (like `.defaultLaunchBehavior`), update `Package.swift`:

```swift
// swift-tools-version: 6.2  // Required for v26 platforms

let package = Package(
    name: "AgentKit",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    // ...
)
```

### API Availability Notes

| API | Minimum Version |
|-----|-----------------|
| `.defaultLaunchBehavior(.presented)` | macOS 15 |
| `MenuBarExtra` | macOS 13 |
| `Window` scene | macOS 13 |
| `@Observable` | macOS 14 |

---

## SwiftUI State Management Patterns

### Shared Singleton for AppKit Bridge

When bridging SwiftUI and AppKit, use a shared singleton to ensure both frameworks reference the same state:

```swift
@MainActor
public final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selectedItem: SidebarItem = .default
    // ...
}

// In SwiftUI App
struct MyApp: App {
    private var appState: AppState { AppState.shared }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// In AppKit AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func createWindow() {
        let view = ContentView()
            .environmentObject(AppState.shared)  // Same instance!
        // ...
    }
}
```

### Anti-Pattern: Multiple Instances

```swift
// DON'T DO THIS - creates separate state!
struct MyApp: App {
    @StateObject private var appState = AppState()  // Instance 1
}

class AppDelegate {
    func createWindow() {
        .environmentObject(AppState())  // Instance 2 - NOT SHARED!
    }
}
```

---

## File Organization

### Recommended Console App Structure

```
AgentKitConsole/
├── AgentKitConsoleApp.swift     # Minimal - just scenes
├── Models/
│   ├── AppState.swift           # @MainActor, ObservableObject
│   ├── AgentTemplates.swift     # Static data
│   └── ViewModels/              # Per-view state
├── Views/
│   ├── Main/
│   │   ├── ContentView.swift
│   │   └── SidebarView.swift
│   ├── Agents/
│   │   ├── AgentPanelView.swift
│   │   └── AgentRecruitmentView.swift
│   ├── Overlays/
│   │   └── CommandPaletteView.swift
│   └── MenuBar/
│       └── MenuBarView.swift
└── Utilities/
    └── Extensions/
```

---

## Resources

- [SwiftUI on macOS - WWDC Sessions](https://developer.apple.com/videos/)
- [MenuBarExtra Documentation](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Scene Management](https://developer.apple.com/documentation/swiftui/scene)
