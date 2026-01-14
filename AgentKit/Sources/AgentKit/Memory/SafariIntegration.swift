import Foundation

#if os(macOS)
import AppKit
#endif

// MARK: - Safari Integration

/// Integrates with Safari's Reading List and Shared with You features.
///
/// ## Data Sources
/// - **Reading List**: ~/Library/Safari/Bookmarks.plist
/// - **Shared with You**: Uses SharedWithYou framework (macOS 13+)
///
/// ## Usage
/// ```swift
/// let safari = SafariIntegration()
/// let items = try await safari.getReadingList()
/// for item in items {
///     let content = try await safari.fetchContent(for: item)
///     try await memoryStore.indexURL(item.url, title: item.title, content: content, source: .readingList)
/// }
/// ```
public actor SafariIntegration {
    private var lastReadingListSync: Date?
    private var knownReadingListItems: Set<URL> = []

    // MARK: - Reading List

    /// Get all items from Safari Reading List
    public func getReadingList() async throws -> [ReadingListItem] {
        let bookmarksPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")

        guard FileManager.default.fileExists(atPath: bookmarksPath.path) else {
            return []
        }

        // Reading list items are stored in the Bookmarks.plist
        guard let plistData = try? Data(contentsOf: bookmarksPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return []
        }

        var items: [ReadingListItem] = []

        // Navigate to Reading List in the plist structure
        if let children = plist["Children"] as? [[String: Any]] {
            for child in children {
                if let title = child["Title"] as? String, title == "com.apple.ReadingList" {
                    if let readingListChildren = child["Children"] as? [[String: Any]] {
                        for item in readingListChildren {
                            if let urlString = item["URLString"] as? String,
                               let url = URL(string: urlString) {
                                let title = (item["URIDictionary"] as? [String: Any])?["title"] as? String
                                let dateAdded = item["ReadingListNonSync"] as? [String: Any]
                                let addedDate = dateAdded?["DateAdded"] as? Date

                                items.append(ReadingListItem(
                                    url: url,
                                    title: title,
                                    dateAdded: addedDate ?? Date(),
                                    preview: item["PreviewText"] as? String
                                ))
                            }
                        }
                    }
                }
            }
        }

        return items
    }

    /// Get new reading list items since last sync
    public func getNewReadingListItems() async throws -> [ReadingListItem] {
        let allItems = try await getReadingList()
        let newItems = allItems.filter { !knownReadingListItems.contains($0.url) }

        // Update known items
        for item in allItems {
            knownReadingListItems.insert(item.url)
        }
        lastReadingListSync = Date()

        return newItems
    }

    // MARK: - Content Fetching

    /// Fetch and extract text content from a URL
    public func fetchContent(for item: ReadingListItem) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: item.url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SafariIntegrationError.fetchFailed(item.url)
        }

        // Check content type
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("text/html") {
            return extractTextFromHTML(data)
        } else if contentType.contains("text/plain") {
            return String(data: data, encoding: .utf8) ?? ""
        } else if contentType.contains("application/pdf") {
            return try extractTextFromPDF(data)
        }

        // Fallback: try as text
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - HTML Extraction

    private func extractTextFromHTML(_ data: Data) -> String {
        guard let html = String(data: data, encoding: .utf8) else {
            return ""
        }

        // Simple HTML tag stripping - in production would use a proper parser
        var text = html

        // Remove script and style tags with content
        text = text.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: .regularExpression
        )

        // Remove all HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        // Clean up whitespace
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - PDF Extraction

    private func extractTextFromPDF(_ data: Data) throws -> String {
        #if os(macOS)
        guard let pdfDocument = PDFDocument(data: data) else {
            throw SafariIntegrationError.pdfExtractionFailed
        }

        var text = ""
        for i in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: i),
               let pageText = page.string {
                text += pageText + "\n\n"
            }
        }
        return text
        #else
        // iOS would use PDFKit differently
        return ""
        #endif
    }
}

// MARK: - Types

public struct ReadingListItem: Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let title: String?
    public let dateAdded: Date
    public let preview: String?
}

public enum SafariIntegrationError: Error, LocalizedError {
    case fetchFailed(URL)
    case pdfExtractionFailed
    case accessDenied

    public var errorDescription: String? {
        switch self {
        case .fetchFailed(let url):
            return "Failed to fetch content from \(url)"
        case .pdfExtractionFailed:
            return "Failed to extract text from PDF"
        case .accessDenied:
            return "Access to Safari data denied - check privacy settings"
        }
    }
}

#if os(macOS)
import PDFKit
#endif

// MARK: - Shared with You Integration

#if os(macOS)
import SharedWithYou

/// Integration with macOS Shared with You feature
@available(macOS 13.0, *)
public actor SharedWithYouIntegration {
    private let highlightCenter = SWHighlightCenter()
    private var knownHighlights: Set<String> = []

    /// Get all shared items
    public func getSharedItems() async throws -> [SharedItem] {
        // Get highlights from the SharedWithYou framework
        let highlights = highlightCenter.highlights

        var items: [SharedItem] = []

        for highlight in highlights {
            // Extract URL from highlight
            let url = highlight.url

            // Use persistent identifier as ID
            let id = String(describing: highlight.identifier)

            let item = SharedItem(
                id: id,
                url: url,
                title: nil, // Will be fetched from URL
                sharedBy: nil, // Attribution API varies by macOS version
                sourceApp: nil,
                dateShared: Date() // Timestamp availability varies
            )

            items.append(item)
        }

        return items
    }

    /// Get new shared items since last check
    public func getNewSharedItems() async throws -> [SharedItem] {
        let allItems = try await getSharedItems()
        let newItems = allItems.filter { !knownHighlights.contains($0.id) }

        // Update known items
        for item in allItems {
            knownHighlights.insert(item.id)
        }

        return newItems
    }
}

public struct SharedItem: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let title: String?
    public let sharedBy: String?
    public let sourceApp: String?
    public let dateShared: Date
}
#endif
