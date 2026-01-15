import AgentKit
import AppKit
import SwiftUI

// MARK: - App Delegate that ACTUALLY works

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var quickNoteWindows: [UUID: NSWindow] = [:]

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            setupAppIcon()
            createAndShowWindow()
            setupQuickNoteListener()
        }
    }

    func setupQuickNoteListener() {
        NotificationCenter.default.addObserver(
            forName: .createQuickNote,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.createQuickNoteWindow()
            }
        }
    }

    func createQuickNoteWindow() {
        let noteId = UUID()

        // Create the quick note view
        let quickNoteView = QuickNoteView(
            noteId: noteId,
            onClose: { [weak self] content in
                self?.closeQuickNote(id: noteId, content: content)
            }
        )
        .environmentObject(AppState.shared)

        // Create a floating panel-style window
        let noteWindow = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        noteWindow.title = "Quick Note"
        noteWindow.titlebarAppearsTransparent = true
        noteWindow.isMovableByWindowBackground = true
        noteWindow.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        noteWindow.level = .floating
        noteWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        noteWindow.contentView = NSHostingView(rootView: quickNoteView)
        noteWindow.isReleasedWhenClosed = false

        // Position near cursor or stagger from existing notes
        let mouseLocation = NSEvent.mouseLocation
        let offsetIndex = quickNoteWindows.count
        noteWindow.setFrameOrigin(NSPoint(
            x: mouseLocation.x + CGFloat(offsetIndex * 30) - 160,
            y: mouseLocation.y + CGFloat(offsetIndex * -30) - 200
        ))

        quickNoteWindows[noteId] = noteWindow
        noteWindow.makeKeyAndOrderFront(nil)
    }

    func closeQuickNote(id: UUID, content: String) {
        guard let noteWindow = quickNoteWindows[id] else { return }

        // Only persist if there's actual content
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Create a new conversation from the quick note
            let newConv = Conversation(
                title: generateNoteTitle(from: content),
                messages: [
                    ConversationMessage(role: .user, content: content)
                ],
                agentName: nil
            )
            AppState.shared.workspace.conversations.insert(newConv, at: 0)
        }

        noteWindow.close()
        quickNoteWindows.removeValue(forKey: id)
    }

    private func generateNoteTitle(from content: String) -> String {
        // Use first line or first few words as title
        let firstLine = content.components(separatedBy: .newlines).first ?? content
        let words = firstLine.components(separatedBy: .whitespaces).prefix(6)
        let title = words.joined(separator: " ")

        if title.count > 40 {
            return String(title.prefix(40)) + "…"
        }
        return title.isEmpty ? "Quick Note" : title
    }

    func setupAppIcon() {
        // Load the app icon from the bundle resources
        // Try different resource paths that SPM might use
        if let iconURL = Bundle.main.url(forResource: "icon_512x512@2x", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        } else if let iconURL = Bundle.main.url(forResource: "icon_512x512", withExtension: "png"),
                  let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        } else if let iconURL = Bundle.main.url(forResource: "icon_256x256@2x", withExtension: "png"),
                  let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        } else {
            // Fall back to named image from asset catalog
            if let iconImage = NSImage(named: "AppIcon") {
                NSApp.applicationIconImage = iconImage
            }
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
        // Ensure app is a regular app that can receive focus
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let contentView = ContentView()
                .environmentObject(AppState.shared)
                .environment(ChatService.shared)
                .environment(ProviderConfigManager.shared)

            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window?.title = "Envoy"
            window?.titlebarAppearsTransparent = true
            window?.titleVisibility = .hidden
            window?.center()
            window?.contentView = NSHostingView(rootView: contentView)
            window?.setFrameAutosaveName("MainWindow")
            window?.isReleasedWhenClosed = false

            // Make window key window
            window?.becomeKey()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Main App (minimal - delegate handles window)

@main
struct EnvoyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private var appState: AppState { AppState.shared }

    var body: some Scene {
        // Menu bar only - window handled by AppDelegate
        MenuBarExtra("Envoy", systemImage: appState.menuBarIcon) {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
        .commands {
            // Add Settings menu item that navigates to inline settings
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // Model selection shortcut
            CommandGroup(after: .newItem) {
                Button("Quick Note") {
                    NotificationCenter.default.post(name: .createQuickNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Select Model…") {
                    NotificationCenter.default.post(name: .openModelPicker, object: nil)
                }
                .keyboardShortcut("m", modifiers: .command)

                Button("New Conversation") {
                    AppState.shared.showNewConversationSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        // Settings are now inline in the main window (accessed via sidebar)
        // No separate Settings window - Cmd+, navigates to settings in sidebar
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let openModelPicker = Notification.Name("openModelPicker")
    static let deleteSelectedConversation = Notification.Name("deleteSelectedConversation")
    static let createQuickNote = Notification.Name("createQuickNote")
}

// MARK: - Quick Note View (Post-it style floating note)

struct QuickNoteView: View {
    let noteId: UUID
    let onClose: (String) -> Void

    @EnvironmentObject private var appState: AppState
    @State private var content: String = ""
    @FocusState private var isFocused: Bool

    // Available colors for post-it style
    private let noteColors: [Color] = [
        Color(red: 1.0, green: 0.98, blue: 0.8),   // Yellow
        Color(red: 0.8, green: 0.95, blue: 1.0),   // Blue
        Color(red: 0.95, green: 0.85, blue: 1.0),  // Purple
        Color(red: 0.85, green: 1.0, blue: 0.85),  // Green
        Color(red: 1.0, green: 0.9, blue: 0.85),   // Orange
    ]

    @State private var selectedColorIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with color picker and close
            HStack(spacing: 8) {
                // Color dots
                ForEach(0..<noteColors.count, id: \.self) { index in
                    Circle()
                        .fill(noteColors[index])
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.3), lineWidth: selectedColorIndex == index ? 2 : 0)
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedColorIndex = index
                            }
                        }
                }

                Spacer()

                // Character count
                Text("\(content.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Save & close button
                Button(action: { onClose(content) }) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Save and close (Cmd+Return)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(noteColors[selectedColorIndex].opacity(0.5))

            // Note content
            TextEditor(text: $content)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .background(noteColors[selectedColorIndex].opacity(0.3))
                .focused($isFocused)
                .padding(8)

            // Footer with hints
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.orange)
                    .font(.caption2)
                Text("Empty notes auto-discard")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("⌘⏎ Save")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(noteColors[selectedColorIndex].opacity(0.2))
        }
        .background(noteColors[selectedColorIndex].opacity(0.15))
        .onAppear {
            // Random color for each new note
            selectedColorIndex = Int.random(in: 0..<noteColors.count)
            isFocused = true
        }
        .onExitCommand {
            // Escape closes without saving empty notes
            onClose(content)
        }
    }
}

