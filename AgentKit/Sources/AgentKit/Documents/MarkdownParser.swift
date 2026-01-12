import Foundation

// MARK: - Markdown Parser

/// Bi-directional parser for converting between Markdown and Documents.
///
/// Supports standard markdown with YAML frontmatter for metadata:
/// ```markdown
/// ---
/// id: abc-123
/// title: My Document
/// ---
///
/// # Heading
/// Text content...
/// ```
public struct MarkdownParser {

    public init() {}

    // MARK: - Parsing (Markdown -> Document)

    /// Parse a markdown string into a Document
    public func parse(_ markdown: String) throws -> Document {
        var content = markdown
        var frontmatter: [String: String] = [:]

        // Extract YAML frontmatter if present
        if content.hasPrefix("---") {
            let parts = content.components(separatedBy: "---")
            if parts.count >= 3 {
                frontmatter = parseFrontmatter(parts[1])
                content = parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Parse blocks from content
        let blocks = parseBlocks(content)

        // Extract document metadata
        let id = frontmatter["id"].map { DocumentID($0) } ?? DocumentID()
        let title = frontmatter["title"] ?? extractTitle(from: blocks) ?? "Untitled"
        let tags = frontmatter["tags"]?.split(separator: ",").map { TagID(String($0).trimmingCharacters(in: .whitespaces)) } ?? []
        let starred = frontmatter["starred"] == "true"

        return Document(
            id: id,
            title: title,
            blocks: blocks,
            tagIds: tags,
            isStarred: starred
        )
    }

    /// Parse markdown file from disk
    public func parseFile(at url: URL) throws -> Document {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(content)
    }

    // MARK: - Serialization (Document -> Markdown)

    /// Convert a Document to markdown string
    public func serialize(_ document: Document) -> String {
        var lines: [String] = []

        // YAML frontmatter
        lines.append("---")
        lines.append("id: \(document.id.rawValue)")
        lines.append("title: \(document.title)")
        lines.append("created: \(ISO8601DateFormatter().string(from: document.createdAt))")
        lines.append("updated: \(ISO8601DateFormatter().string(from: document.updatedAt))")
        if !document.tagIds.isEmpty {
            lines.append("tags: \(document.tagIds.map { $0.rawValue }.joined(separator: ", "))")
        }
        if document.isStarred {
            lines.append("starred: true")
        }
        lines.append("---")
        lines.append("")

        // Content blocks
        for block in document.blocks {
            lines.append(serializeBlock(block))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Write a Document to a markdown file
    public func writeFile(_ document: Document, to url: URL) throws {
        let content = serialize(document)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Block Parsing

    private func parseBlocks(_ content: String) -> [Block] {
        var blocks: [Block] = []
        let lines = content.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Heading
            if let headingMatch = parseHeading(trimmed) {
                blocks.append(headingMatch)
                index += 1
                continue
            }

            // Divider
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider(DividerBlock()))
                index += 1
                continue
            }

            // Code block
            if trimmed.hasPrefix("```") {
                let (codeBlock, consumed) = parseCodeBlock(lines: lines, startIndex: index)
                blocks.append(codeBlock)
                index += consumed
                continue
            }

            // Quote block
            if trimmed.hasPrefix(">") {
                let (quoteBlock, consumed) = parseQuoteBlock(lines: lines, startIndex: index)
                blocks.append(quoteBlock)
                index += consumed
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let (listBlock, consumed) = parseBulletList(lines: lines, startIndex: index)
                blocks.append(listBlock)
                index += consumed
                continue
            }

            // Numbered list
            if let _ = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let (listBlock, consumed) = parseNumberedList(lines: lines, startIndex: index)
                blocks.append(listBlock)
                index += consumed
                continue
            }

            // Todo list
            if trimmed.hasPrefix("- [") {
                let (todoBlock, consumed) = parseTodoList(lines: lines, startIndex: index)
                blocks.append(todoBlock)
                index += consumed
                continue
            }

            // Agent block (HTML comment markers)
            if trimmed.hasPrefix("<!-- agent:") {
                let (agentBlock, consumed) = parseAgentBlock(lines: lines, startIndex: index)
                if let agentBlock = agentBlock {
                    blocks.append(agentBlock)
                }
                index += consumed
                continue
            }

            // Callout (blockquote with icon)
            if trimmed.hasPrefix("> ") && hasCalloutIcon(String(trimmed.dropFirst(2))) {
                let (calloutBlock, consumed) = parseCallout(lines: lines, startIndex: index)
                blocks.append(calloutBlock)
                index += consumed
                continue
            }

            // Image
            if let imageBlock = parseImage(trimmed) {
                blocks.append(imageBlock)
                index += 1
                continue
            }

            // Default: text block (collect consecutive non-special lines)
            let (textBlock, consumed) = parseTextBlock(lines: lines, startIndex: index)
            blocks.append(textBlock)
            index += consumed
        }

        return blocks
    }

    // MARK: - Individual Block Parsers

    private func parseHeading(_ line: String) -> Block? {
        if line.hasPrefix("### ") {
            return .heading(HeadingBlock(content: String(line.dropFirst(4)), level: .h3))
        } else if line.hasPrefix("## ") {
            return .heading(HeadingBlock(content: String(line.dropFirst(3)), level: .h2))
        } else if line.hasPrefix("# ") {
            return .heading(HeadingBlock(content: String(line.dropFirst(2)), level: .h1))
        }
        return nil
    }

    private func parseCodeBlock(lines: [String], startIndex: Int) -> (Block, Int) {
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let language = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)

        var codeLines: [String] = []
        var index = startIndex + 1

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                index += 1
                break
            }
            codeLines.append(line)
            index += 1
        }

        let block = CodeBlock(
            content: codeLines.joined(separator: "\n"),
            language: language.isEmpty ? nil : language
        )
        return (.code(block), index - startIndex)
    }

    private func parseQuoteBlock(lines: [String], startIndex: Int) -> (Block, Int) {
        var quoteLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") {
                var content = String(line.dropFirst())
                if content.hasPrefix(" ") {
                    content = String(content.dropFirst())
                }
                quoteLines.append(content)
                index += 1
            } else {
                break
            }
        }

        // Check for attribution (last line starting with "—" or "--")
        var attribution: String?
        if let lastLine = quoteLines.last,
           lastLine.hasPrefix("—") || lastLine.hasPrefix("--") {
            attribution = lastLine.replacingOccurrences(of: "^[—-]+\\s*", with: "", options: .regularExpression)
            quoteLines.removeLast()
        }

        let block = QuoteBlock(
            content: quoteLines.joined(separator: "\n"),
            attribution: attribution
        )
        return (.quote(block), index - startIndex)
    }

    private func parseBulletList(lines: [String], startIndex: Int) -> (Block, Int) {
        var items: [ListItem] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let content = String(line.dropFirst(2))
                items.append(ListItem(content: content))
                index += 1
            } else if line.isEmpty {
                // Allow one empty line in lists
                if index + 1 < lines.count {
                    let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if nextLine.hasPrefix("- ") || nextLine.hasPrefix("* ") {
                        index += 1
                        continue
                    }
                }
                break
            } else {
                break
            }
        }

        return (.bulletList(BulletListBlock(items: items)), index - startIndex)
    }

    private func parseNumberedList(lines: [String], startIndex: Int) -> (Block, Int) {
        var items: [ListItem] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if let range = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let content = String(line[range.upperBound...])
                items.append(ListItem(content: content))
                index += 1
            } else if line.isEmpty {
                index += 1
                continue
            } else {
                break
            }
        }

        return (.numberedList(NumberedListBlock(items: items)), index - startIndex)
    }

    private func parseTodoList(lines: [String], startIndex: Int) -> (Block, Int) {
        var items: [TodoItem] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                let content = String(line.dropFirst(6))
                items.append(TodoItem(content: content, isCompleted: true))
                index += 1
            } else if line.hasPrefix("- [ ] ") {
                let content = String(line.dropFirst(6))
                items.append(TodoItem(content: content, isCompleted: false))
                index += 1
            } else if line.isEmpty {
                index += 1
                continue
            } else {
                break
            }
        }

        return (.todo(TodoBlock(items: items)), index - startIndex)
    }

    private func parseAgentBlock(lines: [String], startIndex: Int) -> (Block?, Int) {
        let firstLine = lines[startIndex]

        // Extract agent ID from <!-- agent:id -->
        guard let range = firstLine.range(of: #"agent:([^-\s]+)"#, options: .regularExpression) else {
            return (nil, 1)
        }

        let agentIdStr = String(firstLine[range]).replacingOccurrences(of: "agent:", with: "")

        var contentLines: [String] = []
        var index = startIndex + 1

        while index < lines.count {
            let line = lines[index]
            if line.contains("<!-- /agent -->") {
                index += 1
                break
            }
            contentLines.append(line)
            index += 1
        }

        let block = AgentBlock(
            agentId: agentIdStr == "none" ? nil : AgentID(agentIdStr),
            prompt: "",
            content: contentLines.joined(separator: "\n")
        )
        return (.agent(block), index - startIndex)
    }

    private func hasCalloutIcon(_ text: String) -> Bool {
        // Check if text starts with an emoji or specific callout markers
        let calloutPrefixes = ["💡", "⚠️", "✅", "❌", "📝", "🔔", "ℹ️", "**Info:**", "**Warning:**", "**Success:**", "**Error:**"]
        return calloutPrefixes.contains { text.hasPrefix($0) }
    }

    private func parseCallout(lines: [String], startIndex: Int) -> (Block, Int) {
        var contentLines: [String] = []
        var index = startIndex
        var icon = "💡"
        var style = CalloutStyle.info

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") {
                var content = String(line.dropFirst())
                if content.hasPrefix(" ") {
                    content = String(content.dropFirst())
                }

                // Extract icon and style from first line
                if contentLines.isEmpty {
                    if content.hasPrefix("💡") { icon = "💡"; style = .info }
                    else if content.hasPrefix("⚠️") { icon = "⚠️"; style = .warning }
                    else if content.hasPrefix("✅") { icon = "✅"; style = .success }
                    else if content.hasPrefix("❌") { icon = "❌"; style = .error }

                    // Remove icon and style marker from content
                    content = content.replacingOccurrences(of: #"^[^\s]+\s+\*\*\w+:\*\*\s*"#, with: "", options: .regularExpression)
                }

                contentLines.append(content)
                index += 1
            } else {
                break
            }
        }

        let block = CalloutBlock(
            content: contentLines.joined(separator: "\n"),
            icon: icon,
            style: style
        )
        return (.callout(block), index - startIndex)
    }

    private func parseImage(_ line: String) -> Block? {
        // Match ![alt](url) or ![caption](url)
        guard let match = line.range(of: #"!\[([^\]]*)\]\(([^)]+)\)"#, options: .regularExpression) else {
            return nil
        }

        let matchString = String(line[match])

        // Extract alt/caption
        var caption: String?
        if let altRange = matchString.range(of: #"\[([^\]]*)\]"#, options: .regularExpression) {
            let alt = String(matchString[altRange])
            caption = String(alt.dropFirst().dropLast())
            if caption?.isEmpty == true { caption = nil }
        }

        // Extract URL
        var url: URL?
        if let urlRange = matchString.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
            let urlStr = String(matchString[urlRange])
            let cleanUrl = String(urlStr.dropFirst().dropLast())
            url = URL(string: cleanUrl)
        }

        return .image(ImageBlock(url: url, caption: caption))
    }

    private func parseTextBlock(lines: [String], startIndex: Int) -> (Block, Int) {
        var textLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Stop at special markers
            if trimmed.isEmpty ||
               trimmed.hasPrefix("#") ||
               trimmed.hasPrefix("```") ||
               trimmed.hasPrefix(">") ||
               trimmed.hasPrefix("- ") ||
               trimmed.hasPrefix("* ") ||
               trimmed.hasPrefix("---") ||
               trimmed.hasPrefix("***") ||
               trimmed.hasPrefix("<!-- ") ||
               trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                break
            }

            textLines.append(line)
            index += 1
        }

        let block = TextBlock(content: textLines.joined(separator: "\n"))
        return (.text(block), max(index - startIndex, 1))
    }

    // MARK: - Block Serialization

    private func serializeBlock(_ block: Block) -> String {
        switch block {
        case .text(let b):
            return b.content

        case .heading(let b):
            let prefix = String(repeating: "#", count: b.level.rawValue)
            return "\(prefix) \(b.content)"

        case .bulletList(let b):
            return b.items.map { "- \($0.content)" }.joined(separator: "\n")

        case .numberedList(let b):
            return b.items.enumerated().map { "\($0.offset + 1). \($0.element.content)" }.joined(separator: "\n")

        case .todo(let b):
            return b.items.map { item in
                let checkbox = item.isCompleted ? "[x]" : "[ ]"
                return "- \(checkbox) \(item.content)"
            }.joined(separator: "\n")

        case .code(let b):
            return "```\(b.language ?? "")\n\(b.content)\n```"

        case .quote(let b):
            var lines = b.content.split(separator: "\n").map { "> \($0)" }
            if let attribution = b.attribution {
                lines.append("> — \(attribution)")
            }
            return lines.joined(separator: "\n")

        case .divider(_):
            return "---"

        case .callout(let b):
            return "> \(b.icon) **\(b.style.rawValue.capitalized):** \(b.content)"

        case .image(let b):
            let alt = b.caption ?? b.alt ?? ""
            let url = b.url?.absoluteString ?? b.localPath ?? ""
            return "![\(alt)](\(url))"

        case .agent(let b):
            let agentId = b.agentId?.rawValue ?? "none"
            return "<!-- agent:\(agentId) -->\n\(b.content)\n<!-- /agent -->"
        }
    }

    // MARK: - Helpers

    private func parseFrontmatter(_ yaml: String) -> [String: String] {
        var result: [String: String] = [:]

        for line in yaml.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                // Remove quotes if present
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                // Handle array notation [a, b, c]
                if value.hasPrefix("[") && value.hasSuffix("]") {
                    value = String(value.dropFirst().dropLast())
                }
                result[key] = value
            }
        }

        return result
    }

    private func extractTitle(from blocks: [Block]) -> String? {
        // Use first heading as title
        for block in blocks {
            if case .heading(let h) = block, h.level == .h1 {
                return h.content
            }
        }
        return nil
    }
}

// MARK: - Document Loading Extension

extension Document {
    /// Load a document from a markdown file
    public static func load(from url: URL) throws -> Document {
        try MarkdownParser().parseFile(at: url)
    }

    /// Save this document to a markdown file
    public func save(to url: URL) throws {
        try MarkdownParser().writeFile(self, to: url)
    }
}
