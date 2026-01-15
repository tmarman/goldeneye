import Foundation
import Logging

// MARK: - MCP Manager

/// Manages multiple MCP server connections and exposes their tools to agents.
///
/// The MCP Manager acts as a bridge between agent tools and external MCP servers.
/// It discovers tools from connected servers and creates tool wrappers that can
/// be used by the agent loop.
///
/// Example:
/// ```swift
/// let manager = MCPManager()
///
/// // Add a file system server
/// try await manager.addConnection(MCPConnectionConfig(
///     name: "File System",
///     transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "."], env: nil)
/// ))
///
/// // Get all tools (including MCP tools)
/// let tools = await manager.getAllTools()
/// ```
public actor MCPManager {
    /// All configured connections
    private var connections: [String: MCPClient] = [:]

    /// Connection configurations (for reconnection)
    private var configs: [String: MCPConnectionConfig] = [:]

    /// Logger
    private let logger = Logger(label: "AgentKit.MCP")

    /// Cached tools from all connections
    private var cachedTools: [String: MCPTool] = [:]

    public init() {}

    // MARK: - Connection Management

    /// Add a new MCP connection
    @discardableResult
    public func addConnection(_ config: MCPConnectionConfig) async throws -> MCPClient {
        let client = MCPClient(
            id: config.id,
            name: config.name,
            transport: config.transport
        )

        try await client.connect()

        connections[config.id] = client
        configs[config.id] = config

        // Cache tools
        let tools = await client.tools
        for tool in tools {
            cachedTools["\(config.id):\(tool.name)"] = tool
        }

        logger.info("Added MCP connection", metadata: [
            "id": "\(config.id)",
            "name": "\(config.name)",
            "tools": "\(tools.count)"
        ])

        return client
    }

    /// Remove a connection
    public func removeConnection(_ id: String) async {
        if let client = connections.removeValue(forKey: id) {
            await client.disconnect()

            // Remove cached tools
            cachedTools = cachedTools.filter { !$0.key.hasPrefix("\(id):") }
        }
        configs.removeValue(forKey: id)

        logger.info("Removed MCP connection", metadata: ["id": "\(id)"])
    }

    /// Get a connection by ID
    public func connection(_ id: String) -> MCPClient? {
        connections[id]
    }

    /// Get all connection IDs
    public var connectionIds: [String] {
        Array(connections.keys)
    }

    /// Get all connections
    public var allConnections: [MCPClient] {
        Array(connections.values)
    }

    /// Get the number of connections
    public var connectionCount: Int {
        connections.count
    }

    // MARK: - Tool Discovery

    /// Get all tools from all connected MCP servers
    public func getAllMCPTools() -> [MCPTool] {
        Array(cachedTools.values)
    }

    /// Get tools as AgentKit Tool protocol objects
    public func getToolWrappers() -> [Tool] {
        cachedTools.map { key, tool in
            MCPToolWrapper(
                connectionId: String(key.split(separator: ":").first ?? ""),
                mcpTool: tool,
                manager: self
            )
        }
    }

    /// Refresh tools from all connections
    public func refreshAllTools() async {
        cachedTools.removeAll()

        for (id, client) in connections {
            await client.refreshTools()
            let tools = await client.tools
            for tool in tools {
                cachedTools["\(id):\(tool.name)"] = tool
            }
        }

        logger.info("Refreshed MCP tools", metadata: ["total": "\(cachedTools.count)"])
    }

    // MARK: - Tool Execution

    /// Call a tool on a specific connection
    public func callTool(
        connectionId: String,
        toolName: String,
        arguments: [String: Any]
    ) async throws -> MCPToolResult {
        guard let client = connections[connectionId] else {
            throw MCPError.notConnected
        }

        // Serialize to Data (which is Sendable) to safely cross actor boundaries
        let argumentsData = try JSONSerialization.data(withJSONObject: arguments)
        return try await client.callTool(toolName, argumentsData: argumentsData)
    }

    // MARK: - Preset Configurations

    /// Create a file system MCP connection
    public static func fileSystemConfig(path: String, name: String = "File System") -> MCPConnectionConfig {
        MCPConnectionConfig(
            name: name,
            transport: .stdio(
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem", path],
                env: nil
            )
        )
    }

    /// Create a git MCP connection
    public static func gitConfig(repoPath: String, name: String = "Git") -> MCPConnectionConfig {
        MCPConnectionConfig(
            name: name,
            transport: .stdio(
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-git", "--repository", repoPath],
                env: nil
            )
        )
    }

    /// Create a memory/knowledge base MCP connection
    public static func memoryConfig(name: String = "Memory") -> MCPConnectionConfig {
        MCPConnectionConfig(
            name: name,
            transport: .stdio(
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-memory"],
                env: nil
            )
        )
    }

    /// Create a web fetch MCP connection
    public static func webFetchConfig(name: String = "Web") -> MCPConnectionConfig {
        MCPConnectionConfig(
            name: name,
            transport: .stdio(
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-fetch"],
                env: nil
            )
        )
    }
}

