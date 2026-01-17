//
//  AppleMailIntegration.swift
//  AgentKit
//
//  Native Apple Mail integration via AppleScript.
//  Provides MCP-style tools for composing, searching, and managing emails.
//

import Foundation

// MARK: - Apple Mail Integration

/// Native Apple Mail integration providing MCP-style tools for agent use.
///
/// Uses AppleScript to:
/// - Compose new emails
/// - Search emails by subject/sender/content
/// - Get unread email count
///
/// Note: For security, actually sending emails opens the Mail compose window
/// for user review before sending.
///
/// Usage:
/// ```swift
/// let mail = AppleMailIntegration()
/// let tools = mail.tools
/// let result = try await mail.callTool("mail_compose", arguments: [
///     "to": "user@example.com",
///     "subject": "Meeting Follow-up",
///     "body": "Thank you for attending..."
/// ])
/// ```
public actor AppleMailIntegration {
    private let bridge: AppleScriptBridge

    public init() {
        self.bridge = AppleScriptBridge()
    }

    // MARK: - Health Check

    /// Health status for Mail access
    public enum HealthStatus: Sendable {
        case healthy(String)
        case warning(String)
        case error(String)

        public var isHealthy: Bool {
            if case .healthy = self { return true }
            return false
        }

        public var message: String {
            switch self {
            case .healthy(let msg): return msg
            case .warning(let msg): return msg
            case .error(let msg): return msg
            }
        }
    }

    /// Check if Mail is accessible
    public func checkHealth() async -> HealthStatus {
        do {
            let script = """
            tell application "Mail"
                count of accounts
            end tell
            """
            let result = try await bridge.execute(script, timeout: 5)
            if let count = Int(result) {
                if count == 0 {
                    return .warning("Mail accessible but no accounts configured")
                }
                return .healthy("\(count) email accounts configured")
            }
            return .warning("Mail accessible but account count unclear")
        } catch let error as AppleScriptError {
            if error.localizedDescription.contains("not allowed") == true ||
               error.localizedDescription.contains("denied") == true {
                return .error("Mail access denied - enable in System Settings > Privacy & Security > Automation")
            }
            return .error(error.localizedDescription ?? "Unknown error")
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Tool Discovery

    /// All available Mail tools
    public var tools: [MCPTool] {
        [
            MCPTool(from: [
                "name": "mail_compose",
                "description": "Compose a new email. Opens Mail with a draft for user review before sending.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "to": ["type": "string", "description": "Recipient email address(es), comma-separated for multiple"],
                        "subject": ["type": "string", "description": "Email subject line"],
                        "body": ["type": "string", "description": "Email body content"],
                        "cc": ["type": "string", "description": "Optional: CC recipients, comma-separated"],
                        "bcc": ["type": "string", "description": "Optional: BCC recipients, comma-separated"]
                    ],
                    "required": ["to", "subject", "body"]
                ]
            ]),
            MCPTool(from: [
                "name": "mail_search",
                "description": "Search emails by subject, sender, or content.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query to match against subject, sender, or content"],
                        "mailbox": ["type": "string", "description": "Optional: Mailbox name to search in (e.g., 'INBOX', 'Sent')"],
                        "limit": ["type": "integer", "description": "Maximum results to return (default: 10)"]
                    ],
                    "required": ["query"]
                ]
            ]),
            MCPTool(from: [
                "name": "mail_get_unread_count",
                "description": "Get the count of unread emails across all mailboxes or a specific mailbox.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "mailbox": ["type": "string", "description": "Optional: Specific mailbox name (defaults to all)"]
                    ],
                    "required": []
                ]
            ]),
            MCPTool(from: [
                "name": "mail_list_mailboxes",
                "description": "List all available mailboxes/folders.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ])
        ]
    }

    // MARK: - Tool Execution

    /// Call a Mail tool with the given arguments
    public func callTool(_ name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        switch name {
        case "mail_compose":
            return try await composeEmail(arguments)
        case "mail_search":
            return try await searchEmails(arguments)
        case "mail_get_unread_count":
            return try await getUnreadCount(arguments)
        case "mail_list_mailboxes":
            return try await listMailboxes()
        default:
            throw MCPError.toolNotFound(name)
        }
    }

    // MARK: - API Methods

    private func composeEmail(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let to = args["to"] as? String,
              let subject = args["subject"] as? String,
              let body = args["body"] as? String else {
            return errorResult("Missing required: to, subject, and body")
        }

        let cc = args["cc"] as? String
        let bcc = args["bcc"] as? String

        let sanitizedTo = await bridge.sanitize(to)
        let sanitizedSubject = await bridge.sanitize(subject)
        let sanitizedBody = await bridge.sanitize(body)
        let sanitizedCC = cc != nil ? await bridge.sanitize(cc!) : nil
        let sanitizedBCC = bcc != nil ? await bridge.sanitize(bcc!) : nil

        var script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(sanitizedSubject)", content:"\(sanitizedBody)", visible:true}
            tell newMessage
                make new to recipient at end of to recipients with properties {address:"\(sanitizedTo)"}
        """

        if let cc = sanitizedCC {
            script += "\n                make new cc recipient at end of cc recipients with properties {address:\"\(cc)\"}"
        }

        if let bcc = sanitizedBCC {
            script += "\n                make new bcc recipient at end of bcc recipients with properties {address:\"\(bcc)\"}"
        }

        script += """

            end tell
            activate
        end tell
        return "success"
        """

        do {
            _ = try await bridge.execute(script, timeout: 10)
            return successResult("Opened email compose window to '\(to)' with subject '\(subject)'. Please review and send manually.")
        } catch let error as AppleScriptError {
            return errorResult("Failed to compose email: \(error.localizedDescription ?? "Unknown error")")
        } catch {
            return errorResult("Failed to compose email: \(error.localizedDescription)")
        }
    }

    private func searchEmails(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let query = args["query"] as? String else {
            return errorResult("Missing required: query")
        }

        let limit = args["limit"] as? Int ?? 10
        let mailbox = args["mailbox"] as? String
        let sanitizedQuery = await bridge.sanitize(query.lowercased())

        var script: String
        if let mailbox = mailbox {
            let sanitizedMailbox = await bridge.sanitize(mailbox)
            script = """
            tell application "Mail"
                set matchingMessages to {}
                set msgCount to 0
                try
                    set targetMailbox to mailbox "\(sanitizedMailbox)"
                    repeat with aMessage in messages of targetMailbox
                        if msgCount >= \(limit) then exit repeat
                        set msgSubject to subject of aMessage
                        set msgSender to sender of aMessage
                        if msgSubject contains "\(sanitizedQuery)" or msgSender contains "\(sanitizedQuery)" then
                            set msgDate to date received of aMessage
                            set msgRead to read status of aMessage
                            set readStatus to ""
                            if not msgRead then set readStatus to "●"
                            set end of matchingMessages to readStatus & msgDate & " | From: " & msgSender & " | " & msgSubject
                            set msgCount to msgCount + 1
                        end if
                    end repeat
                on error errMsg
                    return "ERROR: " & errMsg
                end try
                set AppleScript's text item delimiters to "\\n"
                return matchingMessages as text
            end tell
            """
        } else {
            script = """
            tell application "Mail"
                set matchingMessages to {}
                set msgCount to 0
                repeat with aMessage in messages of inbox
                    if msgCount >= \(limit) then exit repeat
                    set msgSubject to subject of aMessage
                    set msgSender to sender of aMessage
                    if msgSubject contains "\(sanitizedQuery)" or msgSender contains "\(sanitizedQuery)" then
                        set msgDate to date received of aMessage
                        set msgRead to read status of aMessage
                        set readStatus to ""
                        if not msgRead then set readStatus to "● "
                        set end of matchingMessages to readStatus & msgDate & " | From: " & msgSender & " | " & msgSubject
                        set msgCount to msgCount + 1
                    end if
                end repeat
                set AppleScript's text item delimiters to "\\n"
                return matchingMessages as text
            end tell
            """
        }

        do {
            let result = try await bridge.execute(script, timeout: 30)
            if result.isEmpty {
                return successResult("No emails found matching '\(query)'")
            }
            if result.hasPrefix("ERROR:") {
                return errorResult(result)
            }
            return successResult("Emails matching '\(query)':\n\(result)")
        } catch let error as AppleScriptError {
            return errorResult("Search failed: \(error.localizedDescription ?? "Unknown error")")
        } catch {
            return errorResult("Search failed: \(error.localizedDescription)")
        }
    }

    private func getUnreadCount(_ args: [String: Any]) async throws -> MCPToolResult {
        let mailbox = args["mailbox"] as? String

        var script: String
        if let mailbox = mailbox {
            let sanitizedMailbox = await bridge.sanitize(mailbox)
            script = """
            tell application "Mail"
                set unreadCount to 0
                try
                    set unreadCount to unread count of mailbox "\(sanitizedMailbox)"
                on error
                    return "ERROR: Mailbox not found"
                end try
                return unreadCount as string
            end tell
            """
        } else {
            script = """
            tell application "Mail"
                set totalUnread to 0
                repeat with acct in accounts
                    repeat with mbox in mailboxes of acct
                        set totalUnread to totalUnread + (unread count of mbox)
                    end repeat
                end repeat
                return totalUnread as string
            end tell
            """
        }

        do {
            let result = try await bridge.execute(script, timeout: 15)
            if result.hasPrefix("ERROR:") {
                return errorResult(result)
            }
            let location = mailbox ?? "all mailboxes"
            return successResult("Unread emails in \(location): \(result)")
        } catch let error as AppleScriptError {
            return errorResult("Failed to get unread count: \(error.localizedDescription ?? "Unknown error")")
        } catch {
            return errorResult("Failed to get unread count: \(error.localizedDescription)")
        }
    }

    private func listMailboxes() async throws -> MCPToolResult {
        let script = """
        tell application "Mail"
            set mailboxList to {}
            repeat with acct in accounts
                set acctName to name of acct
                repeat with mbox in mailboxes of acct
                    set mboxName to name of mbox
                    set unread to unread count of mbox
                    set end of mailboxList to acctName & "/" & mboxName & " (" & unread & " unread)"
                end repeat
            end repeat
            set AppleScript's text item delimiters to "\\n"
            return mailboxList as text
        end tell
        """

        do {
            let result = try await bridge.execute(script, timeout: 15)
            if result.isEmpty {
                return successResult("No mailboxes found")
            }
            return successResult("Mailboxes:\n\(result)")
        } catch let error as AppleScriptError {
            return errorResult("Failed to list mailboxes: \(error.localizedDescription ?? "Unknown error")")
        } catch {
            return errorResult("Failed to list mailboxes: \(error.localizedDescription)")
        }
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
