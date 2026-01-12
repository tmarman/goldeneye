import Foundation

// MARK: - Capture Processor

/// The CaptureProcessor orchestrates the flow of captured inputs through agent processing.
/// This is the "Concierge" in action - taking raw input, understanding context, and routing appropriately.
///
/// Processing Pipeline:
/// 1. **Intake**: Receive captured input (text, voice, photo)
/// 2. **Context Gathering**: Find relevant calendar events, recent activity
/// 3. **Analysis**: Agent extracts structured data (tasks, learnings, contacts)
/// 4. **Routing Decision**: Determine where content should go (timeline, space, both)
/// 5. **Action Execution**: Create tasks, update spaces, add to timeline
/// 6. **Feedback**: Return result to UI for display
public actor CaptureProcessor {

    // Dependencies
    private let openSpace: OpenSpace
    private weak var spaceManager: SpaceManager?

    // Processing state
    private var processingQueue: [UUID: ProcessingJob] = [:]
    private var processingStrategies: [ProcessingStrategy] = []

    // Configuration
    private var autoLinkToEvents: Bool = true
    private var autoExtractTasks: Bool = true
    private var autoRouteToSpaces: Bool = true

    public init(openSpace: OpenSpace, spaceManager: SpaceManager? = nil) {
        self.openSpace = openSpace
        self.spaceManager = spaceManager

        // Register default strategies inline to avoid actor isolation issue
        processingStrategies = [
            TaskExtractionStrategy(),
            LearningExtractionStrategy(),
            ContactExtractionStrategy(),
            EventLinkingStrategy()
        ]
    }

    // MARK: - Public Interface

    /// Process a captured input through the agent pipeline
    public func process(_ input: CapturedInput) async -> ProcessingResult {
        // Create job for tracking
        let job = ProcessingJob(input: input)
        processingQueue[input.id] = job

        defer { processingQueue.removeValue(forKey: input.id) }

        // Step 1: Gather context
        let context = await gatherContext(for: input)

        // Step 2: Analyze with strategies
        let analysis = await analyzeInput(input, context: context)

        // Step 3: Execute routing decisions
        let result = await executeRouting(input: input, analysis: analysis, context: context)

        // Step 4: Update OpenSpace
        await openSpace.markProcessed(input.id, result: result)

        return result
    }

    /// Process multiple captures in batch (useful for voice memos with multiple points)
    public func processBatch(_ inputs: [CapturedInput]) async -> [ProcessingResult] {
        var results: [ProcessingResult] = []

        for input in inputs {
            let result = await process(input)
            results.append(result)
        }

        return results
    }

    /// Get the current status of a processing job
    public func jobStatus(_ inputId: UUID) -> ProcessingStatus? {
        processingQueue[inputId]?.status
    }

    // MARK: - Context Gathering

    private func gatherContext(for input: CapturedInput) async -> ProcessingContext {
        // Find relevant calendar events (within 2 hours of capture time)
        let nearbyEvents = await findNearbyEvents(around: input.timestamp)

        // Find the current/most recent event
        let currentEvent = nearbyEvents.first { event in
            event.isHappeningNow ||
            (event.endTime < input.timestamp &&
             input.timestamp.timeIntervalSince(event.endTime) < 3600) // Within 1 hour after
        }

        // Get recent timeline items for pattern matching
        let recentItems = await openSpace.items().prefix(20).map { $0 }

        // Gather space context if available
        var availableSpaces: [SpaceID] = []
        if let manager = spaceManager {
            let spaces = await manager.spaces
            availableSpaces = spaces.map { $0.id }
        }

        return ProcessingContext(
            captureTime: input.timestamp,
            nearbyEvents: nearbyEvents,
            currentEvent: currentEvent,
            recentTimelineItems: recentItems,
            availableSpaces: availableSpaces
        )
    }

    private func findNearbyEvents(around date: Date) async -> [CalendarEvent] {
        let window: TimeInterval = 2 * 60 * 60 // 2 hours
        let events = await openSpace.events()

        return events.filter { event in
            let distance = abs(event.startTime.timeIntervalSince(date))
            let endDistance = abs(event.endTime.timeIntervalSince(date))
            return distance < window || endDistance < window ||
                   (event.startTime < date && event.endTime > date)
        }
    }

    // MARK: - Analysis

    private func analyzeInput(_ input: CapturedInput, context: ProcessingContext) async -> ContentAnalysis {
        var analysis = ContentAnalysis()

        // Run each registered strategy
        for strategy in processingStrategies {
            let strategyResult = await strategy.analyze(input: input, context: context)
            analysis.merge(with: strategyResult)
        }

        return analysis
    }

    // MARK: - Routing

    private func executeRouting(
        input: CapturedInput,
        analysis: ContentAnalysis,
        context: ProcessingContext
    ) async -> ProcessingResult {
        // Determine which event to link to (if any)
        var linkedEventId: String?
        if autoLinkToEvents, let event = context.currentEvent {
            linkedEventId = event.id
        } else if let suggestedEvent = analysis.suggestedEventLink {
            linkedEventId = suggestedEvent
        }

        // Determine target space
        var linkedSpaceId: SpaceID?
        if autoRouteToSpaces, let space = analysis.suggestedSpace {
            linkedSpaceId = space
        }

        // Create tasks if extracted
        var createdTasks: [TimelineTask] = []
        if autoExtractTasks {
            for taskTitle in analysis.extractedTasks {
                let task = TimelineTask(
                    title: taskTitle,
                    sourceSpaceId: linkedSpaceId
                )
                createdTasks.append(task)

                // Add task to timeline
                await openSpace.addItem(TimelineItem(
                    type: .task(task),
                    timestamp: Date()
                ))
            }
        }

        return ProcessingResult(
            linkedEventId: linkedEventId,
            linkedSpaceId: linkedSpaceId,
            createdTasks: createdTasks,
            learnings: analysis.extractedLearnings,
            contacts: analysis.extractedContacts,
            followUps: analysis.extractedFollowUps
        )
    }

    // MARK: - Strategy Management

    public func registerStrategy(_ strategy: ProcessingStrategy) {
        processingStrategies.append(strategy)
    }
}

