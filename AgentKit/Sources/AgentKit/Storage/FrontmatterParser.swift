import Foundation

// MARK: - Frontmatter Parser

/// Parses YAML frontmatter from markdown files.
///
/// Frontmatter is delimited by `---` at the start of the file:
/// ```
/// ---
/// title: My Document
/// tags: [a, b, c]
/// ---
///
/// # Content starts here
/// ```
public struct FrontmatterParser {

    /// Result of parsing a frontmatter document
    public struct ParsedDocument {
        /// The YAML frontmatter as a dictionary
        public let frontmatter: [String: Any]

        /// The markdown content after the frontmatter
        public let content: String

        /// Raw frontmatter string (for re-serialization)
        public let rawFrontmatter: String
    }

    /// Parse a markdown document with YAML frontmatter
    public static func parse(_ text: String) -> ParsedDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if document starts with frontmatter delimiter
        guard trimmed.hasPrefix("---") else {
            return ParsedDocument(frontmatter: [:], content: text, rawFrontmatter: "")
        }

        // Find the closing delimiter
        let lines = trimmed.components(separatedBy: .newlines)
        var frontmatterEndIndex: Int?

        for (index, line) in lines.enumerated() {
            if index > 0 && line.trimmingCharacters(in: .whitespaces) == "---" {
                frontmatterEndIndex = index
                break
            }
        }

        guard let endIndex = frontmatterEndIndex else {
            // No closing delimiter found
            return ParsedDocument(frontmatter: [:], content: text, rawFrontmatter: "")
        }

        // Extract frontmatter and content
        let frontmatterLines = Array(lines[1..<endIndex])
        let contentLines = Array(lines[(endIndex + 1)...])

        let rawFrontmatter = frontmatterLines.joined(separator: "\n")
        let content = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse YAML (simple key-value parser for common cases)
        let frontmatter = parseSimpleYAML(rawFrontmatter)

        return ParsedDocument(
            frontmatter: frontmatter,
            content: content,
            rawFrontmatter: rawFrontmatter
        )
    }

    /// Simple YAML parser for frontmatter (handles common cases)
    private static func parseSimpleYAML(_ yaml: String) -> [String: Any] {
        var result: [String: Any] = [:]
        var currentKey: String?
        var currentArrayItems: [String]?

        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Check for array item (starts with -)
            if trimmed.hasPrefix("- ") {
                if let key = currentKey {
                    let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if currentArrayItems == nil {
                        currentArrayItems = []
                    }
                    currentArrayItems?.append(item)
                    result[key] = currentArrayItems
                }
                continue
            }

            // Check for key-value pair
            if let colonIndex = trimmed.firstIndex(of: ":") {
                // Save previous array if any
                if let key = currentKey, let items = currentArrayItems {
                    result[key] = items
                }
                currentArrayItems = nil

                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let valueStr = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

                currentKey = key

                if valueStr.isEmpty {
                    // Value will be on next lines (array or multiline)
                    continue
                }

                // Parse the value
                result[key] = parseYAMLValue(valueStr)
            }
        }

        return result
    }

    /// Parse a YAML value string into appropriate Swift type
    private static func parseYAMLValue(_ value: String) -> Any {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Boolean
        if trimmed.lowercased() == "true" {
            return true
        }
        if trimmed.lowercased() == "false" {
            return false
        }

        // Null
        if trimmed.lowercased() == "null" || trimmed == "~" {
            return NSNull()
        }

        // Number
        if let intValue = Int(trimmed) {
            return intValue
        }
        if let doubleValue = Double(trimmed) {
            return doubleValue
        }

        // Inline array [a, b, c]
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            let items = inner.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                .filter { !$0.isEmpty }
            return items
        }

        // Quoted string
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }

        // Plain string
        return trimmed
    }

    /// Serialize frontmatter dictionary back to YAML string
    public static func serialize(_ frontmatter: [String: Any]) -> String {
        var lines: [String] = []

        for (key, value) in frontmatter.sorted(by: { $0.key < $1.key }) {
            lines.append(serializeKeyValue(key: key, value: value))
        }

        return lines.joined(separator: "\n")
    }

    private static func serializeKeyValue(key: String, value: Any) -> String {
        switch value {
        case let array as [String]:
            if array.isEmpty {
                return "\(key): []"
            }
            // Use inline format for short arrays
            if array.count <= 3 && array.allSatisfy({ $0.count < 20 }) {
                return "\(key): [\(array.joined(separator: ", "))]"
            }
            // Use block format for longer arrays
            var result = "\(key):"
            for item in array {
                result += "\n  - \(item)"
            }
            return result

        case let bool as Bool:
            return "\(key): \(bool)"

        case let int as Int:
            return "\(key): \(int)"

        case let double as Double:
            return "\(key): \(double)"

        case let string as String:
            // Quote strings that might be ambiguous
            if string.contains(":") || string.contains("#") || string.isEmpty {
                return "\(key): \"\(string)\""
            }
            return "\(key): \(string)"

        case is NSNull:
            return "\(key): null"

        default:
            return "\(key): \(value)"
        }
    }

    /// Create a complete document with frontmatter and content
    public static func createDocument(frontmatter: [String: Any], content: String) -> String {
        let yamlStr = serialize(frontmatter)
        return """
        ---
        \(yamlStr)
        ---

        \(content)
        """
    }
}

// MARK: - Frontmatter Convenience Extensions

extension FrontmatterParser.ParsedDocument {
    /// Get a string value from frontmatter
    public func string(_ key: String) -> String? {
        frontmatter[key] as? String
    }

    /// Get an integer value from frontmatter
    public func int(_ key: String) -> Int? {
        frontmatter[key] as? Int
    }

    /// Get a boolean value from frontmatter
    public func bool(_ key: String) -> Bool? {
        frontmatter[key] as? Bool
    }

    /// Get a string array from frontmatter
    public func stringArray(_ key: String) -> [String]? {
        frontmatter[key] as? [String]
    }

    /// Get a date from frontmatter (ISO8601 format)
    public func date(_ key: String) -> Date? {
        guard let string = frontmatter[key] as? String else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
}
