//
//  MailSearchTool.swift
//  AgentKit
//
//  MCP tool for searching and reading Mail.app content.
//  Uses Spotlight for search and AppleScript for reading.
//

import Foundation

// MARK: - Mail Search Tool

/// Search Mail.app using Spotlight
public struct MailSearchTool: Tool {
    public let name = "mail_search"
    public let description = """
        Search your Mail.app emails using Spotlight.
        Finds emails by subject, sender, recipient, or content.
        Returns message metadata and can retrieve full content.
        Note: Uses Spotlight index - recently received emails may take
        a moment to be indexed.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "query": .init(
                    type: "string",
                    description: "Search query - can include sender:, from:, to:, subject: prefixes"
                ),
                "mailbox": .init(
                    type: "string",
                    description: "Limit to specific mailbox (Inbox, Sent, etc.)"
                ),
                "limit": .init(
                    type: "integer",
                    description: "Maximum results (default: 10)"
                ),
                "days_back": .init(
                    type: "integer",
                    description: "Only search emails from last N days"
                )
            ],
            required: ["query"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let query = try input.require("query", as: String.self)
        let mailbox = input.get("mailbox", as: String.self)
        let limit = input.get("limit", as: Int.self) ?? 10
        let daysBack = input.get("days_back", as: Int.self)

        do {
            let results = try await searchMail(
                query: query,
                mailbox: mailbox,
                limit: limit,
                daysBack: daysBack
            )
            return .success(results)
        } catch {
            return .error("Mail search failed: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let query = input.get("query", as: String.self) {
            return "Search mail for: \"\(query)\""
        }
        return "Search mail"
    }

    // MARK: - Search Implementation

    private func searchMail(
        query: String,
        mailbox: String?,
        limit: Int,
        daysBack: Int?
    ) async throws -> String {
        // Build mdfind query for mail
        var searchQuery = "(kMDItemContentType == 'com.apple.mail.emlx')"

        // Add text search
        let escapedQuery = query.replacingOccurrences(of: "\"", with: "\\\"")
        searchQuery += " && (kMDItemTextContent == \"*\(escapedQuery)*\"cdw"
        searchQuery += " || kMDItemSubject == \"*\(escapedQuery)*\"cdw"
        searchQuery += " || kMDItemAuthors == \"*\(escapedQuery)*\"cdw"
        searchQuery += " || kMDItemRecipients == \"*\(escapedQuery)*\"cdw)"

        // Add date filter if specified
        if let days = daysBack {
            let calendar = Calendar.current
            if let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                let dateStr = formatter.string(from: cutoffDate)
                searchQuery += " && (kMDItemContentCreationDate >= $time.iso(\(dateStr)))"
            }
        }

        // Run mdfind
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")

        var args = [searchQuery]

        // Limit to Mail folder if no specific mailbox
        if mailbox == nil {
            let mailPath = (NSHomeDirectory() as NSString)
                .appendingPathComponent("Library/Mail")
            args.insert(contentsOf: ["-onlyin", mailPath], at: 0)
        }

        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return "No results found"
        }

        let paths = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .prefix(limit)

        if paths.isEmpty {
            return "No emails found matching: \"\(query)\""
        }

        // Get metadata for each result
        var results: [String] = []
        results.append("Found \(paths.count) emails matching: \"\(query)\"\n")

        for (index, path) in paths.enumerated() {
            let metadata = try await getMailMetadata(path: path)
            results.append("[\(index + 1)] \(metadata)")
        }

        return results.joined(separator: "\n")
    }

    private func getMailMetadata(path: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = [
            "-name", "kMDItemSubject",
            "-name", "kMDItemAuthors",
            "-name", "kMDItemRecipients",
            "-name", "kMDItemContentCreationDate",
            "-raw",
            path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Parse raw output (null-separated)
        let values = output.components(separatedBy: "\0")

        var subject = "No Subject"
        var from = "Unknown"
        var to = ""
        var date = ""

        if values.count > 0 && values[0] != "(null)" {
            subject = values[0]
        }
        if values.count > 1 && values[1] != "(null)" {
            from = values[1]
        }
        if values.count > 2 && values[2] != "(null)" {
            to = values[2]
        }
        if values.count > 3 && values[3] != "(null)" {
            date = values[3]
        }

        var result = subject
        result += "\n    From: \(from)"
        if !to.isEmpty {
            result += "\n    To: \(to)"
        }
        if !date.isEmpty {
            result += "\n    Date: \(date)"
        }
        result += "\n    Path: \(path)\n"

        return result
    }
}

// MARK: - Mail Read Tool

/// Read specific email content using Spotlight
public struct MailReadTool: Tool {
    public let name = "mail_read"
    public let description = """
        Read the content of a specific email.
        Takes a path to an .emlx file (from mail_search results).
        Returns the full message content including headers.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Path to the .emlx file"
                ),
                "include_headers": .init(
                    type: "boolean",
                    description: "Include email headers (default: true)"
                ),
                "max_length": .init(
                    type: "integer",
                    description: "Maximum content length (default: 10000)"
                )
            ],
            required: ["path"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let path = try input.require("path", as: String.self)
        let includeHeaders = input.get("include_headers", as: Bool.self) ?? true
        let maxLength = input.get("max_length", as: Int.self) ?? 10000

        guard FileManager.default.fileExists(atPath: path) else {
            return .error("File not found: \(path)")
        }

        guard path.hasSuffix(".emlx") else {
            return .error("Not a mail file. Expected .emlx extension.")
        }

        do {
            let content = try readEmlx(at: path, includeHeaders: includeHeaders, maxLength: maxLength)
            return .success(content)
        } catch {
            return .error("Failed to read email: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let path = input.get("path", as: String.self) {
            let name = (path as NSString).lastPathComponent
            return "Read email: \(name)"
        }
        return "Read email"
    }

    private func readEmlx(at path: String, includeHeaders: Bool, maxLength: Int) throws -> String {
        // .emlx files have a specific format:
        // - First line: message length in bytes
        // - Then the raw RFC 822 message
        // - Followed by Apple's plist metadata

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let content = String(data: data, encoding: .utf8) else {
            throw MailError.encodingError
        }

        let lines = content.components(separatedBy: "\n")

        guard lines.count > 1 else {
            throw MailError.invalidFormat
        }

        // First line is the byte count - skip it
        let messageLines = Array(lines.dropFirst())

        // Find where the message ends (plist starts with <?xml)
        var endIndex = messageLines.count
        for (index, line) in messageLines.enumerated() {
            if line.hasPrefix("<?xml") {
                endIndex = index
                break
            }
        }

        let message = messageLines[0..<endIndex].joined(separator: "\n")

        // Parse headers and body
        var output = ""
        let parts = message.components(separatedBy: "\n\n")

        if includeHeaders && parts.count > 0 {
            output += "=== Headers ===\n"
            // Only include important headers
            let headers = parts[0]
            for line in headers.components(separatedBy: "\n") {
                let lowerLine = line.lowercased()
                if lowerLine.hasPrefix("from:") ||
                   lowerLine.hasPrefix("to:") ||
                   lowerLine.hasPrefix("subject:") ||
                   lowerLine.hasPrefix("date:") ||
                   lowerLine.hasPrefix("cc:") {
                    output += line + "\n"
                }
            }
            output += "\n"
        }

        output += "=== Body ===\n"
        if parts.count > 1 {
            let body = parts[1...].joined(separator: "\n\n")

            // Strip HTML if present
            if body.contains("<html") || body.contains("<HTML") {
                output += stripHTMLTags(body)
            } else {
                output += body
            }
        }

        // Truncate if needed
        if output.count > maxLength {
            return String(output.prefix(maxLength)) + "\n\n[... truncated ...]"
        }

        return output
    }

    private func stripHTMLTags(_ html: String) -> String {
        // Simple HTML tag stripper
        let tagPattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else {
            return html
        }

        let range = NSRange(html.startIndex..., in: html)
        var stripped = regex.stringByReplacingMatches(in: html, range: range, withTemplate: " ")

        // Decode common entities
        stripped = stripped.replacingOccurrences(of: "&nbsp;", with: " ")
        stripped = stripped.replacingOccurrences(of: "&amp;", with: "&")
        stripped = stripped.replacingOccurrences(of: "&lt;", with: "<")
        stripped = stripped.replacingOccurrences(of: "&gt;", with: ">")
        stripped = stripped.replacingOccurrences(of: "&quot;", with: "\"")

        // Clean up whitespace
        let lines = stripped.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        return lines.joined(separator: " ")
    }
}

