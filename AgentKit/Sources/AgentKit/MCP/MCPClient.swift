import Foundation

// MARK: - MCP Client

/// Client for Model Context Protocol (MCP) servers.
///
/// MCP allows agents to connect to external tools and resources. This client
/// supports multiple transport types:
/// - **stdio**: Local processes (most common for file system, git, etc.)
/// - **HTTP/SSE**: Remote servers with HTTP transport
/// - **WebSocket**: Full-duplex connections
///
/// Example usage:
/// ```swift
/// let client = MCPClient(transport: .stdio(command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "."]))
/// try await client.connect()
/// let tools = try await client.listTools()
/// let result = try await client.callTool("read_file", arguments: ["path": "/tmp/test.txt"])
/// ```
public actor MCPClient {
    /// Unique identifier for this client
    public nonisolated let id: String

    /// Display name for this connection
    public nonisolated let name: String

    /// Transport configuration
    public let transport: MCPTransport

    /// Current connection state
    public private(set) var state: MCPConnectionState = .disconnected

    /// Server capabilities discovered during initialization
    public private(set) var serverCapabilities: MCPServerCapabilities?

    /// Available tools from this server
    public private(set) var tools: [MCPTool] = []

    /// Available resources from this server
    public private(set) var resources: [MCPResource] = []

    // Internal
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var requestId: Int = 0
    private var pendingRequests: [Int: CheckedContinuation<MCPResponse, Error>] = [:]
    private var readTask: Task<Void, Never>?

    public init(
        id: String = UUID().uuidString,
        name: String,
        transport: MCPTransport
    ) {
        self.id = id
        self.name = name
        self.transport = transport
    }

    // MARK: - Connection

    /// Connect to the MCP server
    public func connect() async throws {
        guard state == .disconnected else { return }
        state = .connecting

        switch transport {
        case .stdio(let command, let args, let env):
            try await connectStdio(command: command, args: args, env: env)
        case .sse(let url, let headers):
            try await connectSSE(url: url, headers: headers)
        case .websocket(let url, let headers):
            try await connectWebSocket(url: url, headers: headers)
        }

        // Initialize the connection
        try await initialize()
        state = .connected
    }

    /// Disconnect from the MCP server
    public func disconnect() async {
        state = .disconnecting

        readTask?.cancel()
        readTask = nil

        if let process = process, process.isRunning {
            process.terminate()
        }
        process = nil
        inputPipe = nil
        outputPipe = nil

        // Cancel pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: MCPError.disconnected)
        }
        pendingRequests.removeAll()

        state = .disconnected
    }

    // MARK: - stdio Transport

    private func connectStdio(command: String, args: [String], env: [String: String]?) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

        // Set environment
        var environment = ProcessInfo.processInfo.environment
        if let env = env {
            environment.merge(env) { _, new in new }
        }
        process.environment = environment

        // Set up pipes
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe

        try process.run()

        // Start reading responses
        startReading()
    }

    private func startReading() {
        guard let outputPipe = outputPipe else { return }

        readTask = Task {
            let handle = outputPipe.fileHandleForReading

            while !Task.isCancelled {
                let data = handle.availableData
                guard !data.isEmpty else {
                    // End of stream or no data
                    try? await Task.sleep(for: .milliseconds(10))
                    continue
                }

                // Parse JSON-RPC response
                if let response = try? JSONDecoder().decode(MCPResponse.self, from: data) {
                    if let requestId = response.id,
                       let continuation = pendingRequests.removeValue(forKey: requestId) {
                        continuation.resume(returning: response)
                    }
                }
            }
        }
    }

    // MARK: - HTTP/SSE Transport

    private func connectSSE(url: URL, headers: [String: String]?) async throws {
        // TODO: Implement SSE transport
        throw MCPError.transportNotSupported("SSE transport not yet implemented")
    }

    // MARK: - WebSocket Transport

    private func connectWebSocket(url: URL, headers: [String: String]?) async throws {
        // TODO: Implement WebSocket transport
        throw MCPError.transportNotSupported("WebSocket transport not yet implemented")
    }

    // MARK: - Protocol Methods

    /// Initialize the MCP connection
    private func initialize() async throws {
        let params: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "roots": ["listChanged": true],
                "sampling": [:]
            ],
            "clientInfo": [
                "name": "AgentKit",
                "version": "0.1.0"
            ]
        ]

        let response = try await sendRequest(method: "initialize", params: params)

        // Parse server capabilities
        if let result = response.result,
           let data = try? JSONSerialization.data(withJSONObject: result),
           let capabilities = try? JSONDecoder().decode(MCPServerCapabilities.self, from: data) {
            serverCapabilities = capabilities
        }

        // Send initialized notification
        try await sendNotification(method: "notifications/initialized", params: [:])

        // List available tools
        await refreshTools()

        // List available resources
        await refreshResources()
    }

    /// Refresh the list of available tools
    public func refreshTools() async {
        do {
            let response = try await sendRequest(method: "tools/list", params: [:])
            if let result = response.result as? [String: Any],
               let toolsArray = result["tools"] as? [[String: Any]] {
                tools = toolsArray.compactMap { MCPTool(from: $0) }
            }
        } catch {
            print("Failed to list tools: \(error)")
        }
    }

    /// Refresh the list of available resources
    public func refreshResources() async {
        do {
            let response = try await sendRequest(method: "resources/list", params: [:])
            if let result = response.result as? [String: Any],
               let resourcesArray = result["resources"] as? [[String: Any]] {
                resources = resourcesArray.compactMap { MCPResource(from: $0) }
            }
        } catch {
            print("Failed to list resources: \(error)")
        }
    }

    /// List available tools
    public func listTools() async throws -> [MCPTool] {
        await refreshTools()
        return tools
    }

    /// Call a tool with arguments as JSON data (Sendable-safe)
    public func callTool(_ name: String, argumentsData: Data) async throws -> MCPToolResult {
        let arguments = try JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] ?? [:]

        let params: [String: Any] = [
            "name": name,
            "arguments": arguments
        ]

        let response = try await sendRequest(method: "tools/call", params: params)

        guard let result = response.result as? [String: Any] else {
            throw MCPError.invalidResponse
        }

        return MCPToolResult(from: result)
    }

    /// Call a tool (convenience for non-actor contexts)
    public func callTool(_ name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        let data = try JSONSerialization.data(withJSONObject: arguments)
        return try await callTool(name, argumentsData: data)
    }

    /// Read a resource
    public func readResource(_ uri: String) async throws -> MCPResourceContent {
        let params: [String: Any] = [
            "uri": uri
        ]

        let response = try await sendRequest(method: "resources/read", params: params)

        guard let result = response.result as? [String: Any] else {
            throw MCPError.invalidResponse
        }

        return MCPResourceContent(from: result)
    }

    // MARK: - JSON-RPC

    private func sendRequest(method: String, params: [String: Any]) async throws -> MCPResponse {
        guard state == .connected || state == .connecting else {
            throw MCPError.notConnected
        }

        requestId += 1
        let id = requestId

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]

        let data = try JSONSerialization.data(withJSONObject: request)
        var message = data
        message.append(contentsOf: "\n".utf8)

        guard let inputPipe = inputPipe else {
            throw MCPError.notConnected
        }

        inputPipe.fileHandleForWriting.write(message)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }

    private func sendNotification(method: String, params: [String: Any]) async throws {
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]

        let data = try JSONSerialization.data(withJSONObject: notification)
        var message = data
        message.append(contentsOf: "\n".utf8)

        inputPipe?.fileHandleForWriting.write(message)
    }
}

