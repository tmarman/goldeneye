import AgentKit
import SwiftUI

@main
struct AgentKitConsoleApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            AgentCommands(appState: appState)
        }

        // Menu bar presence
        MenuBarExtra("AgentKit", systemImage: appState.menuBarIcon) {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Custom Commands

struct AgentCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu("Agent") {
            Button("New Task...") {
                appState.showNewTaskSheet = true
            }
            .keyboardShortcut("n", modifiers: [.command])

            Divider()

            Button("Connect to Agent...") {
                appState.showConnectSheet = true
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Button("Approve All Pending") {
                Task { await appState.approveAllPending() }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(appState.pendingApprovals.isEmpty)
        }
    }
}
