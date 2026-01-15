//
//  NativeIntegrationManager.swift
//  AgentKit
//
//  Manages native MCP-style integrations (Slack, Quip, etc.)
//  Provides unified tool discovery and execution across all integrations.
//

import Foundation

// MARK: - Native Integration Manager

/// Manages native (non-MCP) integrations that provide tools for agents.
///
/// This manager acts as a bridge between native Swift integrations (Slack, Quip, etc.)
/// and the agent tool system. It aggregates tools from all enabled integrations and
/// provides a unified interface for tool discovery and execution.
///
/// Usage:
/// ```swift
/// let manager = NativeIntegrationManager()
///
/// // Configure integrations
/// await manager.configureSlack(token: "xoxb-your-token")
/// await manager.configureQuip(token: "your-quip-token")
///
/// // Get all tools (for passing to LLM)
/// let tools = await manager.allTools()
///
/// // Execute a tool call
/// let result = try await manager.callTool("slack_send_message", arguments: [
///     "channel": "C1234567890",
///     "text": "Hello!"
/// ])
/// ```
public actor NativeIntegrationManager {
    // MARK: - Integrations

    private var slackIntegration: SlackIntegration?
    private var quipIntegration: QuipIntegration?

    // MARK: - State

    public struct IntegrationStatus: Sendable {
        public let name: String
        public let isConfigured: Bool
        public let toolCount: Int
    }

    public init() {}

    // MARK: - Configuration

    /// Configure Slack integration with a bot token
    public func configureSlack(token: String) {
        guard !token.isEmpty else {
            slackIntegration = nil
            return
        }
        slackIntegration = SlackIntegration(token: token)
    }

    /// Configure Quip integration with an access token
    public func configureQuip(token: String) {
        guard !token.isEmpty else {
            quipIntegration = nil
            return
        }
        quipIntegration = QuipIntegration(token: token)
    }

    /// Check if Slack is configured
    public var hasSlack: Bool {
        slackIntegration != nil
    }

    /// Check if Quip is configured
    public var hasQuip: Bool {
        quipIntegration != nil
    }

    // MARK: - Status

    /// Get status of all integrations
    public func status() async -> [IntegrationStatus] {
        var statuses: [IntegrationStatus] = []

        if let slack = slackIntegration {
            let tools = await slack.tools
            statuses.append(IntegrationStatus(
                name: "Slack",
                isConfigured: true,
                toolCount: tools.count
            ))
        } else {
            statuses.append(IntegrationStatus(
                name: "Slack",
                isConfigured: false,
                toolCount: 0
            ))
        }

        if let quip = quipIntegration {
            let tools = await quip.tools
            statuses.append(IntegrationStatus(
                name: "Quip",
                isConfigured: true,
                toolCount: tools.count
            ))
        } else {
            statuses.append(IntegrationStatus(
                name: "Quip",
                isConfigured: false,
                toolCount: 0
            ))
        }

        return statuses
    }

    // MARK: - Tool Discovery

    /// Get all tools from all configured integrations
    public func allTools() async -> [MCPTool] {
        var tools: [MCPTool] = []

        if let slack = slackIntegration {
            tools.append(contentsOf: await slack.tools)
        }

        if let quip = quipIntegration {
            tools.append(contentsOf: await quip.tools)
        }

        return tools
    }

    /// Get tools wrapped as AgentKit Tool protocol
    public func toolWrappers() async -> [any Tool] {
        let mcpTools = await allTools()
        return mcpTools.map { NativeToolWrapper(mcpTool: $0, manager: self) }
    }

    // MARK: - Tool Execution

    /// Call a tool by name with arguments
    public func callTool(_ name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        // Serialize arguments to JSON data to safely cross actor boundaries
        let argsData = try JSONSerialization.data(withJSONObject: arguments)

        // Route to appropriate integration based on tool name prefix
        if name.hasPrefix("slack_") {
            guard let slack = slackIntegration else {
                throw NativeIntegrationError.integrationNotConfigured("Slack")
            }
            // Deserialize on the other side of the actor boundary
            let safeArgs = try JSONSerialization.jsonObject(with: argsData) as? [String: Any] ?? [:]
            return try await slack.callTool(name, arguments: safeArgs)
        }

        if name.hasPrefix("quip_") {
            guard let quip = quipIntegration else {
                throw NativeIntegrationError.integrationNotConfigured("Quip")
            }
            let safeArgs = try JSONSerialization.jsonObject(with: argsData) as? [String: Any] ?? [:]
            return try await quip.callTool(name, arguments: safeArgs)
        }

        throw NativeIntegrationError.unknownTool(name)
    }
}

// MARK: - Tool Wrapper

/// Wraps a native integration tool as an AgentKit Tool
public struct NativeToolWrapper: Tool {
    public let mcpTool: MCPTool
    private let manager: NativeIntegrationManager

    public var name: String { mcpTool.name }
    public var description: String { mcpTool.description ?? "Native integration tool" }

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

    init(mcpTool: MCPTool, manager: NativeIntegrationManager) {
        self.mcpTool = mcpTool
        self.manager = manager
    }

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        var arguments: [String: Any] = [:]
        for (key, value) in input.parameters {
            arguments[key] = value.value
        }

        do {
            let result = try await manager.callTool(mcpTool.name, arguments: arguments)
            if result.isError {
                return .error(result.text ?? "Tool error")
            }
            return .success(result.text ?? "")
        } catch {
            return .error("Integration error: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        "Call '\(mcpTool.name)' integration"
    }
}

// MARK: - Errors

public enum NativeIntegrationError: Error, LocalizedError {
    case integrationNotConfigured(String)
    case unknownTool(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .integrationNotConfigured(let name):
            return "\(name) integration not configured"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .executionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}

// MARK: - ToolRegistry Extension

extension ToolRegistry {
    /// Add native integration tools
    public func addNativeIntegrations(from manager: NativeIntegrationManager) async {
        let tools = await manager.toolWrappers()
        register(tools)
    }
}