// MARK: - Processing Job

struct ProcessingJob {
    let input: CapturedInput
    var status: ProcessingStatus = .queued
    let startedAt: Date = Date()
    var completedAt: Date?
}

public enum ProcessingStatus: Sendable {
    case queued
    case gatheringContext
    case analyzing
    case routing
    case completed
    case failed(String)
}

// MARK: - Processing Context

public struct ProcessingContext: Sendable {
    public let captureTime: Date
    public let nearbyEvents: [CalendarEvent]
    public let currentEvent: CalendarEvent?
    public let recentTimelineItems: [TimelineItem]
    public let availableSpaces: [SpaceID]

    public init(
        captureTime: Date,
        nearbyEvents: [CalendarEvent],
        currentEvent: CalendarEvent?,
        recentTimelineItems: [TimelineItem],
        availableSpaces: [SpaceID]
    ) {
        self.captureTime = captureTime
        self.nearbyEvents = nearbyEvents
        self.currentEvent = currentEvent
        self.recentTimelineItems = recentTimelineItems
        self.availableSpaces = availableSpaces
    }

    /// Check if content mentions any event by name
    public func findMatchingEvent(for content: String) -> CalendarEvent? {
        let lowercased = content.lowercased()
        return nearbyEvents.first { event in
            lowercased.contains(event.title.lowercased())
        }
    }

    /// Check if content mentions any known space
    public func findMatchingSpace(for content: String, spaces: [Space]) async -> SpaceID? {
        let lowercased = content.lowercased()
        for space in spaces {
            if lowercased.contains(space.name.lowercased()) {
                return space.id
            }
        }
        return nil
    }
}

// MARK: - Content Analysis

