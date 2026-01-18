import Foundation

// MARK: - Experience Protocol

/// An Experience transforms underlying OS primitives into a themed presentation.
/// The same task, space, and event data can be presented as professional work management,
/// a fantasy RPG, a space exploration game, or any other metaphor.
public protocol Experience: Identifiable, Sendable {
    var id: ExperienceID { get }
    var name: String { get }
    var description: String { get }
    var theme: ExperienceTheme { get }

    // Transform primitives to experience-specific representations
    func transform(task: AgentTask) -> ExperienceTask
    func transform(space: Space) -> ExperienceSpace
    func transform(event: SystemEvent) -> ExperienceEvent
    func transform(agent: AgentConfiguration) -> ExperienceAgent

    // Gamification hooks (optional)
    func onTaskCompleted(_ task: AgentTask, result: TaskResult) -> [Reward]
    func calculateProgress(for space: Space) -> Progress
    func getAchievements(for userId: String) -> [Achievement]
}

// MARK: - Experience Types

public struct ExperienceID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let workMode = ExperienceID("work-mode")
    public static let questRPG = ExperienceID("quest-rpg")
    public static let spaceExplorer = ExperienceID("space-explorer")
    public static let journal = ExperienceID("journal")
}

public struct ExperienceTheme: Codable, Sendable {
    public var primaryColor: String
    public var secondaryColor: String
    public var backgroundColor: String
    public var accentColor: String
    public var fontFamily: String?
    public var iconSet: String?
    public var backgroundImage: String?
    public var soundscape: String?

    public static let professional = ExperienceTheme(
        primaryColor: "#3B82F6",
        secondaryColor: "#6B7280",
        backgroundColor: "#FFFFFF",
        accentColor: "#10B981"
    )

    public static let fantasy = ExperienceTheme(
        primaryColor: "#8B5CF6",
        secondaryColor: "#D97706",
        backgroundColor: "#1F1D2B",
        accentColor: "#F59E0B",
        fontFamily: "MedievalSharp",
        iconSet: "fantasy",
        backgroundImage: "fantasy-forest",
        soundscape: "tavern-ambience"
    )

    public static let scifi = ExperienceTheme(
        primaryColor: "#06B6D4",
        secondaryColor: "#8B5CF6",
        backgroundColor: "#0F172A",
        accentColor: "#22D3EE",
        fontFamily: "Orbitron",
        iconSet: "scifi",
        backgroundImage: "starfield",
        soundscape: "spaceship-hum"
    )
}

// MARK: - Transformed Types

/// A task transformed through an experience lens
public struct ExperienceTask: Identifiable, Sendable {
    public let id: TaskID
    public let originalTask: AgentTask

    // Experience-specific presentation
    public let title: String
    public let description: String
    public let icon: String
    public let category: String

    // Gamification
    public let difficulty: Difficulty?
    public let rewards: [PotentialReward]?
    public let timeEstimate: String?

    public enum Difficulty: Int, Sendable {
        case trivial = 1
        case easy = 2
        case medium = 3
        case hard = 4
        case epic = 5

        public var stars: String {
            String(repeating: "⭐", count: rawValue)
        }
    }
}

/// A space transformed through an experience lens
public struct ExperienceSpace: Identifiable, Sendable {
    public let id: SpaceID
    public let originalSpace: Space

    // Experience-specific presentation
    public let name: String
    public let description: String
    public let icon: String
    public let visualType: String  // "office", "dungeon", "planet", etc.

    // Progress tracking
    public let progress: Progress?
    public let stats: [Stat]?

    public struct Stat: Sendable {
        public let name: String
        public let value: String
        public let icon: String
    }
}

/// An event transformed through an experience lens
public struct ExperienceEvent: Identifiable, Sendable {
    public let id: String
    public let originalEvent: SystemEvent

    // Experience-specific presentation
    public let title: String
    public let description: String
    public let icon: String
    public let priority: Priority
    public let sound: String?
    public let animation: String?

    public enum Priority: Sendable {
        case ambient       // Background notification
        case notice        // Worth noting
        case important     // Needs attention
        case critical      // Urgent action required
        case celebration   // Achievement/completion
    }
}

/// An agent transformed through an experience lens
public struct ExperienceAgent: Identifiable, Sendable {
    public let id: AgentID
    public let originalConfig: AgentConfiguration

    // Experience-specific presentation
    public let name: String
    public let title: String      // "Research Assistant" or "Sage" or "Science Officer"
    public let avatar: String
    public let description: String

    // Character stats (for gamified experiences)
    public let stats: [String: Int]?  // "wisdom": 15, "speed": 12
    public let specialties: [String]?
}

// MARK: - Gamification Types

public struct Reward: Identifiable, Codable, Sendable {
    public let id: String
    public let type: RewardType
    public let amount: Int
    public let description: String

