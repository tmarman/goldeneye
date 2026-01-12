import AgentKit
import SwiftUI

// MARK: - Connections View

/// MCP server connections management view
struct ConnectionsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var connections: [MCPConnection] = sampleConnections
    @State private var showAddConnectionSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Connected section
                if !connections.filter({ $0.status == .connected }).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connected")
                            .font(.headline)

                        ForEach(connections.filter { $0.status == .connected }) { connection in
                            ConnectionCard(connection: connection)
                        }
                    }
                }

                // Disconnected section
                if !connections.filter({ $0.status != .connected }).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Available")
                            .font(.headline)

                        ForEach(connections.filter { $0.status != .connected }) { connection in
                            ConnectionCard(connection: connection)
                        }
                    }
                }

                // Discover more
                VStack(alignment: .leading, spacing: 12) {
                    Text("Discover")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150))], spacing: 12) {
                        ForEach(discoverableConnections, id: \.name) { item in
                            DiscoverCard(item: item)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Connections")
        .toolbar {
            ToolbarItem {
                Button(action: { showAddConnectionSheet = true }) {
                    Label("Add Connection", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddConnectionSheet) {
            AddConnectionSheet()
        }
    }
}

// MARK: - Connection Card

struct ConnectionCard: View {
    let connection: MCPConnection
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: connection.icon)
                .font(.title2)
                .foregroundStyle(connection.status == .connected ? .green : .secondary)
                .frame(width: 44, height: 44)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(connection.name)
                        .font(.headline)

                    statusIndicator
                }

                Text(connection.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if connection.status == .connected {
                    Text("Tools: \(connection.tools.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Actions
            if connection.status == .connected {
                Menu {
                    Button(action: {}) {
                        Label("View Tools", systemImage: "hammer")
                    }
                    Button(action: {}) {
                        Label("Configure", systemImage: "gear")
                    }
                    Divider()
                    Button(role: .destructive, action: {}) {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            } else {
                Button("Connect") {
                    // Connect action
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovering ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch connection.status {
        case .connected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        case .disconnected:
            HStack(spacing: 4) {
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
                Text("Disconnected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Discover Card

struct DiscoverCard: View {
    let item: DiscoverableConnection
    @State private var isHovering = false

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text(item.name)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovering ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Add Connection Sheet

struct AddConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var serverType: MCPServerType = .stdio

    var body: some View {
        VStack(spacing: 20) {
            Text("Add MCP Connection")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Server Type")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Type", selection: $serverType) {
                    Text("Standard I/O").tag(MCPServerType.stdio)
                    Text("HTTP/SSE").tag(MCPServerType.sse)
                    Text("WebSocket").tag(MCPServerType.websocket)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(serverType == .stdio ? "Command" : "URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField(serverType == .stdio ? "npx @modelcontextprotocol/server" : "http://localhost:8080", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Connect") {
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(serverURL.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Supporting Types

struct MCPConnection: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    var status: ConnectionStatus
    var tools: [String]
}

enum ConnectionStatus: Equatable {
    case connected
    case disconnected
    case error(String)
}

enum MCPServerType: String, CaseIterable {
    case stdio
    case sse
    case websocket
}

struct DiscoverableConnection {
    let name: String
    let icon: String
}

// MARK: - Sample Data

private let sampleConnections: [MCPConnection] = [
    MCPConnection(
        name: "Filesystem",
        description: "Local file access for documents and data",
        icon: "folder",
        status: .connected,
        tools: ["read_file", "write_file", "list_directory"]
    ),
    MCPConnection(
        name: "PostgreSQL",
        description: "Query your database with natural language",
        icon: "cylinder",
        status: .connected,
        tools: ["query", "describe_table", "list_tables"]
    ),
    MCPConnection(
        name: "Calendar",
        description: "Access your calendar events",
        icon: "calendar",
        status: .disconnected,
        tools: []
    )
]

private let discoverableConnections: [DiscoverableConnection] = [
    DiscoverableConnection(name: "GitHub", icon: "arrow.triangle.branch"),
    DiscoverableConnection(name: "Gmail", icon: "envelope"),
    DiscoverableConnection(name: "Notion", icon: "doc.plaintext"),
    DiscoverableConnection(name: "Slack", icon: "bubble.left.and.text.bubble.right"),
    DiscoverableConnection(name: "Web Search", icon: "globe"),
    DiscoverableConnection(name: "Custom", icon: "plus")
]
