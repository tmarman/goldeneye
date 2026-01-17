//
//  Chunker.swift
//  AgentKit
//
//  Text chunking strategies for the Knowledge Backbone.
//  Chunks documents into smaller pieces suitable for embedding and retrieval.
//

import Foundation

// MARK: - Chunker

/// Text chunker that splits documents into chunks for embedding
public struct KChunker: Sendable {
    public let strategy: KChunkingStrategy
    public let chunkSize: Int
    public let chunkOverlap: Int

    public init(
        strategy: KChunkingStrategy = .semantic,
        chunkSize: Int = 512,
        chunkOverlap: Int = 64
    ) {
        self.strategy = strategy
        self.chunkSize = chunkSize
        self.chunkOverlap = chunkOverlap
    }

    /// Chunk a document into pieces
    public func chunk(_ document: KDocument) -> [KChunk] {
        let content = document.content
        guard !content.isEmpty else { return [] }

        switch strategy {
        case .fixed:
            return fixedChunk(content, documentId: document.id)
        case .sentence:
            return sentenceChunk(content, documentId: document.id)
        case .paragraph:
            return paragraphChunk(content, documentId: document.id)
        case .semantic:
            return semanticChunk(content, documentId: document.id)
        case .markdown:
            return markdownChunk(content, documentId: document.id)
        }
    }

    // MARK: - Fixed Size Chunking