    public enum RewardType: String, Codable, Sendable {
        case xp = "xp"
        case gold = "gold"
        case item = "item"
        case achievement = "achievement"
        case skillPoint = "skill_point"
        case badge = "badge"
    }
}

public struct PotentialReward: Sendable {
    public let type: Reward.RewardType
    public let amount: Int
    public let probability: Double  // 1.0 = guaranteed
}

public struct Progress: Sendable {
    public let current: Int
    public let total: Int
    public let label: String

    public var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total) * 100
    }

    public var progressBar: String {
        let filled = Int(percentage / 10)
        let empty = 10 - filled
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }
}

public struct Achievement: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let icon: String
    public let rarity: Rarity
    public let unlockedAt: Date?
    public let progress: AchievementProgress?

    public var isUnlocked: Bool { unlockedAt != nil }

    public enum Rarity: String, Codable, Sendable {
        case common
        case uncommon
        case rare
        case epic
        case legendary
    }

    public struct AchievementProgress: Codable, Sendable {
        public let current: Int
        public let required: Int
    }
}

// MARK: - Built-in Experiences

/// Professional work management experience (default)
public struct WorkModeExperience: Experience {
    public let id = ExperienceID.workMode
    public let name = "Work Mode"
    public let description = "Professional task and project management"
    public let theme = ExperienceTheme.professional

    public init() {}

    public func transform(task: AgentTask) -> ExperienceTask {
        ExperienceTask(
            id: task.id,
            originalTask: task,
            title: task.message,
            description: "Task in progress",
            icon: "checklist",
            category: "Task",
            difficulty: nil,
            rewards: nil,
            timeEstimate: nil
        )
    }

    public func transform(space: Space) -> ExperienceSpace {
        ExperienceSpace(
            id: space.id,
            originalSpace: space,
            name: space.name,
            description: space.description ?? "Workspace",
            icon: "folder",
            visualType: "workspace",
            progress: nil,
            stats: nil
        )
    }

    public func transform(event: SystemEvent) -> ExperienceEvent {
        ExperienceEvent(
            id: UUID().uuidString,
            originalEvent: event,
            title: event.title,
            description: event.description,
            icon: "bell",
            priority: .notice,
            sound: nil,
            animation: nil
        )
    }

    public func transform(agent: AgentConfiguration) -> ExperienceAgent {
        ExperienceAgent(
            id: AgentID(),
            originalConfig: agent,
            name: agent.name,
            title: "AI Assistant",
            avatar: "robot",
            description: agent.description,
            stats: nil,
            specialties: nil
        )
    }

    public func onTaskCompleted(_ task: AgentTask, result: TaskResult) -> [Reward] {
        [] // No gamification in work mode
    }

    public func calculateProgress(for space: Space) -> Progress {
        Progress(current: 0, total: 0, label: "Tasks")
    }

    public func getAchievements(for userId: String) -> [Achievement] {
        [] // No achievements in work mode
    }
}

/// Fantasy RPG experience - tasks become quests
public struct QuestRPGExperience: Experience {
    public let id = ExperienceID.questRPG
    public let name = "Quest Mode"
    public let description = "Turn your work into an epic adventure"
    public let theme = ExperienceTheme.fantasy

    public var characterName: String = "Hero"
    public var characterClass: String = "Developer"
    public var level: Int = 1
    public var totalXP: Int = 0

    public init() {}

    public func transform(task: AgentTask) -> ExperienceTask {
        let questType = categorizeTask(task)

        return ExperienceTask(
            id: task.id,
            originalTask: task,
            title: questType.questTitle(for: task.message),
            description: questType.description,
            icon: questType.icon,
            category: questType.rawValue,
            difficulty: questType.difficulty,
            rewards: [
                PotentialReward(type: .xp, amount: questType.baseXP, probability: 1.0),
                PotentialReward(type: .gold, amount: questType.baseXP / 2, probability: 0.8)
            ],
            timeEstimate: nil
        )
    }

    public func transform(space: Space) -> ExperienceSpace {
        let locationType = categorizeSpace(space)

        return ExperienceSpace(
            id: space.id,
            originalSpace: space,
            name: locationType.locationName(for: space.name),
            description: locationType.description,
            icon: locationType.icon,
            visualType: locationType.rawValue,
            progress: Progress(current: 45, total: 100, label: "Exploration"),
            stats: [
                ExperienceSpace.Stat(name: "Quests Completed", value: "12", icon: "scroll"),
                ExperienceSpace.Stat(name: "Treasures Found", value: "8", icon: "gem"),
            ]
        )
    }

    public func transform(event: SystemEvent) -> ExperienceEvent {
        ExperienceEvent(
            id: UUID().uuidString,
            originalEvent: event,
            title: "📜 " + event.title,
            description: event.description,
            icon: "scroll",
            priority: .notice,
            sound: "quest-notification",
            animation: "sparkle"
        )
    }