// MARK: - Configuration

/// Configuration for an MCP connection
public struct MCPConnectionConfig: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let transport: MCPTransport
    public var autoConnect: Bool
    public var enabled: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        transport: MCPTransport,
        autoConnect: Bool = true,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.autoConnect = autoConnect
        self.enabled = enabled
    }
}

// MARK: - Tool Wrapper

/// Wraps an MCP tool as an AgentKit Tool
public struct MCPToolWrapper: Tool {
    public let connectionId: String
    public let mcpTool: MCPTool

    // Weak reference via unowned to avoid retain cycles
    private let manager: MCPManager

    public var name: String { "mcp_\(connectionId)_\(mcpTool.name)" }
    public var description: String { mcpTool.description ?? "MCP tool: \(mcpTool.name)" }

    public var inputSchema: ToolSchema {
        // Convert MCP schema to ToolSchema
        var properties: [String: ToolSchema.PropertySchema] = [:]

        if let schemaProps = mcpTool.inputSchema["properties"] as? [String: [String: Any]] {
            for (key, value) in schemaProps {
                let type = value["type"] as? String ?? "string"
                let desc = value["description"] as? String
                properties[key] = ToolSchema.PropertySchema(type: type, description: desc)
            }
        }

        let required = mcpTool.inputSchema["required"] as? [String] ?? []

        return ToolSchema(properties: properties, required: required)
    }

    public var requiresApproval: Bool { false }
    public var riskLevel: RiskLevel { .low }

    init(connectionId: String, mcpTool: MCPTool, manager: MCPManager) {
        self.connectionId = connectionId
        self.mcpTool = mcpTool
        self.manager = manager
    }

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        // Convert parameters to arguments
        var arguments: [String: Any] = [:]
        for (key, value) in input.parameters {
            arguments[key] = value.value
        }

        do {
            let result = try await manager.callTool(
                connectionId: connectionId,
                toolName: mcpTool.name,
                arguments: arguments
            )

            if result.isError {
                return .error(result.text ?? "MCP tool error")
            }

            return .success(result.text ?? "")
        } catch {
            return .error("MCP error: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        "Call MCP tool '\(mcpTool.name)' via \(connectionId)"
    }
}

// MARK: - Configuration Persistence

extension MCPManager {
    /// Save configurations to a file
    public func saveConfigs(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Convert configs to saveable format
        let saveableConfigs = configs.values.map { config -> SaveableMCPConfig in
            SaveableMCPConfig(from: config)
        }

        let data = try encoder.encode(saveableConfigs)
        try data.write(to: url)
    }

    /// Load configurations from a file
    public func loadConfigs(from url: URL) throws -> [MCPConnectionConfig] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let saveableConfigs = try decoder.decode([SaveableMCPConfig].self, from: data)
        return saveableConfigs.map { $0.toConfig() }
    }
}

/// Serializable version of MCPConnectionConfig
private struct SaveableMCPConfig: Codable {
    let id: String
    let name: String
    let transportType: String
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let url: String?
    let headers: [String: String]?
    let autoConnect: Bool
    let enabled: Bool

    init(from config: MCPConnectionConfig) {
        self.id = config.id
        self.name = config.name
        self.autoConnect = config.autoConnect
        self.enabled = config.enabled

        switch config.transport {
        case .stdio(let command, let args, let env):
            self.transportType = "stdio"
            self.command = command
            self.args = args
            self.env = env
            self.url = nil
            self.headers = nil

        case .sse(let url, let headers):
            self.transportType = "sse"
            self.command = nil
            self.args = nil
            self.env = nil
            self.url = url.absoluteString
            self.headers = headers

        case .websocket(let url, let headers):
            self.transportType = "websocket"
            self.command = nil
            self.args = nil
            self.env = nil
            self.url = url.absoluteString
            self.headers = headers
        }
    }

    func toConfig() -> MCPConnectionConfig {
        let transport: MCPTransport
        switch transportType {
        case "stdio":
            transport = .stdio(command: command ?? "", args: args ?? [], env: env)
        case "sse":
            transport = .sse(url: URL(string: url ?? "")!, headers: headers)
        case "websocket":
            transport = .websocket(url: URL(string: url ?? "")!, headers: headers)
        default:
            transport = .stdio(command: "", args: [], env: nil)
        }

        return MCPConnectionConfig(
            id: id,
            name: name,
            transport: transport,
            autoConnect: autoConnect,
            enabled: enabled
        )
    }
}