    /// Simple fixed-size chunks with overlap
    private func fixedChunk(_ text: String, documentId: String) -> [KChunk] {
        var chunks: [KChunk] = []
        var position = 0
        var startIndex = text.startIndex

        while startIndex < text.endIndex {
            // Calculate end index
            let targetEnd = text.index(startIndex, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            var endIndex = targetEnd

            // Try to break at word boundary if not at end
            if endIndex < text.endIndex {
                if let spaceIndex = text[startIndex..<endIndex].lastIndex(of: " ") {
                    endIndex = text.index(after: spaceIndex)
                }
            }

            let chunkContent = String(text[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)

            if !chunkContent.isEmpty {
                chunks.append(KChunk(
                    documentId: documentId,
                    content: chunkContent,
                    position: position,
                    startChar: text.distance(from: text.startIndex, to: startIndex),
                    endChar: text.distance(from: text.startIndex, to: endIndex)
                ))
                position += 1
            }

            // Move start with overlap
            let overlapOffset = max(0, chunkSize - chunkOverlap)
            startIndex = text.index(startIndex, offsetBy: overlapOffset, limitedBy: text.endIndex) ?? text.endIndex
        }

        return chunks
    }

    // MARK: - Sentence Chunking

    /// Chunk by sentences, grouping until chunk size is reached
    private func sentenceChunk(_ text: String, documentId: String) -> [KChunk] {
        let sentences = splitSentences(text)
        return groupIntoChunks(sentences, documentId: documentId)
    }

    private func splitSentences(_ text: String) -> [(content: String, range: Range<String.Index>)] {
        var sentences: [(content: String, range: Range<String.Index>)] = []
        var currentStart = text.startIndex

        // Simple sentence splitting on . ! ? followed by space or end
        let pattern = try! NSRegularExpression(pattern: "[.!?]+(?:\\s+|$)", options: [])
        let nsText = text as NSString
        let matches = pattern.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            if let range = Range(match.range, in: text) {
                let sentenceRange = currentStart..<range.upperBound
                let sentence = String(text[sentenceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append((sentence, sentenceRange))
                }
                currentStart = range.upperBound
            }
        }

        // Add remaining text
        if currentStart < text.endIndex {
            let remaining = String(text[currentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                sentences.append((remaining, currentStart..<text.endIndex))
            }
        }

        return sentences
    }

    // MARK: - Paragraph Chunking

    /// Chunk by paragraphs (double newlines)
    private func paragraphChunk(_ text: String, documentId: String) -> [KChunk] {
        let paragraphs = splitParagraphs(text)
        return groupIntoChunks(paragraphs, documentId: documentId)
    }

    private func splitParagraphs(_ text: String) -> [(content: String, range: Range<String.Index>)] {
        var paragraphs: [(content: String, range: Range<String.Index>)] = []
        var currentStart = text.startIndex

        // Split on double newlines
        let pattern = try! NSRegularExpression(pattern: "\\n\\s*\\n", options: [])
        let nsText = text as NSString
        let matches = pattern.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            if let range = Range(match.range, in: text) {
                let paragraphRange = currentStart..<range.lowerBound
                let paragraph = String(text[paragraphRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !paragraph.isEmpty {
                    paragraphs.append((paragraph, paragraphRange))
                }
                currentStart = range.upperBound
            }
        }

        // Add remaining text
        if currentStart < text.endIndex {
            let remaining = String(text[currentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                paragraphs.append((remaining, currentStart..<text.endIndex))
            }
        }

        return paragraphs
    }

    // MARK: - Semantic Chunking

    /// Hybrid approach: prefer paragraphs, fall back to sentences
    private func semanticChunk(_ text: String, documentId: String) -> [KChunk] {
        // First try paragraphs
        let paragraphs = splitParagraphs(text)

        var result: [(content: String, range: Range<String.Index>)] = []

        for para in paragraphs {
            if para.content.count <= chunkSize {
                result.append(para)
            } else {
                // Split large paragraphs by sentences
                let sentences = splitSentences(para.content)
                for sentence in sentences {
                    // Adjust range to be relative to original text
                    let startOffset = text.distance(from: text.startIndex, to: para.range.lowerBound)
                    let sentenceStart = text.distance(from: para.content.startIndex, to: sentence.range.lowerBound)
                    let sentenceEnd = text.distance(from: para.content.startIndex, to: sentence.range.upperBound)

                    let absoluteStart = text.index(text.startIndex, offsetBy: startOffset + sentenceStart)
                    let absoluteEnd = text.index(text.startIndex, offsetBy: startOffset + sentenceEnd, limitedBy: text.endIndex) ?? text.endIndex

                    result.append((sentence.content, absoluteStart..<absoluteEnd))
                }
            }
        }

        return groupIntoChunks(result, documentId: documentId)
    }

    // MARK: - Markdown Chunking

    /// Chunk by markdown structure (headers, code blocks, etc.)
    private func markdownChunk(_ text: String, documentId: String) -> [KChunk] {
        var chunks: [KChunk] = []
        var position = 0
        var currentHeadings: [String] = []

        // Split by headers
        let lines = text.components(separatedBy: .newlines)
        var currentSection = ""
        var sectionStart = 0
        var charOffset = 0

        for (lineIndex, line) in lines.enumerated() {
            // Check for header
            if line.hasPrefix("#") {
                // Save previous section
                if !currentSection.isEmpty {
                    let sectionChunks = createSectionChunks(
                        content: currentSection,
                        documentId: documentId,
                        headings: currentHeadings,
                        startPosition: position,
                        startChar: sectionStart
                    )
                    chunks.append(contentsOf: sectionChunks)
                    position += sectionChunks.count
                }

                // Parse header level and text
                let headerText = line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                let level = line.prefix(while: { $0 == "#" }).count

                // Adjust heading stack
                while currentHeadings.count >= level {
                    currentHeadings.removeLast()
                }
                currentHeadings.append(headerText)

                currentSection = ""
                sectionStart = charOffset
            } else {
                if !currentSection.isEmpty || !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    currentSection += (currentSection.isEmpty ? "" : "\n") + line
                }
            }

            charOffset += line.count + 1  // +1 for newline
        }

        // Save final section
        if !currentSection.isEmpty {
            let sectionChunks = createSectionChunks(
                content: currentSection,
                documentId: documentId,
                headings: currentHeadings,
                startPosition: position,
                startChar: sectionStart
            )
            chunks.append(contentsOf: sectionChunks)
        }

        return chunks
    }

    private func createSectionChunks(
        content: String,
        documentId: String,
        headings: [String],
        startPosition: Int,
        startChar: Int
    ) -> [KChunk] {
        // If small enough, single chunk
        if content.count <= chunkSize {
            return [KChunk(
                documentId: documentId,
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                position: startPosition,
                startChar: startChar,
                endChar: startChar + content.count,
                metadata: KChunkMetadata(headings: headings.isEmpty ? nil : headings)
            )]
        }

        // Split into smaller chunks
        let subChunks = fixedChunk(content, documentId: documentId)
        return subChunks.enumerated().map { (index, chunk) in
            var newChunk = chunk
            newChunk.metadata.headings = headings.isEmpty ? nil : headings
            return KChunk(
                id: newChunk.id,
                documentId: documentId,
                content: newChunk.content,
                position: startPosition + index,
                startChar: startChar + (chunk.startChar ?? 0),
                endChar: startChar + (chunk.endChar ?? chunk.content.count),
                metadata: KChunkMetadata(headings: headings.isEmpty ? nil : headings)
            )
        }
    }

    // MARK: - Grouping Helper

    /// Group smaller pieces into chunks of appropriate size
    private func groupIntoChunks(
        _ pieces: [(content: String, range: Range<String.Index>)],
        documentId: String
    ) -> [KChunk] {
        var chunks: [KChunk] = []
        var position = 0
        var currentContent = ""
        var currentStart: String.Index?
        var currentEnd: String.Index?

        for piece in pieces {
            let wouldExceed = currentContent.count + piece.content.count + 1 > chunkSize

            if wouldExceed && !currentContent.isEmpty {
                // Save current chunk
                chunks.append(KChunk(
                    documentId: documentId,
                    content: currentContent,
                    position: position,
                    startChar: currentStart.map { pieces[0].content.distance(from: pieces[0].content.startIndex, to: $0) },
                    endChar: currentEnd.map { pieces[0].content.distance(from: pieces[0].content.startIndex, to: $0) }
                ))
                position += 1
                currentContent = ""
                currentStart = nil
                currentEnd = nil
            }

            if currentContent.isEmpty {
                currentContent = piece.content
                currentStart = piece.range.lowerBound
                currentEnd = piece.range.upperBound
            } else {
                currentContent += " " + piece.content
                currentEnd = piece.range.upperBound
            }
        }

        // Save remaining
        if !currentContent.isEmpty {
            chunks.append(KChunk(
                documentId: documentId,
                content: currentContent,
                position: position
            ))
        }

        return chunks
    }
}

// MARK: - Chunking Strategy

public enum KChunkingStrategy: String, Sendable, Codable {
    case fixed          // Fixed character count with overlap
    case sentence       // Group sentences
    case paragraph      // Group paragraphs
    case semantic       // Hybrid: paragraphs + sentences
    case markdown       // Markdown-aware chunking

    public var description: String {
        switch self {
        case .fixed: return "Fixed size chunks with overlap"
        case .sentence: return "Group by sentences"
        case .paragraph: return "Group by paragraphs"
        case .semantic: return "Semantic (hybrid) chunking"
        case .markdown: return "Markdown-aware chunking"
        }
    }
}