    public func transform(agent: AgentConfiguration) -> ExperienceAgent {
        let archetype = categorizeAgent(agent)

        return ExperienceAgent(
            id: AgentID(),
            originalConfig: agent,
            name: archetype.name(for: agent.name),
            title: archetype.title,
            avatar: archetype.avatar,
            description: archetype.description,
            stats: archetype.stats,
            specialties: archetype.specialties
        )
    }

    public func onTaskCompleted(_ task: AgentTask, result: TaskResult) -> [Reward] {
        let questType = categorizeTask(task)
        var rewards: [Reward] = []

        // Base XP reward
        rewards.append(Reward(
            id: UUID().uuidString,
            type: .xp,
            amount: questType.baseXP,
            description: "Quest completed!"
        ))

        // Bonus gold
        if Bool.random() {
            rewards.append(Reward(
                id: UUID().uuidString,
                type: .gold,
                amount: questType.baseXP / 2,
                description: "Bonus loot!"
            ))
        }

        return rewards
    }

    public func calculateProgress(for space: Space) -> Progress {
        // Calculate based on completed vs total tasks
        Progress(current: 45, total: 100, label: "to next level")
    }

    public func getAchievements(for userId: String) -> [Achievement] {
        [
            Achievement(
                id: "first_quest",
                name: "First Steps",
                description: "Complete your first quest",
                icon: "🏆",
                rarity: .common,
                unlockedAt: Date(),
                progress: nil
            ),
            Achievement(
                id: "bug_slayer",
                name: "Bug Slayer",
                description: "Defeat 100 bugs",
                icon: "🐛",
                rarity: .rare,
                unlockedAt: nil,
                progress: Achievement.AchievementProgress(current: 47, required: 100)
            ),
            Achievement(
                id: "code_wizard",
                name: "Code Wizard",
                description: "Write 10,000 lines of code",
                icon: "🧙",
                rarity: .epic,
                unlockedAt: nil,
                progress: Achievement.AchievementProgress(current: 7500, required: 10000)
            )
        ]
    }

    // MARK: - Private Categorization

    private enum QuestType: String {
        case bugHunt = "Bug Hunt"
        case feature = "Feature Quest"
        case refactor = "Training"
        case documentation = "Lore Writing"
        case review = "Council Review"
        case research = "Exploration"

        var icon: String {
            switch self {
            case .bugHunt: return "🐛"
            case .feature: return "⚔️"
            case .refactor: return "🏋️"
            case .documentation: return "📜"
            case .review: return "👁️"
            case .research: return "🔮"
            }
        }

        var description: String {
            switch self {
            case .bugHunt: return "Track and eliminate the bug creature"
            case .feature: return "Forge a new capability"
            case .refactor: return "Strengthen the foundations"
            case .documentation: return "Record the ancient knowledge"
            case .review: return "Seek wisdom from the council"
            case .research: return "Explore the unknown"
            }
        }

        var difficulty: ExperienceTask.Difficulty {
            switch self {
            case .bugHunt: return .medium
            case .feature: return .hard
            case .refactor: return .easy
            case .documentation: return .trivial
            case .review: return .easy
            case .research: return .medium
            }
        }

        var baseXP: Int {
            switch self {
            case .bugHunt: return 50
            case .feature: return 100
            case .refactor: return 30
            case .documentation: return 20
            case .review: return 25
            case .research: return 40
            }
        }

        func questTitle(for original: String) -> String {
            switch self {
            case .bugHunt: return "🐛 Slay the \(original.prefix(30)) Bug"
            case .feature: return "⚔️ Forge: \(original.prefix(30))"
            case .refactor: return "🏋️ Training: \(original.prefix(30))"
            case .documentation: return "📜 Chronicle: \(original.prefix(30))"
            case .review: return "👁️ Council Review: \(original.prefix(30))"
            case .research: return "🔮 Explore: \(original.prefix(30))"
            }
        }
    }

    private func categorizeTask(_ task: AgentTask) -> QuestType {
        let message = task.message.lowercased()
        if message.contains("bug") || message.contains("fix") || message.contains("error") {
            return .bugHunt
        } else if message.contains("add") || message.contains("implement") || message.contains("create") {
            return .feature
        } else if message.contains("refactor") || message.contains("clean") || message.contains("improve") {
            return .refactor
        } else if message.contains("doc") || message.contains("readme") || message.contains("comment") {
            return .documentation
        } else if message.contains("review") || message.contains("check") {
            return .review
        } else {
            return .research
        }
    }

    private enum LocationType: String {
        case castle = "Castle"
        case dungeon = "Dungeon"
        case library = "Library"
        case forge = "Forge"
        case wilderness = "Wilderness"

