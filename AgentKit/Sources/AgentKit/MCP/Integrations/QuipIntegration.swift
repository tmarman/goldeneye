//
//  QuipIntegration.swift
//  AgentKit
//
//  Native Quip MCP integration - provides direct Quip API access as tools.
//  Enables document creation, editing, and collaboration features.
//

import Foundation

// MARK: - Quip Integration

/// Native Quip integration providing MCP-style tools for document collaboration.
///
/// Exposes common Quip operations:
/// - Create and edit documents
/// - Read document content
/// - List folders and threads
/// - Add comments
/// - Search documents
///
/// Usage:
/// ```swift
/// let quip = QuipIntegration(token: "your-access-token")
/// let tools = quip.tools
/// let result = try await quip.callTool("quip_create_document", arguments: [
///     "title": "Meeting Notes",
///     "content": "# Agenda\n- Item 1\n- Item 2"
/// ])
/// ```
public actor QuipIntegration {
    /// Quip Access Token
    private let token: String

    /// Base URL for Quip API
    private let baseURL = URL(string: "https://platform.quip.com/1")!

    /// Current user info
    private var currentUser: UserInfo?

    /// URL session for API calls
    private let session: URLSession

    public init(token: String) {
        self.token = token

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Tool Discovery

    /// All available Quip tools
    public var tools: [MCPTool] {
        [
            MCPTool(from: [
                "name": "quip_create_document",
                "description": "Create a new Quip document. Returns the document ID and URL.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Document title"],
                        "content": ["type": "string", "description": "Document content in Markdown or HTML"],
                        "format": ["type": "string", "description": "Content format: 'markdown' (default) or 'html'"],
                        "folder_id": ["type": "string", "description": "Optional: Folder ID to create document in"]
                    ],
                    "required": ["title"]
                ]
            ]),
            MCPTool(from: [
                "name": "quip_get_document",
                "description": "Get the content and metadata of a Quip document.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "thread_id": ["type": "string", "description": "Document/thread ID"]
                    ],
                    "required": ["thread_id"]
                ]
            ]),
            MCPTool(from: [
                "name": "quip_edit_document",
                "description": "Edit an existing Quip document by appending or prepending content.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "thread_id": ["type": "string", "description": "Document/thread ID to edit"],
                        "content": ["type": "string", "description": "Content to add (Markdown or HTML)"],
                        "format": ["type": "string", "description": "Content format: 'markdown' (default) or 'html'"],
                        "location": ["type": "string", "description": "Where to add: 'append' (default), 'prepend', or section ID"]
                    ],
                    "required": ["thread_id", "content"]
                ]
            ]),
            MCPTool(from: [
                "name": "quip_list_folders",
                "description": "List folders accessible to the user. Returns folder IDs and names.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "folder_id": ["type": "string", "description": "Optional: List contents of specific folder (default: user's private folder)"]
                    ],
                    "required": []
                ]
            ]),
            MCPTool(from: [
                "name": "quip_list_recent",
                "description": "List recently viewed or edited documents.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "count": ["type": "integer", "description": "Number of documents to return (default 10, max 50)"]
                    ],
                    "required": []
                ]
            ]),
            MCPTool(from: [
                "name": "quip_add_comment",
                "description": "Add a comment to a Quip document.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "thread_id": ["type": "string", "description": "Document/thread ID"],
                        "content": ["type": "string", "description": "Comment text"]
                    ],
                    "required": ["thread_id", "content"]
                ]
            ]),
            MCPTool(from: [
                "name": "quip_search",
                "description": "Search for Quip documents by title or content.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query"],
                        "count": ["type": "integer", "description": "Maximum results (default 10)"]
                    ],
                    "required": ["query"]
                ]
            ]),
            MCPTool(from: [
                "name": "quip_get_user",
                "description": "Get information about the current user or a specific user.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "user_id": ["type": "string", "description": "Optional: User ID (default: current user)"]
                    ],
                    "required": []
                ]
            ])
        ]
    }

    // MARK: - Tool Execution

    /// Call a Quip tool with the given arguments
    public func callTool(_ name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        switch name {
        case "quip_create_document":
            return try await createDocument(arguments)
        case "quip_get_document":
            return try await getDocument(arguments)
        case "quip_edit_document":
            return try await editDocument(arguments)
        case "quip_list_folders":
            return try await listFolders(arguments)
        case "quip_list_recent":
            return try await listRecent(arguments)
        case "quip_add_comment":
            return try await addComment(arguments)
        case "quip_search":
            return try await search(arguments)
        case "quip_get_user":
            return try await getUser(arguments)
        default:
            throw MCPError.toolNotFound(name)
        }
    }

    // MARK: - API Methods

    private func createDocument(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let title = args["title"] as? String else {
            return errorResult("Missing required: title")
        }

        var params: [String: Any] = ["title": title]

        if let content = args["content"] as? String {
            let format = args["format"] as? String ?? "markdown"
            if format == "html" {
                params["content"] = content
            } else {
                // Convert markdown - Quip accepts limited markdown
                params["content"] = markdownToQuipHtml(content)
            }
        }

        if let folderId = args["folder_id"] as? String {
            params["member_ids"] = [folderId]
        }

        params["type"] = "document"

        let response = try await apiCall("threads/new-thread", params: params)

        if let thread = response["thread"] as? [String: Any] {
            let id = thread["id"] as? String ?? "?"
            let link = thread["link"] as? String ?? ""
            return successResult("Created document: \(title)\nID: \(id)\nURL: \(link)")
        } else {
            return errorResult("Failed to create document")
        }
    }

    private func getDocument(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let threadId = args["thread_id"] as? String else {
            return errorResult("Missing required: thread_id")
        }

        let response = try await apiCall("threads/\(threadId)", params: nil, method: "GET")

        if let thread = response["thread"] as? [String: Any],
           let html = response["html"] as? String {
            let title = thread["title"] as? String ?? "Untitled"
            let updatedAt = thread["updated_usec"] as? Int64
            let updatedStr = updatedAt.map { formatTimestamp($0) } ?? "unknown"

            // Convert HTML to readable text (basic)
            let text = htmlToText(html)
            let preview = text.count > 1000 ? String(text.prefix(1000)) + "..." : text

            return successResult("""
            📄 \(title)
            Updated: \(updatedStr)

            \(preview)
            """)
        } else {
            return errorResult("Failed to get document")
        }
    }

    private func editDocument(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let threadId = args["thread_id"] as? String,
              let content = args["content"] as? String else {
            return errorResult("Missing required: thread_id, content")
        }

        let format = args["format"] as? String ?? "markdown"
        let location = args["location"] as? String ?? "append"

        var params: [String: Any] = ["thread_id": threadId]

        // Convert content
        if format == "html" {
            params["content"] = content
        } else {
            params["content"] = markdownToQuipHtml(content)
        }

        // Set location
        switch location {
        case "prepend":
            params["location"] = 0
        case "append":
            params["location"] = 2
        default:
            // Could be a section ID
            params["section_id"] = location
        }

        let response = try await apiCall("threads/edit-document", params: params)

        if response["thread"] != nil {
            return successResult("Document updated successfully")
        } else {
            let error = response["error_description"] as? String ?? "Unknown error"
            return errorResult("Failed to edit: \(error)")
        }
    }

    private func listFolders(_ args: [String: Any]) async throws -> MCPToolResult {
        let folderId = args["folder_id"] as? String

        let endpoint: String
        if let id = folderId {
            endpoint = "folders/\(id)"
        } else {
            // Get current user first to get their private folder
            let userResponse = try await apiCall("users/current", params: nil, method: "GET")
            guard let privateFolderId = userResponse["private_folder_id"] as? String else {
                return errorResult("Could not determine user's folder")
            }
            endpoint = "folders/\(privateFolderId)"
        }

        let response = try await apiCall(endpoint, params: nil, method: "GET")

        if let folder = response["folder"] as? [String: Any],
           let children = response["children"] as? [[String: Any]] {
            let folderName = folder["title"] as? String ?? "Folder"

            var items: [String] = []
            for child in children {
                if let threadId = child["thread_id"] as? String {
                    // It's a document
                    let title = (response["threads"] as? [String: [String: Any]])?[threadId]?["title"] as? String ?? "Untitled"
                    items.append("📄 \(title) [\(threadId)]")
                } else if let folderId = child["folder_id"] as? String {
                    // It's a folder
                    let title = (response["folders"] as? [String: [String: Any]])?[folderId]?["title"] as? String ?? "Folder"
                    items.append("📁 \(title) [\(folderId)]")
                }
            }

            return successResult("📁 \(folderName)\n\n\(items.joined(separator: "\n"))")
        } else {
            return errorResult("Failed to list folder")
        }
    }

    private func listRecent(_ args: [String: Any]) async throws -> MCPToolResult {
        let count = min(args["count"] as? Int ?? 10, 50)

        let response = try await apiCall("threads/recent", params: ["count": count], method: "GET")

        if let threads = response as? [[String: Any]] {
            let items = threads.map { thread -> String in
                let id = thread["id"] as? String ?? "?"
                let title = thread["title"] as? String ?? "Untitled"
                return "📄 \(title) [\(id)]"
            }
            return successResult("Recent documents:\n\n\(items.joined(separator: "\n"))")
        } else {
            return errorResult("Failed to list recent documents")
        }
    }

    private func addComment(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let threadId = args["thread_id"] as? String,
              let content = args["content"] as? String else {
            return errorResult("Missing required: thread_id, content")
        }

        let response = try await apiCall("messages/new", params: [
            "thread_id": threadId,
            "content": content
        ])

        if response["id"] != nil {
            return successResult("Comment added successfully")
        } else {
            return errorResult("Failed to add comment")
        }
    }

    private func search(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let query = args["query"] as? String else {
            return errorResult("Missing required: query")
        }

        let count = min(args["count"] as? Int ?? 10, 50)

        let response = try await apiCall("threads/search", params: [
            "query": query,
            "count": count
        ], method: "GET")

        if let threads = response as? [[String: Any]] {
            let items = threads.map { thread -> String in
                let id = thread["id"] as? String ?? "?"
                let title = thread["title"] as? String ?? "Untitled"
                let snippet = thread["snippet"] as? String ?? ""
                return "📄 \(title) [\(id)]\n   \(snippet)"
            }

            if items.isEmpty {
                return successResult("No documents found for: \(query)")
            }
            return successResult("Found \(items.count) documents:\n\n\(items.joined(separator: "\n\n"))")
        } else {
            return errorResult("Failed to search")
        }
    }

    private func getUser(_ args: [String: Any]) async throws -> MCPToolResult {
        let userId = args["user_id"] as? String
        let endpoint = userId.map { "users/\($0)" } ?? "users/current"

        let response = try await apiCall(endpoint, params: nil, method: "GET")

        let name = response["name"] as? String ?? "Unknown"
        let email = (response["emails"] as? [String])?.first ?? ""
        let profileUrl = response["profile_picture_url"] as? String ?? ""

        var info = ["👤 \(name)"]
        if !email.isEmpty { info.append("📧 \(email)") }
        if !profileUrl.isEmpty { info.append("🖼️ Has profile picture") }

        return successResult(info.joined(separator: "\n"))
    }

    // MARK: - HTTP Helpers

    private func apiCall(_ endpoint: String, params: [String: Any]?, method: String = "POST") async throws -> [String: Any] {
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!

        var request: URLRequest

        if method == "GET" {
            // Add params as query string for GET requests
            if let params = params {
                urlComponents.queryItems = params.map { key, value in
                    URLQueryItem(name: key, value: "\(value)")
                }
            }
            request = URLRequest(url: urlComponents.url!)
            request.httpMethod = "GET"
        } else {
            request = URLRequest(url: urlComponents.url!)
            request.httpMethod = method
            if let params = params {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                let bodyString = params.map { "\($0.key)=\(String(describing: $0.value).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
                request.httpBody = bodyString.data(using: .utf8)
            }
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw QuipError.httpError(statusCode)
        }

        // Try to parse as dictionary
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        // Try to parse as array (some endpoints return arrays)
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return ["items": array]
        }

        throw QuipError.invalidResponse
    }

    // MARK: - Helpers

    private func markdownToQuipHtml(_ markdown: String) -> String {
        // Basic markdown to HTML conversion
        var html = markdown
            .replacingOccurrences(of: "### ", with: "<h3>")
            .replacingOccurrences(of: "## ", with: "<h2>")
            .replacingOccurrences(of: "# ", with: "<h1>")

        // Bold
        let boldPattern = #"\*\*(.+?)\*\*"#
        if let regex = try? NSRegularExpression(pattern: boldPattern) {
            html = regex.stringByReplacingMatches(
                in: html,
                range: NSRange(html.startIndex..., in: html),
                withTemplate: "<b>$1</b>"
            )
        }

        // Bullet points
        html = html.replacingOccurrences(of: "\n- ", with: "\n<ul><li>")
            .replacingOccurrences(of: "\n* ", with: "\n<ul><li>")

        // Line breaks
        html = html.replacingOccurrences(of: "\n\n", with: "</p><p>")
        html = "<p>" + html + "</p>"

        return html
    }

    private func htmlToText(_ html: String) -> String {
        // Basic HTML to text conversion
        var text = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "</div>", with: "\n")
            .replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "<li>", with: "• ")

        // Strip remaining tags
        let tagPattern = #"<[^>]+>"#
        if let regex = try? NSRegularExpression(pattern: tagPattern) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }

        // Decode HTML entities
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatTimestamp(_ usec: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(usec) / 1_000_000)
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: date, relativeTo: Date())
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

extension QuipIntegration {
    struct UserInfo {
        let id: String
        let name: String
        let email: String?
    }
}

// MARK: - Errors

public enum QuipError: Error, LocalizedError {
    case missingToken
    case httpError(Int)
    case invalidResponse
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Quip token not configured"
        case .httpError(let code):
            return "Quip API HTTP error: \(code)"
        case .invalidResponse:
            return "Invalid response from Quip API"
        case .apiError(let message):
            return "Quip API error: \(message)"
        }
    }
}
