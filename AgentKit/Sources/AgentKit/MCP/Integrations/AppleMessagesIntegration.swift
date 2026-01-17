//
//  AppleMessagesIntegration.swift
//  AgentKit
//
//  Native Apple Messages integration via URL schemes.
//  Provides MCP-style tools for composing iMessages.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Apple Messages Integration

/// Native Apple Messages integration providing MCP-style tools for agent use.
///
/// Uses the `imessage://` URL scheme for composing messages.
///
/// **Security Note**: Sending iMessages programmatically requires user interaction.
/// This integration opens the Messages app with a pre-filled compose window for
/// user review and manual sending.
///
/// Usage:
/// ```swift
/// let messages = AppleMessagesIntegration()
/// let tools = messages.tools
/// let result = try await messages.callTool("messages_compose", arguments: [
///     "to": "+1234567890",
///     "body": "Hello!"
/// ])
/// ```
public actor AppleMessagesIntegration {

    public init() {}

    // MARK: - Tool Discovery

    /// All available Messages tools
    public var tools: [MCPTool] {
        [
            MCPTool(from: [
                "name": "messages_compose",
                "description": "Open Messages app with a pre-filled message for user review. Cannot send automatically due to security restrictions.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "to": ["type": "string", "description": "Recipient phone number or email address"],
                        "body": ["type": "string", "description": "Message content to pre-fill"]
                    ],
                    "required": ["to", "body"]
                ]
            ]),
            MCPTool(from: [
                "name": "messages_compose_sms",
                "description": "Open Messages app with an SMS message pre-filled. Opens the compose window for manual sending.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "to": ["type": "string", "description": "Recipient phone number"],
                        "body": ["type": "string", "description": "SMS content"]
                    ],
                    "required": ["to", "body"]
                ]
            ])
        ]
    }

    // MARK: - Tool Execution

    /// Call a Messages tool with the given arguments
    public func callTool(_ name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        switch name {
        case "messages_compose", "messages_compose_sms":
            return await composeMessage(arguments)
        default:
            throw MCPError.toolNotFound(name)
        }
    }

    // MARK: - API Methods

    private func composeMessage(_ args: [String: Any]) async -> MCPToolResult {
        guard let to = args["to"] as? String,
              let body = args["body"] as? String else {
            return errorResult("Missing required: to and body")
        }

        // Clean up the recipient (remove spaces, ensure proper format)
        let cleanedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)

        // URL encode the body
        guard let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return errorResult("Failed to encode message body")
        }

        // Construct the iMessage URL
        // Format: imessage://[recipient]?body=[message]
        let urlString = "imessage://\(cleanedTo)?body=\(encodedBody)"

        guard let url = URL(string: urlString) else {
            return errorResult("Failed to create message URL")
        }

        #if canImport(AppKit)
        // Open the URL - this will launch Messages with the compose window
        let opened = await MainActor.run {
            NSWorkspace.shared.open(url)
        }

        if opened {
            return successResult("Opened Messages to compose message to '\(cleanedTo)'. Please review and send manually.")
        } else {
            return errorResult("Failed to open Messages app")
        }
        #else
        return errorResult("Messages integration requires macOS")
        #endif
    }

    // MARK: - Helpers

    private func successResult(_ text: String) -> MCPToolResult {
        MCPToolResult(from: [
            "content": [["type": "text", "text": text]],
            "isError": false
        ])
    }

    private func errorResult(_ text: String) -> MCPToolResult {
        MCPToolResult(from: [
            "content": [["type": "text", "text": text]],
            "isError": true
        ])
    }
}
