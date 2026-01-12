import Foundation

/// Tool for making precise edits to files using search-and-replace
public struct EditTool: Tool {
    public let name = "Edit"
    public let description = "Performs exact string replacements in files. Requires the old_string to be unique in the file."

    public let inputSchema = ToolSchema(
        properties: [
            "file_path": .init(type: "string", description: "Absolute path to the file to modify"),
            "old_string": .init(type: "string", description: "The exact text to find and replace"),
            "new_string": .init(type: "string", description: "The text to replace it with"),
            "replace_all": .init(type: "boolean", description: "Replace all occurrences (default: false, replaces first only)"),
        ],
        required: ["file_path", "old_string", "new_string"]
    )

    public let requiresApproval = true
    public let riskLevel = RiskLevel.medium

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let filePath = try input.require("file_path", as: String.self)
        let oldString = try input.require("old_string", as: String.self)
        let newString = try input.require("new_string", as: String.self)
        let replaceAll = input.get("replace_all", as: Bool.self) ?? false

        let url = URL(fileURLWithPath: filePath)

        // Check file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            return .error("File not found: \(filePath)")
        }

        do {
            // Read current content
            var content = try String(contentsOf: url, encoding: .utf8)

            // Check if old_string exists
            guard content.contains(oldString) else {
                return .error("The specified old_string was not found in the file")
            }

            // Count occurrences
            let occurrences = content.components(separatedBy: oldString).count - 1

            // If not replace_all and multiple occurrences, fail
            if !replaceAll && occurrences > 1 {
                return .error("old_string appears \(occurrences) times. Use replace_all=true or provide more context to make it unique.")
            }

            // Perform replacement
            if replaceAll {
                content = content.replacingOccurrences(of: oldString, to: newString)
            } else {
                // Replace first occurrence only
                if let range = content.range(of: oldString) {
                    content = content.replacingCharacters(in: range, with: newString)
                }
            }

            // Write back
            try content.write(to: url, atomically: true, encoding: .utf8)

            let replacementCount = replaceAll ? occurrences : 1
            return .success("Replaced \(replacementCount) occurrence(s) in \(filePath)")
        } catch {
            return .error("Failed to edit file: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        let path = input.get("file_path", as: String.self) ?? "unknown"
        let replaceAll = input.get("replace_all", as: Bool.self) ?? false
        return replaceAll ? "Replace all occurrences in: \(path)" : "Edit file: \(path)"
    }
}

// MARK: - String Extension

private extension String {
    func replacingOccurrences(of target: String, to replacement: String) -> String {
        self.replacingOccurrences(of: target, with: replacement)
    }
}