// MARK: - Transport Types

/// MCP transport configuration
public enum MCPTransport: Sendable {
    /// stdio transport - communicates with a local process
    case stdio(command: String, args: [String], env: [String: String]?)

    /// HTTP/SSE transport - communicates via Server-Sent Events
    case sse(url: URL, headers: [String: String]?)

    /// WebSocket transport - full-duplex communication
    case websocket(url: URL, headers: [String: String]?)
}

// MARK: - Connection State

public enum MCPConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error
}

// MARK: - Protocol Types

/// Server capabilities returned during initialization
public struct MCPServerCapabilities: Codable, Sendable {
    public let tools: ToolCapabilities?
    public let resources: ResourceCapabilities?
    public let prompts: PromptCapabilities?
    public let logging: LoggingCapabilities?

    public struct ToolCapabilities: Codable, Sendable {
        public let listChanged: Bool?
    }

    public struct ResourceCapabilities: Codable, Sendable {
        public let subscribe: Bool?
        public let listChanged: Bool?
    }

    public struct PromptCapabilities: Codable, Sendable {
        public let listChanged: Bool?
    }

    public struct LoggingCapabilities: Codable, Sendable {}
}

/// An MCP tool definition
public struct MCPTool: Identifiable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let inputSchema: [String: Any]

    public init(from dict: [String: Any]) {
        self.name = dict["name"] as? String ?? ""
        self.id = name
        self.description = dict["description"] as? String
        self.inputSchema = dict["inputSchema"] as? [String: Any] ?? [:]
    }
}

