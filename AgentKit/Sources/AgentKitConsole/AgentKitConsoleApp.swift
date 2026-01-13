import AgentKit
import AppKit
import SwiftUI

// MARK: - App Delegate that ACTUALLY works

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            createAndShowWindow()
        }
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Task { @MainActor in
                createAndShowWindow()
            }
        }
        return true
    }

    func createAndShowWindow() {
        if window == nil {
            let contentView = ContentView()
                .environmentObject(AppState.shared)

            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window?.title = "Goldeneye"
            window?.center()
            window?.contentView = NSHostingView(rootView: contentView)
            window?.setFrameAutosaveName("MainWindow")
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Main App (minimal - delegate handles window)

@main
struct AgentKitConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private var appState: AppState { AppState.shared }

    var body: some Scene {
        // Menu bar only - window handled by AppDelegate
        MenuBarExtra("AgentKit", systemImage: appState.menuBarIcon) {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
