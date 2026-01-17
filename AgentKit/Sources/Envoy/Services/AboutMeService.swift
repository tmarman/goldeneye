import AgentKit
import Foundation
import SwiftUI

// MARK: - About Me Service

/// Service managing the special "About Me" space.
///
/// The About Me space is owned by the Concierge agent and serves as:
/// - Personal knowledge base about the user
/// - Learning center for user preferences and patterns
/// - Hub for suggesting new Space setups based on work history
///
/// Key features:
/// - Auto-creates on first launch if not present
/// - Indexes user content: iCloud files, Mail, Messages, Reminders, Calendar
/// - Tracks work patterns and suggests relevant Spaces
/// - Provides conversational interface for feedback
@MainActor
public class AboutMeService: ObservableObject {
    // MARK: - Properties

    /// Whether the About Me space exists
    @Published public private(set) var isInitialized = false

    /// The About Me space ID (nil if not created yet)
    @Published public private(set) var spaceId: SpaceID?

    /// The user profile store for persisting learnings
    private let profileStore = UserProfileStore()

    /// The profile builder for agentic exploration
    public let profileBuilder = ProfileBuilder(profileStore: UserProfileStore())

    /// Indexing progress (0.0 to 1.0)
    @Published public var indexingProgress: Double = 0.0

    /// Current indexing status message
    @Published public var indexingStatus: String = "Not started"

    /// Detailed indexing activity log
    @Published public var indexingLog: [IndexingLogEntry] = []

    /// Currently scanning file/directory
    @Published public var currentlyScanning: String = ""

    /// File type counts discovered during indexing
    @Published public var fileTypeCounts: [String: Int] = [:]

    /// Discovered user insights
    @Published public var insights: [UserInsight] = []

    /// Suggested spaces based on user patterns
    @Published public var suggestedSpaces: [SpaceSuggestion] = []

    /// Discovered files by category (images, documents, code, etc.)
    @Published public var discoveredFiles: [DiscoveredFile] = []

    /// Sample images found during indexing (for display)
    @Published public var sampleImages: [URL] = []

    /// Recent documents found
    @Published public var recentDocuments: [DiscoveredFile] = []

    /// The Concierge thread for this space
    @Published public var conciergeThreadId: AgentKit.ThreadID?

    /// Whether indexing is currently in progress
    @Published public var isIndexing = false

    // MARK: - Constants

    public static let aboutMeSpaceId = SpaceID("about-me")
    public static let aboutMeSpaceName = "About Me"

    public static let personalSpaceId = SpaceID("personal")
    public static let personalSpaceName = "Personal"

    // MARK: - Initialization

    public init() {}

    // MARK: - Setup

    /// Initialize bootstrap spaces if they don't exist
    /// This creates the About Me space and a default Personal space for first launch
    public func initializeIfNeeded(appState: AppState) async {
        // Check if About Me space already exists
        let hasAboutMe = appState.spaces.contains(where: { $0.id == Self.aboutMeSpaceId.rawValue })

        if hasAboutMe {
            spaceId = Self.aboutMeSpaceId
            isInitialized = true

            // Find the Concierge thread (should only be one)
            if let thread = appState.workspace.threads.first(where: {
                $0.container.spaceId == Self.aboutMeSpaceId.rawValue && $0.container.agentName == "Concierge"
            }) {
                conciergeThreadId = thread.id

                // Clean up any duplicate threads
                let duplicates = appState.workspace.threads.filter {
                    $0.container.spaceId == Self.aboutMeSpaceId.rawValue && $0.container.agentName == "Concierge" && $0.id != thread.id
                }
                for dup in duplicates {
                    appState.workspace.threads.removeAll { $0.id == dup.id }
                }
            }
        } else {
            // Create the About Me space
            await createAboutMeSpace(appState: appState)
        }

        // Also ensure the default Personal space exists
        let hasPersonal = appState.spaces.contains(where: { $0.id == Self.personalSpaceId.rawValue })
        if !hasPersonal {
            await createPersonalSpace(appState: appState)
        }
    }

