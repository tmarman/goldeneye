//
//  SlackIntegration.swift
//  AgentKit
//
//  Native Slack MCP integration - provides direct Slack API access as tools.
//  No external npm packages required - pure Swift implementation.
//

import Foundation

// MARK: - Slack Integration

/// Native Slack integration providing MCP-style tools for agent use.
///
/// Supports both bot tokens (xoxb-) and user tokens (xoxp-) for comprehensive access:
/// - Bot tokens: Post as bot, react to messages, channel operations
/// - User tokens: Search DMs, access private conversations, post as user
///
/// Exposes common Slack operations:
/// - Send messages to channels or DMs
/// - List channels
/// - Read channel history
/// - React to messages
/// - Search messages
///
/// Usage:
/// ```swift
/// let slack = SlackIntegration(botToken: "xoxb-...", userToken: "xoxp-...")
/// let tools = slack.tools
/// let result = try await slack.callTool("slack_send_message", arguments: [
///     "channel": "C1234567890",
///     "text": "Hello from AgentKit!"
/// ])
/// ```
public actor SlackIntegration {
    /// Slack Bot Token (xoxb-...) for bot operations
    private let botToken: String?

    /// Slack User Token (xoxp-...) for user-scoped operations
    private let userToken: String?

    /// Base URL for Slack API
    private let baseURL = URL(string: "https://slack.com/api")!

    /// Workspace info (loaded on first use)
    private var workspaceInfo: WorkspaceInfo?

    /// URL session for API calls
    private let session: URLSession

    /// Token type for API method routing
    public enum TokenType {
        case bot
        case user
        case preferUser  // Use user token if available, fall back to bot
        case preferBot   // Use bot token if available, fall back to user
    }

    /// Initialize with both token types (either or both can be provided)
    public init(botToken: String? = nil, userToken: String? = nil) {
        self.botToken = botToken?.isEmpty == true ? nil : botToken
        self.userToken = userToken?.isEmpty == true ? nil : userToken

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    /// Legacy initializer for backwards compatibility
    public init(token: String) {
        // Auto-detect token type based on prefix
        if token.hasPrefix("xoxp-") {
            self.userToken = token
            self.botToken = nil
        } else {
            self.botToken = token
            self.userToken = nil
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    /// Check if any token is configured
    public var isConfigured: Bool {
        botToken != nil || userToken != nil
    }

    /// Check which tokens are available
    public var tokenStatus: (hasBot: Bool, hasUser: Bool) {
        (botToken != nil, userToken != nil)
    }

    /// Select the appropriate token for an API method
    private func selectToken(for method: String, preference: TokenType = .preferBot) -> String? {
        // Methods that require or work better with user tokens
        let userPreferredMethods = [
            "search.messages",      // Search includes user's DMs
            "search.files",         // File search across all accessible content
            "users.profile.set",    // Modify user's own profile
            "stars.add",            // Star items as the user
            "stars.remove",
            "stars.list",
            "reminders.add",        // Create reminders for the user
            "reminders.complete",
            "reminders.delete",
            "reminders.list"
        ]

        // Methods that should use bot token (appear as bot)
        let botPreferredMethods = [
            "chat.postMessage",     // Post as bot (unless explicitly as user)
            "reactions.add",        // React as bot
            "reactions.remove"
        ]

        // Determine preference based on method
        let effectivePreference: TokenType
        if userPreferredMethods.contains(method) {
            effectivePreference = .preferUser
        } else if botPreferredMethods.contains(method) {
            effectivePreference = .preferBot
        } else {
            effectivePreference = preference
        }

        // Select token based on preference and availability
        switch effectivePreference {
        case .bot:
            return botToken
        case .user:
            return userToken
        case .preferUser:
            return userToken ?? botToken
        case .preferBot:
            return botToken ?? userToken
        }
    }

    // MARK: - Tool Discovery

    /// All available Slack tools
    public var tools: [MCPTool] {
        [
            MCPTool(from: [
                "name": "slack_send_message",
                "description": "Send a message to a Slack channel or DM. Returns the message timestamp (ts) for threading.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "channel": ["type": "string", "description": "Channel ID (C...) or user ID (U...) for DM"],
                        "text": ["type": "string", "description": "Message text (supports Slack markdown)"],
                        "thread_ts": ["type": "string", "description": "Optional: Reply in thread to this message timestamp"],
                        "unfurl_links": ["type": "boolean", "description": "Whether to unfurl links in the message"],
                        "as_user": ["type": "boolean", "description": "If true, post as the authenticated user (requires user token)"]
                    ],
                    "required": ["channel", "text"]
                ]
            ]),
            MCPTool(from: [
                "name": "slack_list_channels",
                "description": "List Slack channels the bot has access to. Returns channel IDs and names.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "types": ["type": "string", "description": "Comma-separated types: public_channel, private_channel, mpim, im"],
                        "limit": ["type": "integer", "description": "Maximum channels to return (default 100)"]
                    ],
                    "required": []
                ]
            ]),
            MCPTool(from: [
                "name": "slack_channel_history",
                "description": "Read recent messages from a Slack channel. Returns up to the specified limit.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "channel": ["type": "string", "description": "Channel ID to read history from"],
                        "limit": ["type": "integer", "description": "Number of messages to return (default 10, max 100)"]
                    ],
                    "required": ["channel"]
                ]
            ]),
            MCPTool(from: [
                "name": "slack_add_reaction",
                "description": "Add an emoji reaction to a message.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "channel": ["type": "string", "description": "Channel ID where the message is"],
                        "timestamp": ["type": "string", "description": "Message timestamp to react to"],
                        "emoji": ["type": "string", "description": "Emoji name without colons (e.g., 'thumbsup')"]
                    ],
                    "required": ["channel", "timestamp", "emoji"]
                ]
            ]),
            MCPTool(from: [
                "name": "slack_search_messages",
                "description": "Search for messages in Slack. Returns matching messages with context.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query (supports Slack search syntax)"],
                        "count": ["type": "integer", "description": "Number of results (default 10, max 100)"]
                    ],
                    "required": ["query"]
                ]
            ]),
            MCPTool(from: [
                "name": "slack_get_user_info",
                "description": "Get information about a Slack user by ID.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "user": ["type": "string", "description": "User ID (U...)"]
                    ],
                    "required": ["user"]
                ]
            ])
        ]
    }

    // MARK: - Tool Execution

    /// Call a Slack tool with the given arguments
    public func callTool(_ name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        switch name {
        case "slack_send_message":
            return try await sendMessage(arguments)
        case "slack_list_channels":
            return try await listChannels(arguments)
        case "slack_channel_history":
            return try await channelHistory(arguments)
        case "slack_add_reaction":
            return try await addReaction(arguments)
        case "slack_search_messages":
            return try await searchMessages(arguments)
        case "slack_get_user_info":
            return try await getUserInfo(arguments)
        default:
            throw MCPError.toolNotFound(name)
        }
    }

    // MARK: - API Methods

    private func sendMessage(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let channel = args["channel"] as? String,
              let text = args["text"] as? String else {
            return errorResult("Missing required: channel and text")
        }

        let asUser = args["as_user"] as? Bool ?? false

        var params: [String: Any] = [
            "channel": channel,
            "text": text
        ]

        if let threadTs = args["thread_ts"] as? String {
            params["thread_ts"] = threadTs
        }
        if let unfurl = args["unfurl_links"] as? Bool {
            params["unfurl_links"] = unfurl
        }

        // Use user token if posting as user, otherwise prefer bot token
        let tokenPreference: TokenType = asUser ? .preferUser : .preferBot
        let response = try await apiCall("chat.postMessage", params: params, tokenPreference: tokenPreference)

        if let ok = response["ok"] as? Bool, ok {
            let ts = response["ts"] as? String ?? "unknown"
            let channelId = response["channel"] as? String ?? channel
            let poster = asUser ? "as user" : "as bot"
            return successResult("Message sent to \(channelId) \(poster) (ts: \(ts))")
        } else {
            let error = response["error"] as? String ?? "Unknown error"
            return errorResult("Failed to send message: \(error)")
        }
    }

    private func listChannels(_ args: [String: Any]) async throws -> MCPToolResult {
        var params: [String: Any] = [
            "limit": args["limit"] as? Int ?? 100,
            "exclude_archived": true
        ]

        if let types = args["types"] as? String {
            params["types"] = types
        }

        let response = try await apiCall("conversations.list", params: params)

        if let ok = response["ok"] as? Bool, ok,
           let channels = response["channels"] as? [[String: Any]] {
            let channelList = channels.map { channel -> String in
                let id = channel["id"] as? String ?? "?"
                let name = channel["name"] as? String ?? "?"
                let isPrivate = channel["is_private"] as? Bool ?? false
                let memberCount = channel["num_members"] as? Int
                let members = memberCount.map { " (\($0) members)" } ?? ""
                return "\(isPrivate ? "🔒" : "#")\(name) [\(id)]\(members)"
            }
            return successResult("Found \(channels.count) channels:\n\(channelList.joined(separator: "\n"))")
        } else {
            let error = response["error"] as? String ?? "Unknown error"
            return errorResult("Failed to list channels: \(error)")
        }
    }

    private func channelHistory(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let channel = args["channel"] as? String else {
            return errorResult("Missing required: channel")
        }

        let limit = min(args["limit"] as? Int ?? 10, 100)

        let response = try await apiCall("conversations.history", params: [
            "channel": channel,
            "limit": limit
        ])

        if let ok = response["ok"] as? Bool, ok,
           let messages = response["messages"] as? [[String: Any]] {
            let formattedMessages = messages.map { msg -> String in
                let user = msg["user"] as? String ?? "bot"
                let text = msg["text"] as? String ?? ""
                let ts = msg["ts"] as? String ?? ""
                let truncatedText = text.count > 200 ? String(text.prefix(200)) + "..." : text
                return "[\(ts)] <\(user)>: \(truncatedText)"
            }
            return successResult("Last \(messages.count) messages:\n\(formattedMessages.joined(separator: "\n\n"))")
        } else {
            let error = response["error"] as? String ?? "Unknown error"
            return errorResult("Failed to get history: \(error)")
        }
    }

    private func addReaction(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let channel = args["channel"] as? String,
              let timestamp = args["timestamp"] as? String,
              let emoji = args["emoji"] as? String else {
            return errorResult("Missing required: channel, timestamp, emoji")
        }

        let response = try await apiCall("reactions.add", params: [
            "channel": channel,
            "timestamp": timestamp,
            "name": emoji
        ])

        if let ok = response["ok"] as? Bool, ok {
            return successResult("Added :\(emoji): reaction")
        } else {
            let error = response["error"] as? String ?? "Unknown error"
            return errorResult("Failed to add reaction: \(error)")
        }
    }

    private func searchMessages(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let query = args["query"] as? String else {
            return errorResult("Missing required: query")
        }

        let count = min(args["count"] as? Int ?? 10, 100)

        let response = try await apiCall("search.messages", params: [
            "query": query,
            "count": count,
            "sort": "timestamp",
            "sort_dir": "desc"
        ])

        if let ok = response["ok"] as? Bool, ok,
           let messages = response["messages"] as? [String: Any],
           let matches = messages["matches"] as? [[String: Any]] {
            let formattedMatches = matches.map { match -> String in
                let text = match["text"] as? String ?? ""
                let channel = (match["channel"] as? [String: Any])?["name"] as? String ?? "?"
                let user = match["user"] as? String ?? "?"
                let truncatedText = text.count > 150 ? String(text.prefix(150)) + "..." : text
                return "#\(channel) <\(user)>: \(truncatedText)"
            }
            return successResult("Found \(matches.count) matches:\n\(formattedMatches.joined(separator: "\n\n"))")
        } else {
            let error = response["error"] as? String ?? "Unknown error"
            return errorResult("Failed to search: \(error)")
        }
    }

    private func getUserInfo(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let user = args["user"] as? String else {
            return errorResult("Missing required: user")
        }

        let response = try await apiCall("users.info", params: ["user": user])

        if let ok = response["ok"] as? Bool, ok,
           let userInfo = response["user"] as? [String: Any] {
            let name = userInfo["real_name"] as? String ?? "?"
            let displayName = (userInfo["profile"] as? [String: Any])?["display_name"] as? String ?? ""
            let title = (userInfo["profile"] as? [String: Any])?["title"] as? String ?? ""
            let email = (userInfo["profile"] as? [String: Any])?["email"] as? String ?? ""
            let isBot = userInfo["is_bot"] as? Bool ?? false
            let isAdmin = userInfo["is_admin"] as? Bool ?? false

            var info = ["Name: \(name)"]
            if !displayName.isEmpty { info.append("Display: @\(displayName)") }
            if !title.isEmpty { info.append("Title: \(title)") }
            if !email.isEmpty { info.append("Email: \(email)") }
            if isBot { info.append("🤖 Bot account") }
            if isAdmin { info.append("👑 Admin") }

            return successResult(info.joined(separator: "\n"))
        } else {
            let error = response["error"] as? String ?? "Unknown error"
            return errorResult("Failed to get user info: \(error)")
        }
    }

    // MARK: - Raw API Access (for indexers)

    /// Direct API access for internal use (e.g., SlackIndexer)
    /// Returns JSON-encoded Data to avoid Sendable issues across actor boundaries
    public func rawAPI(_ method: String, params: [String: Any]) async throws -> Data {
        let result = try await apiCall(method, params: params)
        return try JSONSerialization.data(withJSONObject: result)
    }

    /// Convenience for when caller handles JSON themselves
    public func rawAPIDict(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        return try await apiCall(method, params: params)
    }

    // MARK: - HTTP Helpers

    private func apiCall(_ method: String, params: [String: Any], tokenPreference: TokenType = .preferBot) async throws -> [String: Any] {
        guard let token = selectToken(for: method, preference: tokenPreference) else {
            throw SlackError.missingToken
        }

        let url = baseURL.appendingPathComponent(method)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SlackError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SlackError.invalidResponse
        }

        return json
    }

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

// MARK: - Supporting Types

extension SlackIntegration {
    struct WorkspaceInfo {
        let teamId: String
        let teamName: String
    }
}

// MARK: - Errors

public enum SlackError: Error, LocalizedError {
    case missingToken
    case httpError(Int)
    case invalidResponse
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Slack token not configured"
        case .httpError(let code):
            return "Slack API HTTP error: \(code)"
        case .invalidResponse:
            return "Invalid response from Slack API"
        case .apiError(let message):
            return "Slack API error: \(message)"
        }
    }
}
