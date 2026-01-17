import AgentKit
import SwiftUI

// MARK: - Command Palette

/// Spotlight-style command palette (⌘K) for quick navigation and actions
struct CommandPaletteView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            Divider()

            // Results
            if filteredCommands.isEmpty {
                emptyState
            } else {
                resultsList
            }

            // Footer hint
            footerHint
        }
        .frame(width: 600, height: 400)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            executeSelected()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField("Search commands, documents, agents...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
                .onChange(of: searchText) { _, _ in
                    selectedIndex = 0
                }

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(groupedCommands.keys.sorted()), id: \.self) { category in
                        if let commands = groupedCommands[category] {
                            Section {
                                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                                    let globalIndex = globalIndex(for: command)
                                    CommandRow(
                                        command: command,
                                        isSelected: globalIndex == selectedIndex
                                    )
                                    .id(command.id)
                                    .onTapGesture {
                                        execute(command)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(category)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if let command = filteredCommands[safe: newIndex] {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(command.id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No results found")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Try a different search term")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer Hint

    private var footerHint: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                KeyboardHint(key: "↑↓")
                Text("Navigate")
            }
            HStack(spacing: 4) {
                KeyboardHint(key: "↵")
                Text("Select")
            }
            HStack(spacing: 4) {
                KeyboardHint(key: "esc")
                Text("Close")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Commands

    private var allCommands: [PaletteCommand] {
        var commands: [PaletteCommand] = []

        // Navigation commands
        commands.append(contentsOf: [
            PaletteCommand(
                id: "nav-openspace",
                title: "Open Space",
                subtitle: "Quick capture & timeline",
                icon: "square.and.pencil",
                category: "Navigation",
                action: { appState.selectedSidebarItem = .headspace; dismiss() }
            ),
            PaletteCommand(
                id: "nav-documents",
                title: "Documents",
                subtitle: "All your documents",
                icon: "doc.text",
                category: "Navigation",
                action: { appState.selectedSidebarItem = .documents; dismiss() }
            ),
            PaletteCommand(
                id: "nav-threads",
                title: "Threads",
                subtitle: "Agent chat threads",
                icon: "bubble.left.and.bubble.right",
                category: "Navigation",
                action: { appState.selectedSidebarItem = .threads; dismiss() }
            ),
            PaletteCommand(
                id: "nav-tasks",
                title: "Tasks",
                subtitle: "Your task list",
                icon: "checklist",
                category: "Navigation",
                action: { appState.selectedSidebarItem = .tasks; dismiss() }
            ),
            PaletteCommand(
                id: "nav-agents",
                title: "Agents",
                subtitle: "Manage your agents",
                icon: "person.2",
                category: "Navigation",
                action: { appState.selectedSidebarItem = .agents; dismiss() }
            ),
            PaletteCommand(
                id: "nav-connections",
                title: "Connections",
                subtitle: "MCP servers & integrations",
                icon: "link",
                category: "Navigation",
                action: { appState.selectedSidebarItem = .connections; dismiss() }
            ),
        ])

        // Action commands
        commands.append(contentsOf: [
            PaletteCommand(
                id: "action-new-doc",
                title: "New Document",
                subtitle: "Create a new document",
                icon: "doc.badge.plus",
                category: "Actions",
                shortcut: "⌘N",
                action: { appState.showNewDocumentSheet = true; dismiss() }
            ),
            PaletteCommand(
                id: "action-new-thread",
                title: "New Thread",
                subtitle: "Start a chat with an agent",
                icon: "bubble.left.and.bubble.right",
                category: "Actions",
                shortcut: "⌘⇧N",
                action: { appState.showNewThreadSheet = true; dismiss() }
            ),
            PaletteCommand(
                id: "action-new-task",
                title: "New Task",
                subtitle: "Create a task for an agent",
                icon: "plus.circle",
                category: "Actions",
                action: { appState.showNewTaskSheet = true; dismiss() }
            ),
            PaletteCommand(
                id: "action-toggle-agent",
                title: "Toggle Agent Panel",
                subtitle: "Open/close the agent assistant",
                icon: "sparkles",
                category: "Actions",
                shortcut: "⌘/",
                action: { appState.isAgentPanelVisible.toggle(); dismiss() }
            ),
            PaletteCommand(
                id: "action-recruit-agent",
                title: "Recruit Agent",
                subtitle: "Add a new agent to your team",
                icon: "person.badge.plus",
                category: "Actions",
                iconColor: .purple,
                action: { appState.showAgentRecruitment = true; dismiss() }
            ),
            PaletteCommand(
                id: "action-build-agent",
                title: "Build Custom Agent",
                subtitle: "Create your own agent through conversation",
                icon: "wand.and.stars",
                category: "Actions",
                shortcut: "⌘⇧B",
                iconColor: .purple,
                action: { appState.showAgentBuilder = true; dismiss() }
            ),
        ])

        // Recent documents
        for doc in appState.workspace.documents.prefix(5) {
            commands.append(PaletteCommand(
                id: "doc-\(doc.id.rawValue)",
                title: doc.title.isEmpty ? "Untitled" : doc.title,
                subtitle: "Document • \(doc.updatedAt.formatted(.relative(presentation: .named)))",
                icon: "doc.text",
                category: "Recent Documents",
                action: {
                    appState.selectedSidebarItem = .documents
                    appState.selectedDocumentId = doc.id
                    dismiss()
                }
            ))
        }

        // Recent threads
        for thread in appState.workspace.threads.prefix(5) {
            commands.append(PaletteCommand(
                id: "thread-\(thread.id.rawValue)",
                title: thread.title,
                subtitle: "Thread • \(thread.container.agentName ?? "Agent")",
                icon: "bubble.left",
                category: "Recent Threads",
                action: {
                    appState.selectedSidebarItem = .threads
                    appState.selectedThreadId = thread.id
                    dismiss()
                }
            ))
        }

        // Connected agents
        if let localAgent = appState.localAgent {
            commands.append(PaletteCommand(
                id: "agent-local",
                title: localAgent.name,
                subtitle: localAgent.status.isConnected ? "Connected" : "Disconnected",
                icon: "sparkles",
                category: "Agents",
                iconColor: .purple,
                action: {
                    appState.selectedSidebarItem = .agents
                    dismiss()
                }
            ))
        }

        for agent in appState.connectedAgents {
            commands.append(PaletteCommand(
                id: "agent-\(agent.id)",
                title: agent.name,
                subtitle: agent.status.isConnected ? "Connected" : "Disconnected",
                icon: "person.circle",
                category: "Agents",
                iconColor: .blue,
                action: {
                    appState.selectedSidebarItem = .agents
                    dismiss()
                }
            ))
        }

        return commands
    }

    private var filteredCommands: [PaletteCommand] {
        if searchText.isEmpty {
            return allCommands
        }

        let query = searchText.lowercased()
        return allCommands.filter { command in
            command.title.lowercased().contains(query) ||
            command.subtitle.lowercased().contains(query) ||
            command.category.lowercased().contains(query)
        }
    }

    private var groupedCommands: [String: [PaletteCommand]] {
        Dictionary(grouping: filteredCommands, by: { $0.category })
    }

    private func globalIndex(for command: PaletteCommand) -> Int {
        filteredCommands.firstIndex(where: { $0.id == command.id }) ?? 0
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        let newIndex = selectedIndex + delta
        if newIndex >= 0 && newIndex < filteredCommands.count {
            selectedIndex = newIndex
        }
    }

    private func executeSelected() {
        if let command = filteredCommands[safe: selectedIndex] {
            execute(command)
        }
    }

    private func execute(_ command: PaletteCommand) {
        command.action()
    }
}

// MARK: - Command Model

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let category: String
    var shortcut: String? = nil
    var iconColor: Color = .secondary
    let action: () -> Void
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: command.icon)
                .font(.title3)
                .foregroundStyle(command.iconColor)
                .frame(width: 28)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(command.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Shortcut
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Keyboard Hint

private struct KeyboardHint: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.caption.monospaced())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Array Extension

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
