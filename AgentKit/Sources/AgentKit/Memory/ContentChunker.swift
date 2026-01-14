import Foundation

// MARK: - Content Chunker

/// Splits content into chunks suitable for embedding.
///
/// Different strategies work better for different content types:
/// - `.semantic` - Best for documents with clear structure
/// - `.sentence` - Best for conversational content
/// - `.fixed` - Best for uniform processing
public struct ContentChunker: Sendable {
    public let strategy: ChunkingStrategy

    public init(strategy: ChunkingStrategy = .semantic) {
        self.strategy = strategy
    }

    /// Chunk content according to the configured strategy
    public func chunk(_ content: String) -> [String] {
        switch strategy {
        case .none:
            return [content]

        case .fixed(let size, let overlap):
            return chunkFixed(content, size: size, overlap: overlap)

        case .sentence(let maxPerChunk):
            return chunkBySentence(content, maxPerChunk: maxPerChunk)

        case .semantic:
            return chunkSemantic(content)
        }
    }

    // MARK: - Fixed Size Chunking

    private func chunkFixed(_ content: String, size: Int, overlap: Int) -> [String] {
        let words = content.split(separator: " ")
        var chunks: [String] = []
        var i = 0

        while i < words.count {
            let end = min(i + size, words.count)
            let chunk = words[i..<end].joined(separator: " ")
            chunks.append(chunk)
            i += size - overlap
        }

        return chunks.isEmpty ? [content] : chunks
    }

    // MARK: - Sentence Chunking

    private func chunkBySentence(_ content: String, maxPerChunk: Int) -> [String] {
        // Use Natural Language for better sentence detection
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var currentChunk: [String] = []

        for sentence in sentences {
            currentChunk.append(sentence)

            if currentChunk.count >= maxPerChunk {
                chunks.append(currentChunk.joined(separator: ". ") + ".")
                currentChunk = []
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: ". ") + ".")
        }

        return chunks.isEmpty ? [content] : chunks
    }

    // MARK: - Semantic Chunking

    private func chunkSemantic(_ content: String) -> [String] {
        var chunks: [String] = []

        // Split by double newlines (paragraphs)
        let paragraphs = content.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Target chunk size: 256-512 tokens (roughly 200-400 words)
        let targetWordCount = 300
        var currentChunk = ""
        var currentWordCount = 0

        for paragraph in paragraphs {
            let paragraphWordCount = paragraph.split(separator: " ").count

            // If this paragraph alone exceeds target, it becomes its own chunk
            if paragraphWordCount > Int(Double(targetWordCount) * 1.5) {
                // Save current chunk if exists
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                    currentChunk = ""
                    currentWordCount = 0
                }

                // Split large paragraph by sentences
                let subChunks = chunkBySentence(paragraph, maxPerChunk: 5)
                chunks.append(contentsOf: subChunks)
                continue
            }

            // If adding this paragraph exceeds target, start new chunk
            if currentWordCount + paragraphWordCount > targetWordCount && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = paragraph
                currentWordCount = paragraphWordCount
            } else {
                // Add to current chunk
                if currentChunk.isEmpty {
                    currentChunk = paragraph
                } else {
                    currentChunk += "\n\n" + paragraph
                }
                currentWordCount += paragraphWordCount
            }
        }

        // Don't forget the last chunk
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks.isEmpty ? [content] : chunks
    }
}

// MARK: - Markdown-Aware Chunking

extension ContentChunker {
    /// Chunk markdown content respecting structure
    public func chunkMarkdown(_ content: String) -> [String] {
        var chunks: [String] = []
        var currentSection = ""
        var currentHeading: String?

        let lines = content.components(separatedBy: "\n")

        for line in lines {
            // Check for headings
            if line.hasPrefix("# ") || line.hasPrefix("## ") || line.hasPrefix("### ") {
                // Save previous section
                if !currentSection.isEmpty {
                    let sectionContent = currentHeading != nil
                        ? "\(currentHeading!)\n\n\(currentSection)"
                        : currentSection
                    chunks.append(contentsOf: chunk(sectionContent))
                }

                currentHeading = line
                currentSection = ""
            } else {
                currentSection += line + "\n"
            }
        }

        // Don't forget last section
        if !currentSection.isEmpty {
            let sectionContent = currentHeading != nil
                ? "\(currentHeading!)\n\n\(currentSection)"
                : currentSection
            chunks.append(contentsOf: chunk(sectionContent))
        }

        return chunks.isEmpty ? [content] : chunks
    }
}