    private func createAboutMeSpace(appState: AppState) async {
        // Create the special About Me space
        let aboutMeSpace = SpaceViewModel(
            id: Self.aboutMeSpaceId.rawValue,
            name: Self.aboutMeSpaceName,
            description: "Your personal profile space, managed by Concierge",
            icon: "person.crop.circle.fill",
            color: .blue,
            path: nil,  // Virtual space, not file-backed
            channels: [
                ChannelViewModel(id: "insights", name: "Insights", icon: "lightbulb.fill", unreadCount: 0),
                ChannelViewModel(id: "suggestions", name: "Suggestions", icon: "sparkles", unreadCount: 0),
                ChannelViewModel(id: "preferences", name: "Preferences", icon: "slider.horizontal.3", unreadCount: 0)
            ]
        )

        appState.spaces.insert(aboutMeSpace, at: 0)
        spaceId = Self.aboutMeSpaceId

        // Create the Concierge conversation
        let welcomeMessage = AgentKit.ThreadMessage.assistant(
            """
            👋 **Welcome to your About Me space!**

            I'm your **Concierge** - I help you get the most out of Envoy by learning about your work and suggesting ways to organize it.

            Here's what I can do for you:
            - 📁 **Index your files** from iCloud, Documents, and Downloads
            - 📧 **Learn from your communications** (Mail, Messages)
            - 📅 **Understand your schedule** from Calendar and Reminders
            - 💡 **Suggest new Spaces** based on your work patterns

            Would you like me to start learning about you? I can begin indexing your content to provide personalized suggestions.

            **Quick actions:**
            - Say "**Start indexing**" to begin
            - Say "**Show suggestions**" to see Space recommendations
            - Say "**Privacy settings**" to control what I access
            """,
            agentName: "Concierge"
        )

        let conciergeThread = AgentKit.Thread(
            title: "Chat with Concierge",
            messages: [welcomeMessage],
            container: .space(Self.aboutMeSpaceId.rawValue)
        )

        appState.workspace.threads.insert(conciergeThread, at: 0)
        conciergeThreadId = conciergeThread.id

        // Persist
        await appState.saveThread(conciergeThread)

        isInitialized = true
        indexingStatus = "Ready to start"
    }

    /// Create the default Personal space for general use
    private func createPersonalSpace(appState: AppState) async {
        let personalSpace = SpaceViewModel(
            id: Self.personalSpaceId.rawValue,
            name: Self.personalSpaceName,
            description: "Your personal workspace for notes, chats, and documents",
            icon: "folder.fill",
            color: .purple,
            path: nil,
            channels: [
                ChannelViewModel(id: "general", name: "General", icon: "bubble.left.and.bubble.right", unreadCount: 0),
                ChannelViewModel(id: "notes", name: "Notes", icon: "note.text", unreadCount: 0),
                ChannelViewModel(id: "tasks", name: "Tasks", icon: "checklist", unreadCount: 0)
            ]
        )

        // Insert after About Me (at index 1)
        let insertIndex = min(1, appState.spaces.count)
        appState.spaces.insert(personalSpace, at: insertIndex)
    }

    // MARK: - Indexing

    /// Helper to add a log entry
    private func log(_ type: IndexingLogEntry.LogType, _ message: String, detail: String? = nil) {
        indexingLog.append(IndexingLogEntry(type: type, message: message, detail: detail))
    }

    /// Start indexing user content
    public func startIndexing(appState: AppState) async {
        // Guard against multiple concurrent runs
        guard !isIndexing else {
            log(.info, "Indexing already in progress, skipping...")
            return
        }

        // Reset state
        isIndexing = true
        indexingStatus = "Starting..."
        indexingProgress = 0.0
        indexingLog = []
        fileTypeCounts = [:]
        insights = []
        suggestedSpaces = []
        discoveredFiles = []
        sampleImages = []
        recentDocuments = []

        log(.info, "Starting indexing process...")

        // Phase 1: Scan file system
        indexingStatus = "Scanning files..."
        log(.info, "Phase 1: Scanning file system")
        await scanFileSystem()
        indexingProgress = 0.25
        log(.complete, "File system scan complete", detail: "\(fileTypeCounts.values.reduce(0, +)) files indexed")

        // Phase 2: Scan communications (if permitted)
        indexingStatus = "Analyzing communications..."
        log(.info, "Phase 2: Analyzing communications")
        await scanCommunications()
        indexingProgress = 0.50
        log(.complete, "Communications scan complete")

        // Phase 3: Scan calendar and reminders
        indexingStatus = "Checking calendar..."
        log(.info, "Phase 3: Checking calendar and reminders")
        await scanCalendarAndReminders()
        indexingProgress = 0.75
        log(.complete, "Calendar scan complete")

        // Phase 4: Generate insights
        indexingStatus = "Generating insights..."
        log(.info, "Phase 4: Generating insights from collected data")
        await generateInsights()
        indexingProgress = 0.90
        log(.complete, "Generated \(insights.count) insights")

        // Phase 5: Generate space suggestions
        indexingStatus = "Creating suggestions..."
        log(.info, "Phase 5: Creating space suggestions")
        await generateSpaceSuggestions(appState: appState)
        indexingProgress = 1.0
        log(.complete, "Generated \(suggestedSpaces.count) space suggestions")

        indexingStatus = "Complete!"
        log(.info, "✅ Indexing complete!")
        isIndexing = false

        // Update the Concierge conversation with results
        await postIndexingResults(appState: appState)
    }