public struct ContentAnalysis: Sendable {
    public var extractedTasks: [String] = []
    public var extractedLearnings: [String] = []
    public var extractedContacts: [ExtractedContact] = []
    public var extractedFollowUps: [FollowUp] = []
    public var suggestedEventLink: String?
    public var suggestedSpace: SpaceID?
    public var confidence: Double = 0.0
    public var tags: [String] = []

    public init(
        extractedTasks: [String] = [],
        extractedLearnings: [String] = [],
        extractedContacts: [ExtractedContact] = [],
        extractedFollowUps: [FollowUp] = [],
        suggestedEventLink: String? = nil,
        suggestedSpace: SpaceID? = nil,
        confidence: Double = 0.0,
        tags: [String] = []
    ) {
        self.extractedTasks = extractedTasks
        self.extractedLearnings = extractedLearnings
        self.extractedContacts = extractedContacts
        self.extractedFollowUps = extractedFollowUps
        self.suggestedEventLink = suggestedEventLink
        self.suggestedSpace = suggestedSpace
        self.confidence = confidence
        self.tags = tags
    }

    public mutating func merge(with other: ContentAnalysis) {
        extractedTasks.append(contentsOf: other.extractedTasks)
        extractedLearnings.append(contentsOf: other.extractedLearnings)
        extractedContacts.append(contentsOf: other.extractedContacts)
        extractedFollowUps.append(contentsOf: other.extractedFollowUps)

        // Take the suggestion with higher confidence
        if other.suggestedEventLink != nil && other.confidence > confidence {
            suggestedEventLink = other.suggestedEventLink
        }
        if other.suggestedSpace != nil && other.confidence > confidence {
            suggestedSpace = other.suggestedSpace
        }

        confidence = max(confidence, other.confidence)
        tags.append(contentsOf: other.tags)
    }
}

// MARK: - Processing Strategy Protocol

/// A strategy for analyzing captured content.
/// Multiple strategies can run in parallel to extract different types of information.
public protocol ProcessingStrategy: Sendable {
    var name: String { get }
    func analyze(input: CapturedInput, context: ProcessingContext) async -> ContentAnalysis
}

// MARK: - Default Strategies

/// Extracts tasks from content (looks for action words, "TODO", etc.)
struct TaskExtractionStrategy: ProcessingStrategy {
    let name = "TaskExtraction"

    // Task indicator patterns
    private let taskPatterns = [
        "todo:",
        "task:",
        "need to",
        "should",
        "must",
        "have to",
        "remember to",
        "don't forget",
        "action item:",
        "follow up:",
        "→",  // Arrow often indicates action
        "[ ]", // Checkbox syntax
    ]

    func analyze(input: CapturedInput, context: ProcessingContext) async -> ContentAnalysis {
        var analysis = ContentAnalysis()
        let content = input.content.lowercased()

        // Check for task patterns
        for pattern in taskPatterns {
            if content.contains(pattern) {
                // Extract the task text after the pattern
                if let range = content.range(of: pattern) {
                    let afterPattern = String(content[range.upperBound...])
                    let task = extractTaskText(from: afterPattern)
                    if !task.isEmpty {
                        analysis.extractedTasks.append(task.capitalized)
                    }
                }
            }
        }

        // Also look for bullet points that might be tasks
        let lines = input.content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("* ") {
                let taskText = String(trimmed.dropFirst(2))
                if looksLikeTask(taskText) {
                    analysis.extractedTasks.append(taskText)
                }
            }
        }

        if !analysis.extractedTasks.isEmpty {
            analysis.confidence = 0.7
            analysis.tags.append("has-tasks")
        }

