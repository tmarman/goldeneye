//
//  DocumentExtractorTool.swift
//  AgentKit
//
//  MCP tool for extracting text content from documents.
//  Supports PDFs, iWork (Pages, Numbers, Keynote), and Office formats.
//

import Foundation
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Document Extractor Tool

/// Extract text content from documents
public struct DocumentExtractorTool: Tool {
    public let name = "extract_document_text"
    public let description = """
        Extract text content from a document file.
        Supports:
        - PDF files (.pdf)
        - iWork: Pages (.pages), Numbers (.numbers), Keynote (.key)
        - Office: Word (.docx), Excel (.xlsx), PowerPoint (.pptx)
        - Rich Text (.rtf, .rtfd)
        - Plain Text (.txt, .md)
        Use this to read document contents for indexing or analysis.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "path": .init(
                    type: "string",
                    description: "Path to the document file"
                ),
                "max_length": .init(
                    type: "integer",
                    description: "Maximum characters to extract (default: 50000)"
                ),
                "include_metadata": .init(
                    type: "boolean",
                    description: "Include document metadata like title, author (default: true)"
                )
            ],
            required: ["path"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let path = try input.require("path", as: String.self)
        let maxLength = input.get("max_length", as: Int.self) ?? 50000
        let includeMetadata = input.get("include_metadata", as: Bool.self) ?? true

        let url = URL(fileURLWithPath: path)

        // Check file exists
        guard FileManager.default.fileExists(atPath: path) else {
            return .error("File not found: \(path)")
        }

        do {
            let result = try await extractContent(from: url, maxLength: maxLength, includeMetadata: includeMetadata)
            return .success(result)
        } catch {
            return .error("Failed to extract content: \(error.localizedDescription)")
        }
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let path = input.get("path", as: String.self) {
            let name = (path as NSString).lastPathComponent
            return "Extract text from: \(name)"
        }
        return "Extract document text"
    }

    // MARK: - Extraction

    private func extractContent(from url: URL, maxLength: Int, includeMetadata: Bool) async throws -> String {
        let ext = url.pathExtension.lowercased()

        var output = ""

        // Add metadata if requested
        if includeMetadata {
            let metadata = try await getSpotlightMetadata(for: url)
            if !metadata.isEmpty {
                output += "=== Metadata ===\n"
                for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
                    output += "\(key): \(value)\n"
                }
                output += "\n"
            }
        }

        output += "=== Content ===\n"

        // Extract based on file type
        let content: String

        switch ext {
        case "pdf":
            content = try extractPDF(from: url)

        case "pages", "key", "numbers":
            content = try await extractiWork(from: url)

        case "docx", "xlsx", "pptx":
            content = try extractOffice(from: url)

        case "rtf", "rtfd":
            content = try extractRTF(from: url)

        case "txt", "md", "markdown", "json", "xml", "html", "css", "js", "swift", "py":
            content = try extractPlainText(from: url)

        default:
            // Try Spotlight text content as fallback
            content = try await extractViaSpotlight(from: url)
        }

        // Truncate if needed
        if content.count > maxLength {
            output += String(content.prefix(maxLength))
            output += "\n\n[... truncated at \(maxLength) characters ...]"
        } else {
            output += content
        }

        return output
    }

    // MARK: - PDF Extraction

    private func extractPDF(from url: URL) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            throw DocumentExtractorError.cannotOpenFile
        }

        var text = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i),
               let pageText = page.string {
                text += pageText
                text += "\n\n--- Page \(i + 1) ---\n\n"
            }
        }

        return text.isEmpty ? "[PDF contains no extractable text - may be scanned/image-based]" : text
        #else
        throw DocumentExtractorError.unsupportedPlatform
        #endif
    }

    // MARK: - iWork Extraction

    private func extractiWork(from url: URL) async throws -> String {
        // First try Spotlight (it indexes iWork documents)
        if let spotlightText = try? await extractViaSpotlight(from: url), !spotlightText.isEmpty {
            return spotlightText
        }

        // iWork files are bundles or zip archives
        // Try to find and parse the Index.zip or similar
        let fm = FileManager.default

        // Check if it's a bundle
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return try extractiWorkBundle(from: url)
        } else {
            // Single file - treat as zip
            return try extractiWorkZip(from: url)
        }
    }

    private func extractiWorkBundle(from url: URL) throws -> String {
        // Check for Index.zip inside the bundle
        let indexZip = url.appendingPathComponent("Index.zip")

        if FileManager.default.fileExists(atPath: indexZip.path) {
            // Extract strings from the protobuf files
            return try extractStringsFromZip(at: indexZip)
        }

        // Try preview text
        let previewPath = url.appendingPathComponent("QuickLook/Preview.pdf")
        if FileManager.default.fileExists(atPath: previewPath.path) {
            return try extractPDF(from: previewPath)
        }

        return "[Could not extract text from iWork bundle]"
    }

    private func extractiWorkZip(from url: URL) throws -> String {
        // For single-file iWork, use unzip to extract strings
        return try extractStringsFromZip(at: url)
    }

    private func extractStringsFromZip(at url: URL) throws -> String {
        // Use unzip and strings to extract readable text
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        // Run strings on the output to extract text
        let stringsProcess = Process()
        stringsProcess.executableURL = URL(fileURLWithPath: "/usr/bin/strings")

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        stringsProcess.standardInput = inputPipe
        stringsProcess.standardOutput = outputPipe
        stringsProcess.standardError = FileHandle.nullDevice

        try stringsProcess.run()
        inputPipe.fileHandleForWriting.write(data)
        inputPipe.fileHandleForWriting.closeFile()
        stringsProcess.waitUntilExit()

        let stringsData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let strings = String(data: stringsData, encoding: .utf8) ?? ""

        // Filter out noise and return meaningful text
        let lines = strings.components(separatedBy: .newlines)
            .filter { line in
                // Keep lines with actual content (words, sentences)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.count > 3 &&
                       !trimmed.hasPrefix("_") &&
                       !trimmed.contains("uuid") &&
                       !trimmed.contains("iwa") &&
                       trimmed.rangeOfCharacter(from: .letters) != nil
            }

        return lines.joined(separator: "\n")
    }

    // MARK: - Office Extraction

    private func extractOffice(from url: URL) throws -> String {
        // Office documents are ZIP archives with XML content
        let ext = url.pathExtension.lowercased()

        let contentPath: String
        switch ext {
        case "docx":
            contentPath = "word/document.xml"
        case "xlsx":
            contentPath = "xl/sharedStrings.xml"
        case "pptx":
            contentPath = "ppt/slides/slide*.xml"
        default:
            throw DocumentExtractorError.unsupportedFormat
        }

        // Extract and parse XML
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")

        if ext == "pptx" {
            // For PPTX, extract all slides
            process.arguments = ["-p", url.path, "ppt/slides/*.xml"]
        } else {
            process.arguments = ["-p", url.path, contentPath]
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let xml = String(data: data, encoding: .utf8) else {
            return "[Could not read Office document]"
        }

        // Strip XML tags to get text
        return stripXMLTags(xml)
    }

    private func stripXMLTags(_ xml: String) -> String {
        // Simple regex to remove XML tags and extract text
        let tagPattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else {
            return xml
        }

        let range = NSRange(xml.startIndex..., in: xml)
        let stripped = regex.stringByReplacingMatches(in: xml, range: range, withTemplate: " ")

        // Clean up whitespace
        let lines = stripped.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        return lines.joined(separator: " ")
    }

    // MARK: - RTF Extraction

    private func extractRTF(from url: URL) throws -> String {
        #if canImport(AppKit)
        let data = try Data(contentsOf: url)

        if let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            return attributed.string
        } else if let attributed = try? NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        ) {
            return attributed.string
        }

        throw DocumentExtractorError.cannotOpenFile
        #else
        // Fallback: use textutil
        return try extractViaTextutil(from: url)
        #endif
    }

    // MARK: - Plain Text Extraction

    private func extractPlainText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        // Try different encodings
        if let text = String(data: data, encoding: .utf8) {
            return text
        } else if let text = String(data: data, encoding: .isoLatin1) {
            return text
        } else if let text = String(data: data, encoding: .macOSRoman) {
            return text
        }

        throw DocumentExtractorError.encodingError
    }

    // MARK: - Spotlight Extraction

    private func extractViaSpotlight(from url: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-name", "kMDItemTextContent", "-raw", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""

        if text == "(null)" || text.isEmpty {
            return ""
        }

        return text
    }

    private func extractViaTextutil(from url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Metadata

    private func getSpotlightMetadata(for url: URL) async throws -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = [
            "-name", "kMDItemTitle",
            "-name", "kMDItemAuthors",
            "-name", "kMDItemContentCreationDate",
            "-name", "kMDItemContentModificationDate",
            "-name", "kMDItemContentType",
            "-name", "kMDItemNumberOfPages",
            "-name", "kMDItemKeywords",
            url.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return [:]
        }

        // Parse mdls output
        var metadata: [String: String] = [:]

        for line in output.components(separatedBy: .newlines) {
            if let range = line.range(of: " = ") {
                let key = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                var value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)

                // Clean up value
                if value != "(null)" && !value.isEmpty {
                    // Remove quotes
                    if value.hasPrefix("\"") && value.hasSuffix("\"") {
                        value = String(value.dropFirst().dropLast())
                    }

                    // Clean up key name
                    let cleanKey = key.replacingOccurrences(of: "kMDItem", with: "")
                    metadata[cleanKey] = value
                }
            }
        }

        return metadata
    }
}

// MARK: - Batch Extractor Tool

/// Extract text from multiple documents at once
public struct BatchDocumentExtractorTool: Tool {
    public let name = "extract_documents_batch"
    public let description = """
        Extract text from multiple documents in a directory.
        Useful for indexing a folder of documents at once.
        Returns combined content with file separators.
        """

    public var inputSchema: ToolSchema {
        ToolSchema(
            properties: [
                "directory": .init(
                    type: "string",
                    description: "Path to directory containing documents"
                ),
                "extensions": .init(
                    type: "string",
                    description: "Comma-separated file extensions to include (default: pdf,pages,key,numbers,docx)"
                ),
                "recursive": .init(
                    type: "boolean",
                    description: "Search subdirectories (default: false)"
                ),
                "max_files": .init(
                    type: "integer",
                    description: "Maximum number of files to process (default: 20)"
                )
            ],
            required: ["directory"]
        )
    }

    public init() {}

    public func execute(_ input: ToolInput, context: ToolContext) async throws -> ToolOutput {
        let directory = try input.require("directory", as: String.self)
        let extensionsStr = input.get("extensions", as: String.self) ?? "pdf,pages,key,numbers,docx,xlsx,pptx"
        let recursive = input.get("recursive", as: Bool.self) ?? false
        let maxFiles = input.get("max_files", as: Int.self) ?? 20

        let extensions = Set(extensionsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })

        let directoryURL = URL(fileURLWithPath: directory)

        guard FileManager.default.fileExists(atPath: directory) else {
            return .error("Directory not found: \(directory)")
        }

        // Find matching files
        let enumerator: FileManager.DirectoryEnumerator?
        if recursive {
            enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } else {
            enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        }

        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            if extensions.contains(ext) {
                files.append(url)
                if files.count >= maxFiles {
                    break
                }
            }
        }

        if files.isEmpty {
            return .success("No matching documents found in: \(directory)")
        }

        // Extract each file
        let extractor = DocumentExtractorTool()
        var results: [String] = []

        for file in files {
            let extractInput = ToolInput(parameters: [
                "path": AnyCodable(file.path),
                "max_length": AnyCodable(10000),
                "include_metadata": AnyCodable(false)
            ])

            let output = try await extractor.execute(extractInput, context: context)

            results.append("=== \(file.lastPathComponent) ===")
            results.append(output.content)
            results.append("")
        }

        return .success("Extracted \(files.count) documents:\n\n\(results.joined(separator: "\n"))")
    }

    public func describeAction(_ input: ToolInput) -> String {
        if let dir = input.get("directory", as: String.self) {
            return "Extract documents from: \(dir)"
        }
        return "Extract documents from directory"
    }
}

// MARK: - Errors

public enum DocumentExtractorError: Error, LocalizedError {
    case cannotOpenFile
    case unsupportedFormat
    case unsupportedPlatform
    case encodingError
    case extractionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpenFile:
            return "Cannot open file"
        case .unsupportedFormat:
            return "Unsupported document format"
        case .unsupportedPlatform:
            return "Feature not available on this platform"
        case .encodingError:
            return "Could not decode file contents"
        case .extractionFailed(let reason):
            return "Extraction failed: \(reason)"
        }
    }
}