    // MARK: - Agentic Profile Building

    /// Build profile using an agentic workflow (LLM explores file system)
    ///
    /// This is more intelligent than startIndexing() - the agent decides what to explore,
    /// forms hypotheses, and records meaningful learnings about the user.
    public func buildAgenticProfile(appState: AppState) async {
        guard let agentKit = appState.agentKit else {
            log(.info, "AgentKit not available for agentic profile building")
            return
        }

        log(.info, "Starting agentic profile building...")
        indexingStatus = "AI is exploring your files..."
        isIndexing = true

        // Run the profile builder
        await profileBuilder.buildProfile(using: agentKit)

        // Copy learnings to our insights for display
        for learning in profileBuilder.discoveredLearnings {
            insights.append(UserInsight(
                type: mapLearningCategory(learning.category),
                title: learning.title,
                description: learning.description,
                confidence: learning.confidence
            ))
        }

        indexingStatus = "Complete!"
        isIndexing = false
        log(.info, "✅ Agentic profile building complete - \(profileBuilder.discoveredLearnings.count) learnings")

        // Update the Concierge conversation with results
        await postAgenticResults(appState: appState)
    }

    private func mapLearningCategory(_ category: String) -> UserInsight.InsightType {
        switch category.lowercased() {
        case "work", "technology":
            return .technology
        case "interest":
            return .general
        case "pattern":
            return .workStyle
        default:
            return .general
        }
    }

    private func postAgenticResults(appState: AppState) async {
        guard let threadId = conciergeThreadId,
              let index = appState.workspace.threads.firstIndex(where: { $0.id == threadId }) else {
            return
        }

        var message = "## 🔍 Profile Building Complete!\n\n"
        message += "I explored your file system and discovered **\(profileBuilder.discoveredLearnings.count)** insights about you.\n\n"

        if !profileBuilder.discoveredLearnings.isEmpty {
            message += "### What I Learned\n\n"
            for learning in profileBuilder.discoveredLearnings {
                let confidence = Int(learning.confidence * 100)
                message += "- **\(learning.title)** (\(confidence)% confident)\n"
                message += "  _\(learning.description)_\n"
                if let evidence = learning.evidence {
                    message += "  Evidence: `\(evidence)`\n"
                }
                message += "\n"
            }
        }

        message += "Your profile has been saved. I'll use this to personalize your experience!"

        let resultMessage = AgentKit.ThreadMessage.assistant(message, agentName: "Concierge")

        appState.workspace.threads[index].messages.append(resultMessage)
        appState.workspace.threads[index].updatedAt = Date()

        await appState.saveThread(appState.workspace.threads[index])
    }

    private func scanFileSystem() async {
        // Scan common directories for patterns
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directories: [(String, URL)] = [
            ("Documents", home.appendingPathComponent("Documents")),
            ("Downloads", home.appendingPathComponent("Downloads")),
            ("Desktop", home.appendingPathComponent("Desktop")),
        ]

        // Check for iCloud Drive
        let iCloudURL = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: iCloudURL.path) {
            directories.append(("iCloud Drive", iCloudURL))
        }

        // Note: Skipping ~/dev and other code directories to avoid scanning millions of files
        // in node_modules, build folders, etc. Focus on user documents for indexing.

        var allFileTypes: [String: Int] = [:]
        var projectIndicators: [String] = []
        var accessDeniedDirs: [String] = []
        var totalFilesScanned = 0

        // Track discovered files
        var allDiscoveredFiles: [DiscoveredFile] = []
        var foundImages: [URL] = []
        var foundDocuments: [DiscoveredFile] = []