        return analysis
    }

    private func extractTaskText(from text: String) -> String {
        // Take until end of sentence or newline
        let endPatterns: [Character] = [".", "!", "\n"]
        var result = ""
        for char in text {
            if endPatterns.contains(char) {
                break
            }
            result.append(char)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func looksLikeTask(_ text: String) -> Bool {
        let actionWords = ["send", "email", "call", "schedule", "review", "check", "update", "create", "write", "prepare", "finish", "complete", "buy", "get"]
        let lowercased = text.lowercased()
        return actionWords.contains { lowercased.hasPrefix($0) }
    }
}

/// Extracts learnings/insights from content
struct LearningExtractionStrategy: ProcessingStrategy {
    let name = "LearningExtraction"

    private let learningPatterns = [
        "learned that",
        "realized that",
        "key insight:",
        "takeaway:",
        "note to self:",
        "important:",
        "remember:",
        "insight:",
        "til:",
        "til ",
        "aha moment",
    ]

    func analyze(input: CapturedInput, context: ProcessingContext) async -> ContentAnalysis {
        var analysis = ContentAnalysis()
        let content = input.content.lowercased()

        for pattern in learningPatterns {
            if content.contains(pattern) {
                if let range = content.range(of: pattern) {
                    let afterPattern = String(content[range.upperBound...])
                    let learning = extractLearningText(from: afterPattern)
                    if !learning.isEmpty {
                        analysis.extractedLearnings.append(learning)
                    }
                }
            }
        }

        if !analysis.extractedLearnings.isEmpty {
            analysis.confidence = 0.6
            analysis.tags.append("has-learnings")
        }

        return analysis
    }

    private func extractLearningText(from text: String) -> String {
        // Take until end of sentence
        let endPatterns: [Character] = [".", "!", "\n"]
        var result = ""
        for char in text {
            if endPatterns.contains(char) {
                result.append(char)
                break
            }
            result.append(char)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

/// Extracts contact information from content
struct ContactExtractionStrategy: ProcessingStrategy {
    let name = "ContactExtraction"

    func analyze(input: CapturedInput, context: ProcessingContext) async -> ContentAnalysis {
        var analysis = ContentAnalysis()

        // Look for email patterns
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        if let emailRegex = try? NSRegularExpression(pattern: emailPattern),
           let match = emailRegex.firstMatch(in: input.content, range: NSRange(input.content.startIndex..., in: input.content)),
           let range = Range(match.range, in: input.content) {
            let email = String(input.content[range])
            analysis.extractedContacts.append(ExtractedContact(name: "Unknown", email: email))
            analysis.confidence = 0.8
        }

        // Look for phone patterns
        let phonePattern = #"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b"#
        if let phoneRegex = try? NSRegularExpression(pattern: phonePattern),
           let match = phoneRegex.firstMatch(in: input.content, range: NSRange(input.content.startIndex..., in: input.content)),
           let range = Range(match.range, in: input.content) {
            let phone = String(input.content[range])
            // Add to existing contact or create new
            if analysis.extractedContacts.isEmpty {
                analysis.extractedContacts.append(ExtractedContact(name: "Unknown", phone: phone))
            } else {
                analysis.extractedContacts[0] = ExtractedContact(
                    name: analysis.extractedContacts[0].name,
                    email: analysis.extractedContacts[0].email,
                    phone: phone
                )
            }
            analysis.confidence = max(analysis.confidence, 0.7)
        }

        if !analysis.extractedContacts.isEmpty {
            analysis.tags.append("has-contacts")
        }

        return analysis
    }
}

/// Links captures to relevant calendar events
struct EventLinkingStrategy: ProcessingStrategy {
    let name = "EventLinking"

    func analyze(input: CapturedInput, context: ProcessingContext) async -> ContentAnalysis {
        var analysis = ContentAnalysis()

        // If there's a current event (happening now or just ended), link to it
        if let currentEvent = context.currentEvent {
            analysis.suggestedEventLink = currentEvent.id
            analysis.confidence = 0.9
            analysis.tags.append("linked-to-current-event")
            return analysis
        }

        // Otherwise, try to match by event name
        if let matchedEvent = context.findMatchingEvent(for: input.content) {
            analysis.suggestedEventLink = matchedEvent.id
            analysis.confidence = 0.7
            analysis.tags.append("linked-by-name")
        }

        return analysis
    }
}
