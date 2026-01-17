import AgentKit
import SwiftUI

// MARK: - Connections View

/// MCP server connections management view
struct ConnectionsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var connections: [MCPConnection] = []  // No sample data
    @State private var showAddConnectionSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Connected section
                let connectedConnections = connections.filter { $0.status == .connected || $0.status == .connecting }
                if !connectedConnections.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Connected")
                            .font(.headline)

                        ForEach(connectedConnections) { connection in
                            ConnectionCard(
                                connection: connection,
                                onDisconnect: {
                                    disconnectConnection(connection)
                                }
                            )
                        }
                    }
                }

                // Disconnected section
                let disconnectedConnections = connections.filter { connection in
                    if case .disconnected = connection.status { return true }
                    if case .error(_) = connection.status { return true }
                    return false
                }
                if !disconnectedConnections.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Available")
                            .font(.headline)

                        ForEach(disconnectedConnections) { connection in
                            ConnectionCard(
                                connection: connection,
                                onConnect: {
                                    connectConnection(connection)
                                }
                            )
                        }
                    }
                }

                // Discover more
                VStack(alignment: .leading, spacing: 12) {
                    Text("Discover")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150))], spacing: 12) {
                        ForEach(discoverableConnections, id: \.name) { item in
                            DiscoverCard(item: item) {
                                handleDiscoverSelection(item)
                            }
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

    // MARK: - Actions

    private func connectConnection(_ connection: MCPConnection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }

        connections[index].status = .connecting

        Task {
            do {
                // Create config based on connection type
                let config = MCPConnectionConfig(
                    id: connection.id.uuidString,
                    name: connection.name,
                    transport: .stdio(
                        command: "npx",
                        args: ["-y", "@modelcontextprotocol/server-\(connection.name.lowercased())"],
                        env: nil
                    )
                )

                let client = try await appState.mcpManager.addConnection(config)

                // Get tools from the connection
                let tools = await client.tools.map { $0.name }

                await MainActor.run {
                    if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
                        connections[idx].status = .connected
                        connections[idx].tools = tools
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
                        connections[idx].status = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func disconnectConnection(_ connection: MCPConnection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }

        Task {
            await appState.mcpManager.removeConnection(connection.id.uuidString)
        }

        connections[index].status = .disconnected
        connections[index].tools = []
    }

    private func handleDiscoverSelection(_ item: DiscoverableConnection) {
        if item.name == "Custom" {
            showAddConnectionSheet = true
        } else {
            // In real implementation, this would open specific setup flow
            // For now, show the add connection sheet
            showAddConnectionSheet = true
        }
    }
}

// MARK: - Connection Card

struct ConnectionCard: View {
    let connection: MCPConnection
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onViewTools: (() -> Void)?
    var onConfigure: (() -> Void)?
    @State private var isHovering = false
    @State private var showToolsSheet = false

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
                    Button(action: {
                        showToolsSheet = true
                    }) {
                        Label("View Tools", systemImage: "hammer")
                    }
                    Button(action: {
                        onConfigure?()
                    }) {
                        Label("Configure", systemImage: "gear")
                    }
                    Divider()
                    Button(role: .destructive, action: {
                        onDisconnect?()
                    }) {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            } else {
                Button("Connect") {
                    onConnect?()
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
        .sheet(isPresented: $showToolsSheet) {
            ConnectionToolsSheet(connection: connection)
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
        case .connecting:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 8, height: 8)
                Text("Connecting...")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
    var onSelect: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        Button(action: { onSelect?() }) {
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
    @EnvironmentObject private var appState: AppState

    @State private var name = ""
    @State private var serverURL = ""
    @State private var serverType: MCPServerType = .stdio
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Add MCP Connection")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Connection Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("My MCP Server", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

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

                TextField(
                    serverType == .stdio
                        ? "npx -y @modelcontextprotocol/server-filesystem ."
                        : "http://localhost:8080",
                    text: $serverURL
                )
                .textFieldStyle(.roundedBorder)
            }

            // Error display
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(8)
                .background(.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button(action: addConnection) {
                    if isConnecting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Connect")
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(serverURL.isEmpty || name.isEmpty || isConnecting)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private func addConnection() {
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                let transport: MCPTransport
                switch serverType {
                case .stdio:
                    // Parse command and arguments
                    let parts = serverURL.components(separatedBy: " ")
                    let command = parts.first ?? ""
                    let args = Array(parts.dropFirst())
                    transport = .stdio(command: command, args: args, env: nil)

                case .sse:
                    guard let url = URL(string: serverURL) else {
                        throw ConnectionError.invalidURL(serverURL)
                    }
                    transport = .sse(url: url, headers: nil)

                case .websocket:
                    guard let url = URL(string: serverURL) else {
                        throw ConnectionError.invalidURL(serverURL)
                    }
                    transport = .websocket(url: url, headers: nil)
                }

                let config = MCPConnectionConfig(
                    name: name,
                    transport: transport
                )

                _ = try await appState.mcpManager.addConnection(config)

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }
}

// MARK: - Connection Tools Sheet

struct ConnectionToolsSheet: View {
    let connection: MCPConnection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: connection.icon)
                    .font(.title2)
                Text(connection.name)
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Tools list
            if connection.tools.isEmpty {
                ContentUnavailableView(
                    "No Tools Available",
                    systemImage: "hammer",
                    description: Text("This connection doesn't expose any tools")
                )
            } else {
                List(connection.tools, id: \.self) { tool in
                    HStack {
                        Image(systemName: "function")
                            .foregroundStyle(.secondary)
                        Text(tool)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 400, height: 350)
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
    case connecting
    case disconnected
    case error(String)
}

enum MCPServerType: String, CaseIterable {
    case stdio
    case sse
    case websocket
}

enum ConnectionError: Error, LocalizedError {
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        }
    }
}

struct DiscoverableConnection {
    let name: String
    let icon: String
}

// MARK: - Discoverable Connection Types

private let discoverableConnections: [DiscoverableConnection] = [
    DiscoverableConnection(name: "GitHub", icon: "arrow.triangle.branch"),
    DiscoverableConnection(name: "Gmail", icon: "envelope"),
    DiscoverableConnection(name: "Notion", icon: "doc.plaintext"),
    DiscoverableConnection(name: "Slack", icon: "bubble.left.and.text.bubble.right"),
    DiscoverableConnection(name: "Web Search", icon: "globe"),
    DiscoverableConnection(name: "Custom", icon: "plus")
]