        // Image extensions to track
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp"])

        for (dirIndex, (dirName, directory)) in directories.enumerated() {
            log(.directory, "📂 Scanning ~/\(dirName)...")
            currentlyScanning = "~/\(dirName)"
            indexingStatus = "Scanning \(dirName)..."

            // Check if directory exists
            guard FileManager.default.fileExists(atPath: directory.path) else {
                log(.info, "Skipping ~/\(dirName) - not found")
                continue
            }

            // Check if we have read access
            guard FileManager.default.isReadableFile(atPath: directory.path) else {
                log(.info, "⚠️ No access to ~/\(dirName) - grant in System Settings > Privacy & Security > Files and Folders")
                accessDeniedDirs.append(dirName)
                continue
            }

            // Try to enumerate - this will fail if we don't have full disk access
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                log(.info, "Cannot enumerate ~/\(dirName) - check permissions")
                accessDeniedDirs.append(dirName)
                continue
            }

            // Skip these heavy directories that can contain millions of files
            let skipDirs = Set(["node_modules", ".build", "build", "target", "dist", "Pods",
                               "DerivedData", "vendor", "__pycache__", ".venv", "venv"])

            var fileCount = 0
            let maxFilesPerDir = 1000  // Reasonable limit per directory

            while let fileURL = enumerator.nextObject() as? URL, fileCount < maxFilesPerDir {
                // Skip heavy directories entirely
                let lastComponent = fileURL.lastPathComponent
                if skipDirs.contains(lastComponent) {
                    enumerator.skipDescendants()
                    continue
                }

                // Skip directories themselves
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    continue
                }

                fileCount += 1
                totalFilesScanned += 1

                let ext = fileURL.pathExtension.lowercased()
                if !ext.isEmpty {
                    allFileTypes[ext, default: 0] += 1
                }

                // Get file attributes
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = (attributes?[.size] as? Int64) ?? 0
                let modDate = (attributes?[.modificationDate] as? Date) ?? Date.distantPast

                // Get relative path for display
                let relativePath = fileURL.path.replacingOccurrences(of: home.path, with: "~")
                let filename = fileURL.lastPathComponent

                // Create discovered file record
                let category = DiscoveredFile.category(for: ext)
                let discoveredFile = DiscoveredFile(
                    url: fileURL,
                    name: filename,
                    category: category,
                    size: fileSize,
                    modifiedDate: modDate
                )

                // Track images (collect up to 20 sample images)
                if imageExtensions.contains(ext) {
                    if foundImages.count < 20 {
                        foundImages.append(fileURL)
                    }
                    log(.file, "🖼️ \(relativePath)")
                }

                // Track recent documents (PDFs, docs, etc.)
                if category == .document && fileSize > 1000 {  // Skip tiny files
                    foundDocuments.append(discoveredFile)
                    if foundDocuments.count <= 10 {
                        log(.file, "📄 \(relativePath)")
                    }
                }

                // Keep track of all files (sample)
                if allDiscoveredFiles.count < 500 {
                    allDiscoveredFiles.append(discoveredFile)
                }

                // Look for project indicators
                let lowercasedFilename = filename.lowercased()
                if lowercasedFilename == "package.json" {
                    let projectName = fileURL.deletingLastPathComponent().lastPathComponent
                    projectIndicators.append("Node.js: \(projectName)")
                    log(.file, "📦 Node.js project: \(projectName)")
                }
                if lowercasedFilename == "cargo.toml" {
                    let projectName = fileURL.deletingLastPathComponent().lastPathComponent
                    projectIndicators.append("Rust: \(projectName)")
                    log(.file, "🦀 Rust project: \(projectName)")
                }
                if lowercasedFilename == "package.swift" {
                    let projectName = fileURL.deletingLastPathComponent().lastPathComponent
                    projectIndicators.append("Swift: \(projectName)")
                    log(.file, "🍎 Swift project: \(projectName)")
                }
                if lowercasedFilename == "requirements.txt" || lowercasedFilename == "pyproject.toml" {
                    let projectName = fileURL.deletingLastPathComponent().lastPathComponent
                    projectIndicators.append("Python: \(projectName)")
                    log(.file, "🐍 Python project: \(projectName)")
                }
                if lowercasedFilename == "go.mod" {
                    let projectName = fileURL.deletingLastPathComponent().lastPathComponent
                    projectIndicators.append("Go: \(projectName)")
                    log(.file, "🔵 Go project: \(projectName)")
                }