/// Result from calling a tool
public struct MCPToolResult: Sendable {
    public let content: [MCPContent]
    public let isError: Bool

    public init(from dict: [String: Any]) {
        self.isError = dict["isError"] as? Bool ?? false

        if let contentArray = dict["content"] as? [[String: Any]] {
            self.content = contentArray.map { MCPContent(from: $0) }
        } else {
            self.content = []
        }
    }

    /// Get text content
    public var text: String? {
        content.compactMap { $0.text }.first
    }
}

/// An MCP resource definition
public struct MCPResource: Identifiable, Sendable {
    public let id: String
    public let uri: String
    public let name: String
    public let description: String?
    public let mimeType: String?

    public init(from dict: [String: Any]) {
        self.uri = dict["uri"] as? String ?? ""
        self.id = uri
        self.name = dict["name"] as? String ?? uri
        self.description = dict["description"] as? String
        self.mimeType = dict["mimeType"] as? String
    }
}

/// Content from a resource
public struct MCPResourceContent: Sendable {
    public let contents: [MCPContent]

    public init(from dict: [String: Any]) {
        if let contentArray = dict["contents"] as? [[String: Any]] {
            self.contents = contentArray.map { MCPContent(from: $0) }
        } else {
            self.contents = []
        }
    }
}

/// MCP content item
public struct MCPContent: Sendable {
    public let type: String
    public let text: String?
    public let data: Data?
    public let mimeType: String?

    public init(from dict: [String: Any]) {
        self.type = dict["type"] as? String ?? "text"
        self.text = dict["text"] as? String
        self.mimeType = dict["mimeType"] as? String

        if let base64 = dict["data"] as? String {
            self.data = Data(base64Encoded: base64)
        } else {
            self.data = nil
        }
    }
}

/// JSON-RPC response
public struct MCPResponse: Decodable, @unchecked Sendable {
    public let jsonrpc: String
    public let id: Int?
    public let result: Any?
    public let error: MCPResponseError?

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        error = try container.decodeIfPresent(MCPResponseError.self, forKey: .error)

        // Decode result as Any
        if let resultData = try? container.decode(AnyCodable.self, forKey: .result) {
            result = resultData.value
        } else {
            result = nil
        }
    }
}

public struct MCPResponseError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?
}

// MARK: - Errors

public enum MCPError: Error, LocalizedError {
    case notConnected
    case disconnected
    case invalidResponse
    case transportNotSupported(String)
    case serverError(code: Int, message: String)
    case toolNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to MCP server"
        case .disconnected:
            return "Disconnected from MCP server"
        case .invalidResponse:
            return "Invalid response from MCP server"
        case .transportNotSupported(let transport):
            return "Transport not supported: \(transport)"
        case .serverError(let code, let message):
            return "MCP server error (\(code)): \(message)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        }
    }
}
