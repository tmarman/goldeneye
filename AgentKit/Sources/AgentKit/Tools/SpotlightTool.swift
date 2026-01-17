//
//  SpotlightTool.swift
//  AgentKit
//
//  MCP tool for searching macOS Spotlight index.
//  Provides fast search across all indexed content including
//  documents, mail, images with text, and more.
//

import Foundation

// MARK: - Spotlight Search Tool

/// Search macOS Spotlight for files and content
public struct SpotlightSearchTool: Tool {
    public let name = "spotlight_search"
    public let description = """
        Search your Mac using Spotlight. Finds files, documents, emails, and more.
        Spotlight indexes content from many sources including:
        - Documents (PDF, Word, Pages, etc.)
        - Mail messages
        - Images with text (via OCR)
        - Notes
        - Calendar events
        - Contacts
        Use this for fast full-text search across your local files.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "query": .init(
                    type: "string",
                    description: "Search query - can include operators like AND, OR, NOT"
                ),
                "content_type": .init(
                    type: "string",
                    description: "Filter by content type",
                    enumValues: ["any", "documents", "images", "mail", "folders", "audio", "video", "pdf", "presentations"]
                ),
                "scope": .init(
                    type: "string",
                    description: "Directory to search within (default: entire Mac)"
                ),
                "limit": .init(
                    type: "integer",
                    description: "Maximum results to return (default: 20)"
                )
            ],
            required: ["query"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let query = try input.require("query", as: String.self)
        let contentType = input.get("content_type", as: String.self) ?? "any"
        let scope = input.get("scope", as: String.self)
        let limit = input.get("limit", as: Int.self) ?? 20

        // Build mdfind command
        var args = [String]()

        // Add scope if specified
        if let scope = scope {
            args.append("-onlyin")
            args.append(scope)
        }

        // Build query with content type filter
        var searchQuery = query
        if contentType != "any" {
            if let typeFilter = contentTypeFilter(contentType) {
                searchQuery = "(\(query)) && (\(typeFilter))"
            }
        }

        args.append(searchQuery)

        do {
            let results = try await runMdfind(args: args, limit: limit)

            if results.isEmpty {
                return .success("No results found for: \"\(query)\"")
            }

            var output = "Found \(results.count) results:\n\n"

            for (i, result) in results.enumerated() {
                output += "[\(i + 1)] \(result.path)\n"
                if let displayName = result.displayName {
                    output += "    Name: \(displayName)\n"
                }
                if let contentType = result.contentType {
                    output += "    Type: \(contentType)\n"
                }
                if let modified = result.modifiedDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    output += "    Modified: \(formatter.string(from: modified))\n"
                }
                output += "\n"
            }

            return .success(output)
        } catch {
            return .error("Spotlight search failed: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let query = input.get("query", as: String.self) {
            return "Search Spotlight for: \"\(query)\""
        }
        return "Search Spotlight"
    }

    // MARK: - Private

    private func contentTypeFilter(_ type: String) -> String? {
        switch type {
        case "documents":
            return "kMDItemContentTypeTree == 'public.content'"
        case "images":
            return "kMDItemContentTypeTree == 'public.image'"
        case "mail":
            return "kMDItemContentType == 'com.apple.mail.emlx'"
        case "folders":
            return "kMDItemContentType == 'public.folder'"
        case "audio":
            return "kMDItemContentTypeTree == 'public.audio'"
        case "video":
            return "kMDItemContentTypeTree == 'public.movie'"
        case "pdf":
            return "kMDItemContentType == 'com.adobe.pdf'"
        case "presentations":
            return "kMDItemContentType == 'com.apple.keynote.key' || kMDItemContentType == 'org.openxmlformats.presentationml.presentation'"
        default:
            return nil
        }
    }

    private func runMdfind(args: [String], limit: Int) async throws -> [SpotlightResult] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        let paths = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .prefix(limit)

        // Get metadata for each result
        var results: [SpotlightResult] = []
        for path in paths {
            let metadata = try await getMetadata(for: path)
            results.append(metadata)
        }

        return results
    }

    private func getMetadata(for path: String) async throws -> SpotlightResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = [
            "-name", "kMDItemDisplayName",
            "-name", "kMDItemContentType",
            "-name", "kMDItemContentModificationDate",
            "-name", "kMDItemTextContent",
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

        // Parse the raw output (null-separated values)
        let values = output.components(separatedBy: "\0")

        var result = SpotlightResult(path: path)

        if values.count > 0 && values[0] != "(null)" {
            result.displayName = values[0]
        }
        if values.count > 1 && values[1] != "(null)" {
            result.contentType = values[1]
        }
        if values.count > 2 && values[2] != "(null)" {
            // Parse date - format varies
            let dateStr = values[2].trimmingCharacters(in: .whitespaces)
            let formatter = ISO8601DateFormatter()
            result.modifiedDate = formatter.date(from: dateStr)
        }
        if values.count > 3 && values[3] != "(null)" && !values[3].isEmpty {
            result.textContent = String(values[3].prefix(500))
        }

        return result
    }
}

// MARK: - Spotlight Result

struct SpotlightResult {
    let path: String
    var displayName: String?
    var contentType: String?
    var modifiedDate: Date?
    var textContent: String?
}

// MARK: - Spotlight File Info Tool

/// Get detailed Spotlight metadata for a file
public struct SpotlightFileTool: Tool {
    public let name = "spotlight_file_info"
    public let description = """
        Get detailed Spotlight metadata for a specific file.
        Returns all indexed attributes including:
        - Content type and kind
        - Author, title, description
        - Creation and modification dates
        - Text content (if extracted)
        - Image dimensions, EXIF data
        - Audio/video duration
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Path to the file"
                ),
                "include_content": .init(
                    type: "boolean",
                    description: "Include extracted text content (default: false)"
                )
            ],
            required: ["path"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let path = try input.require("path", as: String.self)
        let includeContent = input.get("include_content", as: Bool.self) ?? false

        // Check file exists
        guard FileManager.default.fileExists(atPath: path) else {
            return .error("File not found: \(path)")
        }

        do {
            let metadata = try await getAllMetadata(for: path, includeContent: includeContent)
            return .success(metadata)
        } catch {
            return .error("Failed to get metadata: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let path = input.get("path", as: String.self) {
            let name = (path as NSString).lastPathComponent
            return "Get Spotlight info for: \(name)"
        }
        return "Get Spotlight file info"
    }

    private func getAllMetadata(for path: String, includeContent: Bool) async throws -> String {
        var args = [String]()

        if !includeContent {
            // Exclude text content for brevity
            args.append("-name")
            args.append("kMDItemTextContent")
            args.append("-nullMarker")
            args.append("[excluded]")
        }

        args.append(path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw SpotlightError.invalidOutput
        }

        return output
    }
}

// MARK: - Errors

public enum SpotlightError: Error, LocalizedError {
    case searchFailed(String)
    case invalidOutput
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .searchFailed(let msg):
            return "Spotlight search failed: \(msg)"
        case .invalidOutput:
            return "Invalid output from Spotlight"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}
