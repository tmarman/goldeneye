//
//  AppleNotesIntegration.swift
//  AgentKit
//
//  Native Apple Notes integration via AppleScript.
//  Provides MCP-style tools for creating, searching, and managing notes.
//

import Foundation

// MARK: - Apple Notes Integration

/// Native Apple Notes integration providing MCP-style tools for agent use.
///
/// Uses AppleScript to:
/// - Create notes with title and body
/// - Search notes by title/content
/// - Get note content by title
/// - List note folders
/// - Append content to existing notes
///
/// Usage:
/// ```swift
/// let notes = AppleNotesIntegration()
/// let tools = notes.tools
/// let result = try await notes.callTool("notes_create", arguments: [
///     "title": "Meeting Notes",
///     "body": "Discussion topics...",
///     "folder": "Work"
/// ])
/// ```
public actor AppleNotesIntegration {
    private let bridge: AppleScriptBridge

    public init() {
        self.bridge = AppleScriptBridge()
    }

    // MARK: - Health Check

    /// Health status for Notes access
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

    /// Check if Notes is accessible
    public func checkHealth() async -> HealthStatus {
        do {
            let script = """
            tell application "Notes"
                count of folders
            end tell
            """
            let result = try await bridge.execute(script, timeout: 5)
            if let count = Int(result) {
                return .healthy("\(count) folders accessible")
            }
            return .warning("Notes accessible but folder count unclear")
        } catch let error as AppleScriptError {
            if error.localizedDescription.contains("not allowed") == true ||
               error.localizedDescription.contains("denied") == true {
                return .error("Notes access denied - enable in System Settings > Privacy & Security > Automation")
            }
            return .error(error.localizedDescription ?? "Unknown error")
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Tool Discovery

    /// All available Notes tools
    public var tools: [MCPTool] {
        [
            MCPTool(from: [
                "name": "notes_create",
                "description": "Create a new Apple Note. Returns confirmation message.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Note title"],
                        "body": ["type": "string", "description": "Note content (supports basic HTML)"],
                        "folder": ["type": "string", "description": "Optional: Folder name (defaults to 'Notes')"]
                    ],
                    "required": ["title", "body"]
                ]
            ]),
            MCPTool(from: [
                "name": "notes_search",
                "description": "Search notes by title or content.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query to match against title and body"],
                        "limit": ["type": "integer", "description": "Maximum results to return (default: 10)"]
                    ],
                    "required": ["query"]
                ]
            ]),
            MCPTool(from: [
                "name": "notes_get",
                "description": "Get the content of a note by its exact title.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Exact title of the note to retrieve"]
                    ],
                    "required": ["title"]
                ]
            ]),
            MCPTool(from: [
                "name": "notes_list_folders",
                "description": "List all note folders/accounts.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ]),
            MCPTool(from: [
                "name": "notes_append",
                "description": "Append content to an existing note.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Exact title of the note to append to"],
                        "content": ["type": "string", "description": "Content to append (supports basic HTML)"]
                    ],
                    "required": ["title", "content"]
                ]
            ])
        ]
    }

    // MARK: - Tool Execution

    /// Call a Notes tool with the given arguments
    public func callTool(_ name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        switch name {
        case "notes_create":
            return try await createNote(arguments)
        case "notes_search":
            return try await searchNotes(arguments)
        case "notes_get":
            return try await getNote(arguments)
        case "notes_list_folders":
            return try await listFolders()
        case "notes_append":
            return try await appendToNote(arguments)
        default:
            throw MCPError.toolNotFound(name)
        }
    }

    // MARK: - API Methods

    private func createNote(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let title = args["title"] as? String,
              let body = args["body"] as? String else {
            return errorResult("Missing required: title and body")
        }

        let folder = args["folder"] as? String ?? "Notes"
        let sanitizedTitle = await bridge.sanitize(title)
        let sanitizedBody = await bridge.sanitize(body)
        let sanitizedFolder = await bridge.sanitize(folder)

        let script = """
        tell application "Notes"
            tell account "iCloud"
                if not (exists folder "\(sanitizedFolder)") then
                    make new folder with properties {name:"\(sanitizedFolder)"}
                end if
                tell folder "\(sanitizedFolder)"
                    make new note with properties {name:"\(sanitizedTitle)", body:"\(sanitizedBody)"}
                end tell
            end tell
        end tell
        return "success"
        """

        do {
            _ = try await bridge.execute(script, timeout: 10)
            return successResult("Created note '\(title)' in folder '\(folder)'")
        } catch let error as AppleScriptError {
            return errorResult("Failed to create note: \(error.localizedDescription ?? "Unknown error")")
        } catch {
            return errorResult("Failed to create note: \(error.localizedDescription)")
        }
    }

    private func searchNotes(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let query = args["query"] as? String else {
            return errorResult("Missing required: query")
        }

        let limit = args["limit"] as? Int ?? 10
        let sanitizedQuery = await bridge.sanitize(query.lowercased())

        let script = """
        tell application "Notes"
            set matchingNotes to {}
            set noteCount to 0
            repeat with aNote in notes
                if noteCount >= \(limit) then exit repeat
                set noteName to name of aNote
                set noteBody to body of aNote
                if noteName contains "\(sanitizedQuery)" or noteBody contains "\(sanitizedQuery)" then
                    set noteFolder to name of container of aNote
                    set end of matchingNotes to noteName & " [" & noteFolder & "]"
                    set noteCount to noteCount + 1
                end if
            end repeat
            return matchingNotes as text
        end tell
        """

        do {
            let result = try await bridge.execute(script, timeout: 30)
            if result.isEmpty {
                return successResult("No notes found matching '\(query)'")
            }
            return successResult("Found notes matching '\(query)':\n\(result)")
        } catch let error as AppleScriptError {
            return errorResult("Search failed: \(error.localizedDescription ?? "Unknown error")")
        } catch {
            return errorResult("Search failed: \(error.localizedDescription)")
        }
    }

    private func getNote(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let title = args["title"] as? String else {
            return errorResult("Missing required: title")
        }

        let sanitizedTitle = await bridge.sanitize(title)

        let script = """
        tell application "Notes"
            set matchedNote to missing value
            repeat with aNote in notes
                if name of aNote is "\(sanitizedTitle)" then
                    set matchedNote to aNote
                    exit repeat
                end if
            end repeat
            if matchedNote is missing value then
                return "NOTE_NOT_FOUND"
            else
                set noteBody to body of matchedNote
                set noteFolder to name of container of matchedNote
                set noteDate to modification date of matchedNote
                return "FOLDER:" & noteFolder & "\\nDATE:" & (noteDate as string) & "\\nBODY:" & noteBody
            end if
        end tell
        """

        do {
            let result = try await bridge.execute(script, timeout: 15)
            if result == "NOTE_NOT_FOUND" {
                return errorResult("Note '\(title)' not found")
            }
            return successResult("Note: \(title)\n\n\(result)")
        } catch let error as AppleScriptError {
            return errorResult("Failed to get note: \(error.localizedDescription ?? "Unknown error")")
        } catch {
            return errorResult("Failed to get note: \(error.localizedDescription)")
        }
    }

    private func listFolders() async throws -> MCPToolResult {
        let script = """
        tell application "Notes"
            set folderList to {}
            repeat with anAccount in accounts
                set accountName to name of anAccount
                repeat with aFolder in folders of anAccount
                    set folderName to name of aFolder
                    set noteCount to count of notes of aFolder
                    set end of folderList to accountName & "/" & folderName & " (" & noteCount & " notes)"
                end repeat
            end repeat
            set AppleScript's text item delimiters to "\\n"
            return folderList as text
        end tell
        """

        do {
            let result = try await bridge.execute(script, timeout: 15)
            if result.isEmpty {
                return successResult("No folders found")
            }
            return successResult("Note folders:\n\(result)")
        } catch let error as AppleScriptError {
            return errorResult("Failed to list folders: \(error.localizedDescription ?? "Unknown error")")
        } catch {
            return errorResult("Failed to list folders: \(error.localizedDescription)")
        }
    }

    private func appendToNote(_ args: [String: Any]) async throws -> MCPToolResult {
        guard let title = args["title"] as? String,
              let content = args["content"] as? String else {
            return errorResult("Missing required: title and content")
        }

        let sanitizedTitle = await bridge.sanitize(title)
        let sanitizedContent = await bridge.sanitize(content)

        let script = """
        tell application "Notes"
            set matchedNote to missing value
            repeat with aNote in notes
                if name of aNote is "\(sanitizedTitle)" then
                    set matchedNote to aNote
                    exit repeat
                end if
            end repeat
            if matchedNote is missing value then
                return "NOTE_NOT_FOUND"
            else
                set currentBody to body of matchedNote
                set body of matchedNote to currentBody & "<br><br>" & "\(sanitizedContent)"
                return "success"
            end if
        end tell
        """

        do {
            let result = try await bridge.execute(script, timeout: 10)
            if result == "NOTE_NOT_FOUND" {
                return errorResult("Note '\(title)' not found")
            }
            return successResult("Appended content to '\(title)'")
        } catch let error as AppleScriptError {
            return errorResult("Failed to append: \(error.localizedDescription ?? "Unknown error")")
        } catch {
            return errorResult("Failed to append: \(error.localizedDescription)")
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