                // Update UI frequently for visible progress
                if fileCount % 25 == 0 {
                    currentlyScanning = relativePath
                    fileTypeCounts = allFileTypes
                    indexingStatus = "Scanning \(dirName)... (\(fileCount) files)"
                    // Allow UI to update
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }

            // Update progress based on directories scanned
            let dirProgress = Double(dirIndex + 1) / Double(directories.count)
            indexingProgress = 0.05 + (dirProgress * 0.20)  // Phase 1 is 5-25%

            log(.complete, "✅ ~/\(dirName): \(fileCount) files indexed")
        }

        // Store discovered files
        discoveredFiles = allDiscoveredFiles
        sampleImages = foundImages

        // Sort documents by modification date (most recent first)
        recentDocuments = foundDocuments.sorted { $0.modifiedDate > $1.modifiedDate }.prefix(20).map { $0 }

        // Log summary of what we found
        if !foundImages.isEmpty {
            log(.insight, "🖼️ Found \(foundImages.count) images")
        }
        if !foundDocuments.isEmpty {
            log(.insight, "📄 Found \(foundDocuments.count) documents")
        }

        // Log discovered projects
        for indicator in Set(projectIndicators).prefix(10) {
            log(.file, "Project detected: \(indicator)")
        }

        // Log access denied directories
        if !accessDeniedDirs.isEmpty {
            log(.info, "⚠️ Could not access: \(accessDeniedDirs.joined(separator: ", "))")
            // Add insight about needing permissions
            insights.append(UserInsight(
                type: .general,
                title: "Limited Access",
                description: "Grant Full Disk Access in System Settings for deeper analysis",
                confidence: 1.0
            ))
        }

        fileTypeCounts = allFileTypes
        currentlyScanning = ""

        // Generate insights from file scan
        if allFileTypes["swift", default: 0] > 10 {
            let count = allFileTypes["swift", default: 0]
            insights.append(UserInsight(
                type: .technology,
                title: "Swift Developer",
                description: "Found \(count) Swift files",
                confidence: 0.9
            ))
            log(.insight, "Insight: Swift Developer", detail: "\(count) Swift files found")
        }
        if allFileTypes["ts", default: 0] + allFileTypes["tsx", default: 0] > 10 {
            let count = allFileTypes["ts", default: 0] + allFileTypes["tsx", default: 0]
            insights.append(UserInsight(
                type: .technology,
                title: "TypeScript Developer",
                description: "Found \(count) TypeScript files",
                confidence: 0.85
            ))
            log(.insight, "Insight: TypeScript Developer", detail: "\(count) TypeScript files found")
        }
        if allFileTypes["py", default: 0] > 10 {
            let count = allFileTypes["py", default: 0]
            insights.append(UserInsight(
                type: .technology,
                title: "Python Developer",
                description: "Found \(count) Python files",
                confidence: 0.85
            ))
            log(.insight, "Insight: Python Developer", detail: "\(count) Python files found")
        }
        if allFileTypes["rs", default: 0] > 5 {
            let count = allFileTypes["rs", default: 0]
            insights.append(UserInsight(
                type: .technology,
                title: "Rust Developer",
                description: "Found \(count) Rust files",
                confidence: 0.85
            ))
            log(.insight, "Insight: Rust Developer", detail: "\(count) Rust files found")
        }
        if allFileTypes["md", default: 0] > 20 {
            let count = allFileTypes["md", default: 0]
            insights.append(UserInsight(
                type: .workStyle,
                title: "Documentation Writer",
                description: "Found \(count) markdown files",
                confidence: 0.8
            ))
            log(.insight, "Insight: Documentation Writer", detail: "\(count) markdown files found")
        }
        if allFileTypes["pdf", default: 0] > 50 {
            let count = allFileTypes["pdf", default: 0]
            insights.append(UserInsight(
                type: .workStyle,
                title: "Document Reader",
                description: "Large PDF collection (\(count) files)",
                confidence: 0.7
            ))
            log(.insight, "Insight: Document Reader", detail: "\(count) PDF files found")
        }
    }

    private func scanCommunications() async {
        // Mail and Messages APIs require special entitlements not available to third-party apps.
        // In the future, we could analyze:
        // - Exported mailbox files (.mbox)
        // - iMessage database (if Full Disk Access granted)
        // - Slack exports (if user provides them)
        //
        // For now, this phase is skipped - no fake insights added.
        log(.info, "Communications scan skipped (requires exported data)")
    }

    private func scanCalendarAndReminders() async {
        let calendarService = CalendarService.shared

        // Check authorization status
        calendarService.checkAuthorizationStatus()

        // Check for calendar access (fullAccess on macOS 14+, authorized on earlier)
        let hasAccess: Bool
        if #available(macOS 14.0, *) {
            hasAccess = calendarService.authorizationStatus == .fullAccess
        } else {
            hasAccess = calendarService.authorizationStatus == .authorized
        }

        guard hasAccess else {
            log(.info, "Calendar access not granted - request in System Settings")
            insights.append(UserInsight(
                type: .schedule,
                title: "Calendar Access",
                description: "Grant calendar access in System Settings for schedule insights",
                confidence: 0.5
            ))
            return
        }

        // Refresh events from calendar
        await calendarService.refreshEvents()

        let todayCount = calendarService.todayEvents.count
        let upcomingCount = calendarService.upcomingEvents.count

        log(.info, "Found \(todayCount) events today, \(upcomingCount) upcoming")

        if todayCount > 0 {
            insights.append(UserInsight(
                type: .schedule,
                title: "Today's Schedule",
                description: "\(todayCount) events scheduled for today",
                confidence: 0.9
            ))
            log(.insight, "Schedule insight: \(todayCount) events today")
        }

        if upcomingCount > 0 {
            insights.append(UserInsight(
                type: .schedule,
                title: "Upcoming Week",
                description: "\(upcomingCount) events in the next 7 days",
                confidence: 0.9
            ))
            log(.insight, "Schedule insight: \(upcomingCount) upcoming events")
        }

        // Analyze meeting patterns
        let allEvents = calendarService.todayEvents + calendarService.upcomingEvents
        let meetingCount = allEvents.filter { !$0.isAllDay }.count
        let allDayCount = allEvents.filter { $0.isAllDay }.count

        if meetingCount > 10 {
            insights.append(UserInsight(
                type: .workStyle,
                title: "Meeting-Heavy Schedule",
                description: "\(meetingCount) timed meetings this week",
                confidence: 0.8
            ))
        }

        if allDayCount > 3 {
            insights.append(UserInsight(
                type: .workStyle,
                title: "Block Scheduling",
                description: "\(allDayCount) all-day events (likely focus blocks)",
                confidence: 0.7
            ))
        }
    }

    private func generateInsights() async {
        // Analyze collected data and generate high-level insights
        // This is where ML/LLM analysis would happen in production

        if insights.isEmpty {
            insights.append(UserInsight(
                type: .general,
                title: "Getting Started",
                description: "Grant permissions in Settings → Extensions to enable full analysis",
                confidence: 1.0
            ))
        }

        // Persist insights as profile learnings
        await persistInsightsToProfile()
    }

    /// Convert discovered insights into persistent profile learnings
    private func persistInsightsToProfile() async {
        // Load existing profile
        try? await profileStore.load()

        // Convert each insight to a ProfileLearning
        for insight in insights {
            let category = convertInsightCategory(insight.type)

            await profileStore.addFromIndexing(
                category: category,
                title: insight.title,
                description: insight.description,
                evidence: gatherEvidence(for: insight),
                confidence: insight.confidence
            )
        }

        // Mark indexing complete and save
        await profileStore.markIndexingComplete()
        try? await profileStore.save()

        log(.complete, "💾 Profile saved with \(insights.count) learnings")
    }

    /// Convert insight type to learning category
    private func convertInsightCategory(_ type: UserInsight.InsightType) -> LearningCategory {
        switch type {
        case .technology:
            return .work
        case .workStyle:
            return .pattern
        case .communication:
            return .pattern
        case .schedule:
            return .pattern
        case .general:
            return .general
        }
    }

    /// Gather evidence paths for an insight
    private func gatherEvidence(for insight: UserInsight) -> [String] {
        var evidence: [String] = []

        // Add sample file paths as evidence based on insight type
        switch insight.type {
        case .technology:
            // Add relevant code files as evidence
            let relevantFiles = discoveredFiles
                .filter { $0.category == .code }
                .prefix(5)
                .map { $0.relativePath }
            evidence.append(contentsOf: relevantFiles)

        case .workStyle:
            // Add document files as evidence
            let relevantDocs = recentDocuments
                .prefix(3)
                .map { $0.relativePath }
            evidence.append(contentsOf: relevantDocs)

        case .schedule, .communication, .general:
            // No file evidence for these
            break
        }

        return evidence
    }

    private func generateSpaceSuggestions(appState: AppState) async {
        // Generate Space suggestions based on insights
        let existingSpaceNames = Set(appState.spaces.map { $0.name.lowercased() })

        // Suggest based on detected technologies
        if insights.contains(where: { $0.title.contains("Swift") }) &&
           !existingSpaceNames.contains("swift projects") {
            suggestedSpaces.append(SpaceSuggestion(
                name: "Swift Projects",
                description: "Organize your Swift and iOS/macOS development work",
                icon: "swift",
                color: .orange,
                reason: "Detected Swift files in your Documents",
                suggestedAgents: ["Coder", "Reviewer"]
            ))
        }

        if insights.contains(where: { $0.title.contains("TypeScript") }) &&
           !existingSpaceNames.contains("web development") {
            suggestedSpaces.append(SpaceSuggestion(
                name: "Web Development",
                description: "Frontend and fullstack web projects",
                icon: "globe",
                color: .blue,
                reason: "Detected TypeScript projects",
                suggestedAgents: ["Coder", "Designer"]
            ))
        }

        if insights.contains(where: { $0.title.contains("Documentation") }) &&
           !existingSpaceNames.contains("documentation") {
            suggestedSpaces.append(SpaceSuggestion(
                name: "Documentation",
                description: "Technical writing and documentation projects",
                icon: "doc.text",
                color: .purple,
                reason: "Found significant markdown files",
                suggestedAgents: ["Writer", "Editor"]
            ))
        }

        // Always suggest a Research space if not present
        if !existingSpaceNames.contains("research") {
            suggestedSpaces.append(SpaceSuggestion(
                name: "Research",
                description: "Collect and organize research materials",
                icon: "magnifyingglass",
                color: .green,
                reason: "Useful for organizing learning and exploration",
                suggestedAgents: ["Librarian", "Weaver"]
            ))
        }
    }

    private func postIndexingResults(appState: AppState) async {
        guard let threadId = conciergeThreadId,
              let index = appState.workspace.threads.firstIndex(where: { $0.id == threadId }) else {
            return
        }

        // Build results message with actual file details
        var message = "## Indexing Complete! 🎉\n\n"

        // Summary stats
        let totalFiles = fileTypeCounts.values.reduce(0, +)
        message += "I scanned **\(totalFiles) files** across your Documents, Downloads, Desktop, and iCloud Drive.\n\n"

        // Images found
        if !sampleImages.isEmpty {
            message += "### 🖼️ Images Found (\(sampleImages.count))\n"
            message += "Here are some images I discovered:\n"
            for image in sampleImages.prefix(5) {
                let relativePath = image.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
                message += "- `\(relativePath)`\n"
            }
            if sampleImages.count > 5 {
                message += "- _...and \(sampleImages.count - 5) more_\n"
            }
            message += "\n"
        }

        // Recent documents
        if !recentDocuments.isEmpty {
            message += "### 📄 Recent Documents\n"
            for doc in recentDocuments.prefix(5) {
                let sizeKB = doc.size / 1024
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                message += "- `\(doc.relativePath)` (\(sizeKB)KB, modified \(dateFormatter.string(from: doc.modifiedDate)))\n"
            }
            if recentDocuments.count > 5 {
                message += "- _...and \(recentDocuments.count - 5) more_\n"
            }
            message += "\n"
        }

        // File type breakdown
        let sortedTypes = fileTypeCounts.sorted { $0.value > $1.value }.prefix(6)
        if !sortedTypes.isEmpty {
            message += "### 📊 File Types\n"
            for (ext, count) in sortedTypes {
                message += "- **.\(ext)**: \(count) files\n"
            }
            message += "\n"
        }

        // Insights
        if !insights.isEmpty {
            message += "### 💡 What I Learned\n"
            for insight in insights.prefix(5) {
                message += "- **\(insight.title)**: \(insight.description)\n"
            }
            message += "\n"
        }

        // Suggested spaces
        if !suggestedSpaces.isEmpty {
            message += "### ✨ Suggested Spaces\n"
            message += "Based on your work patterns, I recommend creating these Spaces:\n\n"

            for suggestion in suggestedSpaces {
                message += "**\(suggestion.name)**\n"
                message += "_\(suggestion.reason)_\n"
                message += "Suggested agents: \(suggestion.suggestedAgents.joined(separator: ", "))\n\n"
            }

            message += "Say \"**Create [Space Name]**\" to set up any of these, or \"**Create all**\" to set them all up at once."
        }

        let resultMessage = AgentKit.ThreadMessage.assistant(message, agentName: "Concierge")

        appState.workspace.threads[index].messages.append(resultMessage)
        appState.workspace.threads[index].updatedAt = Date()

        await appState.saveThread(appState.workspace.threads[index])
    }

    // MARK: - Actions

    /// Create a suggested space
    public func createSuggestedSpace(_ suggestion: SpaceSuggestion, appState: AppState) async {
        let newSpace = SpaceViewModel(
            id: UUID().uuidString,
            name: suggestion.name,
            description: suggestion.description,
            icon: suggestion.icon,
            color: colorFromName(suggestion.color),
            path: nil,
            channels: []
        )

        appState.spaces.append(newSpace)

        // Remove from suggestions
        suggestedSpaces.removeAll { $0.name == suggestion.name }

        // Post confirmation
        if let threadId = conciergeThreadId,
           let index = appState.workspace.threads.firstIndex(where: { $0.id == threadId }) {
            let confirmMessage = AgentKit.ThreadMessage.assistant(
                "✅ Created **\(suggestion.name)** space! You can find it in the sidebar. Would you like me to invite any agents to help you get started?",
                agentName: "Concierge"
            )
            appState.workspace.threads[index].messages.append(confirmMessage)
            await appState.saveThread(appState.workspace.threads[index])
        }
    }

    private func colorFromName(_ name: SpaceSuggestion.SuggestedColor) -> Color {
        switch name {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .cyan: return .cyan
        case .red: return .red
        case .yellow: return .yellow
        }
    }
}