// MARK: - Mail Stats Tool

/// Get mail statistics using Spotlight
public struct MailStatsTool: Tool {
    public let name = "mail_stats"
    public let description = """
        Get statistics about your mail using Spotlight.
        Shows total indexed messages, recent message count, and top senders.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "days": .init(
                    type: "integer",
                    description: "Analyze messages from last N days (default: 7)"
                )
            ],
            required: []
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let days = input.get("days", as: Int.self) ?? 7

        do {
            let stats = try await getMailStats(days: days)
            return .success(stats)
        } catch {
            return .error("Failed to get mail stats: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        let days = input.get("days", as: Int.self) ?? 7
        return "Get mail stats for last \(days) days"
    }

    private func getMailStats(days: Int) async throws -> String {
        let mailPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Mail")

        // Count total indexed mail
        let totalCount = try await countMail(query: "kMDItemContentType == 'com.apple.mail.emlx'", onlyIn: mailPath)

        // Count recent mail
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date())!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dateStr = formatter.string(from: cutoff)

        let recentQuery = "kMDItemContentType == 'com.apple.mail.emlx' && kMDItemContentCreationDate >= $time.iso(\(dateStr))"
        let recentCount = try await countMail(query: recentQuery, onlyIn: mailPath)

        var output = "=== Mail Statistics ===\n\n"
        output += "Total indexed messages: \(totalCount)\n"
        output += "Messages in last \(days) days: \(recentCount)\n"
        output += "\n"

        // Get recent senders
        output += "=== Recent Activity ===\n"
        output += "Messages per day (last \(days) days): \(recentCount / max(days, 1))\n"

        return output
    }

    private func countMail(query: String, onlyIn path: String) async throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", path, "-count", query]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"

        return Int(output) ?? 0
    }
}

// MARK: - Errors

public enum MailError: Error, LocalizedError {
    case encodingError
    case invalidFormat
    case searchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Could not decode email content"
        case .invalidFormat:
            return "Invalid email file format"
        case .searchFailed(let reason):
            return "Search failed: \(reason)"
        }
    }
}