        var icon: String {
            switch self {
            case .castle: return "🏰"
            case .dungeon: return "🕳️"
            case .library: return "📚"
            case .forge: return "⚒️"
            case .wilderness: return "🌲"
            }
        }

        var description: String {
            switch self {
            case .castle: return "Your main stronghold"
            case .dungeon: return "A dark place full of bugs"
            case .library: return "Repository of knowledge"
            case .forge: return "Where features are crafted"
            case .wilderness: return "Unexplored territory"
            }
        }

        func locationName(for original: String) -> String {
            "\(icon) \(original) \(rawValue)"
        }
    }

    private func categorizeSpace(_ space: Space) -> LocationType {
        let name = space.name.lowercased()
        if name.contains("main") || name.contains("personal") {
            return .castle
        } else if name.contains("bug") || name.contains("issue") {
            return .dungeon
        } else if name.contains("doc") || name.contains("wiki") {
            return .library
        } else if name.contains("feature") || name.contains("dev") {
            return .forge
        } else {
            return .wilderness
        }
    }

    private enum AgentArchetype {
        case sage
        case warrior
        case artisan
        case scout

        var title: String {
            switch self {
            case .sage: return "Sage"
            case .warrior: return "Code Knight"
            case .artisan: return "Artisan"
            case .scout: return "Scout"
            }
        }

        var avatar: String {
            switch self {
            case .sage: return "🧙"
            case .warrior: return "⚔️"
            case .artisan: return "🛠️"
            case .scout: return "🔍"
            }
        }

        var description: String {
            switch self {
            case .sage: return "Master of ancient code knowledge"
            case .warrior: return "Champion of bug battles"
            case .artisan: return "Crafter of fine features"
            case .scout: return "Explorer of unknown territories"
            }
        }

        var stats: [String: Int] {
            switch self {
            case .sage: return ["wisdom": 18, "speed": 10, "strength": 8]
            case .warrior: return ["wisdom": 12, "speed": 14, "strength": 16]
            case .artisan: return ["wisdom": 14, "speed": 12, "strength": 12]
            case .scout: return ["wisdom": 10, "speed": 18, "strength": 8]
            }
        }

        var specialties: [String] {
            switch self {
            case .sage: return ["Research", "Analysis", "Documentation"]
            case .warrior: return ["Bug Fixing", "Testing", "Debugging"]
            case .artisan: return ["Feature Building", "UI/UX", "Architecture"]
            case .scout: return ["Code Review", "Exploration", "Discovery"]
            }
        }

        func name(for original: String) -> String {
            "\(original) the \(title)"
        }
    }

    private func categorizeAgent(_ config: AgentConfiguration) -> AgentArchetype {
        let name = config.name.lowercased()
        if name.contains("research") || name.contains("analyze") {
            return .sage
        } else if name.contains("test") || name.contains("debug") || name.contains("fix") {
            return .warrior
        } else if name.contains("build") || name.contains("create") || name.contains("design") {
            return .artisan
        } else {
            return .scout
        }
    }
}

// MARK: - Experience Manager

/// Manages active experiences and switches between them
public actor ExperienceManager {
    public static let shared = ExperienceManager()

    private var registeredExperiences: [ExperienceID: any Experience] = [:]
    private var activeExperience: ExperienceID = .workMode
    private var userPreferences: [String: ExperienceID] = [:]

    private init() {
        // Register built-in experiences
        register(WorkModeExperience())
        register(QuestRPGExperience())
    }

    public func register(_ experience: some Experience) {
        registeredExperiences[experience.id] = experience
    }

    public func setActive(_ experienceId: ExperienceID, for userId: String? = nil) {
        if let userId {
            userPreferences[userId] = experienceId
        } else {
            activeExperience = experienceId
        }
    }

    public func getActive(for userId: String? = nil) -> (any Experience)? {
        let id = userId.flatMap { userPreferences[$0] } ?? activeExperience
        return registeredExperiences[id]
    }

    public func availableExperiences() -> [any Experience] {
        Array(registeredExperiences.values)
    }
}

// MARK: - Extension for SystemEvent

extension SystemEvent {
    var title: String {
        switch self {
        case .agentSpawned: return "Agent Started"
        case .agentTerminated: return "Agent Finished"
        case .decisionCardCreated: return "New Decision"
        case .decisionCardMerged: return "Decision Approved"
        case .taskCompleted: return "Task Complete"
        default: return "Event"
        }
    }

    var description: String {
        switch self {
        case .agentSpawned(let id): return "Agent \(id) has started"
        case .agentTerminated(let id, _): return "Agent \(id) has finished"
        case .decisionCardCreated(let id): return "Decision \(id) needs review"
        case .decisionCardMerged(let id): return "Decision \(id) was approved"
        case .taskCompleted(let id): return "Task \(id) completed successfully"
        default: return "An event occurred"
        }
    }
}