// MARK: - Supporting Types

/// Log entry for indexing activity
public struct IndexingLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let type: LogType
    public let message: String
    public let detail: String?

    public enum LogType: String, Sendable {
        case directory   // Scanning a directory
        case file        // Found a file
        case insight     // Generated an insight
        case suggestion  // Generated a suggestion
        case complete    // Phase complete
        case info        // General info
    }

    public init(type: LogType, message: String, detail: String? = nil) {
        self.timestamp = Date()
        self.type = type
        self.message = message
        self.detail = detail
    }
}

public struct UserInsight: Identifiable, Sendable {
    public let id = UUID()
    public let type: InsightType
    public let title: String
    public let description: String
    public let confidence: Double

    public enum InsightType: String, Sendable {
        case technology
        case workStyle
        case communication
        case schedule
        case general
    }
}

public struct SpaceSuggestion: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let description: String
    public let icon: String
    public let color: SuggestedColor
    public let reason: String
    public let suggestedAgents: [String]

    public enum SuggestedColor: String, Sendable {
        case blue, purple, green, orange, pink, cyan, red, yellow
    }
}

/// A file discovered during indexing
public struct DiscoveredFile: Identifiable, Sendable {
    public let id = UUID()
    public let url: URL
    public let name: String
    public let category: FileCategory
    public let size: Int64
    public let modifiedDate: Date

    public var relativePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }

    public enum FileCategory: String, Sendable {
        case image
        case document
        case code
        case spreadsheet
        case presentation
        case archive
        case other

        public var icon: String {
            switch self {
            case .image: return "photo"
            case .document: return "doc.text"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .spreadsheet: return "tablecells"
            case .presentation: return "play.rectangle"
            case .archive: return "archivebox"
            case .other: return "doc"
            }
        }
    }

    public static func category(for ext: String) -> FileCategory {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "bmp", "svg":
            return .image
        case "pdf", "doc", "docx", "txt", "rtf", "md", "pages":
            return .document
        case "swift", "ts", "tsx", "js", "jsx", "py", "rs", "go", "java", "c", "cpp", "h", "rb", "sh":
            return .code
        case "xls", "xlsx", "csv", "numbers":
            return .spreadsheet
        case "ppt", "pptx", "key":
            return .presentation
        case "zip", "tar", "gz", "rar", "7z":
            return .archive
        default:
            return .other
        }
    }
}
