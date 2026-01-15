import AgentKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Haptic & Sound Feedback

/// Centralized feedback manager for haptic and sound effects
enum FeedbackManager {
    // MARK: - Haptic Feedback

    /// Perform haptic feedback on trackpad
    static func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    /// Light tap feedback for selections and toggles
    static func selectionChanged() {
        haptic(.levelChange)
    }

    /// Confirmation feedback for successful actions
    static func success() {
        haptic(.alignment)
    }

    /// Warning feedback for destructive or important actions
    static func warning() {
        haptic(.generic)
    }

    // MARK: - Sound Feedback

    /// Play system sound for common actions
    static func playSound(_ sound: SystemSound) {
        NSSound(named: sound.soundName)?.play()
    }

    /// System sounds available on macOS
    enum SystemSound: String {
        case send = "Morse"         // Message sent
        case receive = "Pop"        // Message received
        case success = "Glass"      // Action completed
        case error = "Basso"        // Error occurred
        case delete = "Funk"        // Item deleted
        case archive = "Submarine"  // Item archived
        case notification = "Blow"  // Alert

        var soundName: NSSound.Name {
            NSSound.Name(rawValue)
        }
    }

    // MARK: - Combined Feedback

    /// Feedback for sending a message
    static func messageSent() {
        haptic(.alignment)
        playSound(.send)
    }

    /// Feedback for receiving a response
    static func messageReceived() {
        haptic(.levelChange)
        playSound(.receive)
    }

    /// Feedback for deleting an item
    static func itemDeleted() {
        haptic(.generic)
        playSound(.delete)
    }

    /// Feedback for archiving an item
    static func itemArchived() {
        haptic(.alignment)
        playSound(.archive)
    }

    /// Feedback for starring/pinning
    static func itemFavorited() {
        haptic(.levelChange)
    }

    /// Feedback for copying to clipboard
    static func copied() {
        haptic(.alignment)
    }

    /// Feedback for errors
    static func error() {
        haptic(.generic)
        playSound(.error)
    }
}

// MARK: - View Extension for Feedback

extension View {
    /// Add haptic feedback on tap
    func hapticOnTap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                FeedbackManager.haptic(pattern)
            }
        )
    }
}

// MARK: - App Color Theme

extension Color {
    /// Semantic colors for consistent theming
    enum Envoy {
        // Status colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue

        // Role colors
        static let model = Color.orange
        static let agent = Color.purple
        static let user = Color.accentColor

        // UI element colors
        static let pin = Color.orange
        static let star = Color.yellow
        static let archive = Color.indigo

        // Backgrounds
        static let subtleBackground = Color(.controlBackgroundColor)
        static let elevatedBackground = Color(.windowBackgroundColor)
    }
}

// MARK: - Typography System

extension Font {
    /// Semantic typography for consistent text styling
    enum Envoy {
        // Headings
        static let pageTitle = Font.title2.weight(.semibold)
        static let sectionTitle = Font.headline.weight(.semibold)
        static let cardTitle = Font.subheadline.weight(.medium)

        // Body text
        static let bodyPrimary = Font.body
        static let bodySecondary = Font.callout

        // Supporting text
        static let caption = Font.caption
        static let captionSmall = Font.caption2
        static let meta = Font.caption2.weight(.medium)

        // Special
        static let code = Font.system(.body, design: .monospaced)
        static let codeSmall = Font.system(.caption, design: .monospaced)
    }
}

// MARK: - Spacing System

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Conversations View

// MARK: - Conversation Filter

enum ConversationFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case agents = "Agents"  // Primary focus - agent-centric design
    case starred = "Starred"
    case archived = "Archived"
    // Note: "Models" filter removed per agent-centric design philosophy
    // Agents are the interaction point, not models

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .agents: return "sparkles"  // AI/agent icon
        case .starred: return "star"
        case .archived: return "archivebox"
        }
    }
}

// MARK: - Date Grouping Types

enum DateGroup: Int, CaseIterable, Hashable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case older

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .lastWeek: return "Last Week"
        case .thisMonth: return "This Month"
        case .older: return "Older"
        }
    }

    static func from(_ date: Date) -> DateGroup {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return .today
        } else if calendar.isDateInYesterday(date) {
            return .yesterday
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                  date > weekAgo {
            return .thisWeek
        } else if let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now),
                  date > twoWeeksAgo {
            return .lastWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return .thisMonth
        } else {
            return .older
        }
    }
}

struct ConversationDateGroup: Hashable {
    let dateGroup: DateGroup
    let conversations: [Conversation]

    func hash(into hasher: inout Hasher) {
        hasher.combine(dateGroup)
    }

    static func == (lhs: ConversationDateGroup, rhs: ConversationDateGroup) -> Bool {
        lhs.dateGroup == rhs.dateGroup
    }
}

struct ConversationsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(ChatService.self) private var chatService
    @Environment(ProviderConfigManager.self) private var providerManager
    @State private var searchText = ""
    @State private var selectedFilter: ConversationFilter = .all

    var filteredConversations: [Conversation] {
        var conversations = appState.workspace.conversations

        // Apply agent DM filter first (when coming from Direct Messages)
        if let agentName = appState.selectedAgentFilter {
            conversations = conversations.filter { $0.agentName == agentName }
        }

        // Apply filter (agent-centric design - no models filter)
        switch selectedFilter {
        case .all:
            // Exclude archived from "All" view
            conversations = conversations.filter { !$0.isArchived }
        case .agents:
            // Show agent conversations (includes model-powered agents)
            conversations = conversations.filter { ($0.agentName != nil || $0.modelId != nil) && !$0.isArchived }
        case .starred:
            conversations = conversations.filter { $0.isStarred && !$0.isArchived }
        case .archived:
            conversations = conversations.filter { $0.isArchived }
        }

        // Apply search
        if !searchText.isEmpty {
            conversations = conversations.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
            }
        }

        return conversations
    }

    private var filterCounts: [ConversationFilter: Int] {
        let all = appState.workspace.conversations
        let nonArchived = all.filter { !$0.isArchived }
        return [
            .all: nonArchived.count,
            // Agents includes all AI-powered conversations (agent-centric design)
            .agents: nonArchived.filter { $0.agentName != nil || $0.modelId != nil }.count,
            .starred: nonArchived.filter { $0.isStarred }.count,
            .archived: all.filter { $0.isArchived }.count
        ]
    }

    /// Navigation title - shows agent name when filtering by DM
    private var agentFilterTitle: String {
        if let agentName = appState.selectedAgentFilter {
            return "Threads with \(agentName)"
        }
        return "Conversations"
    }

    var body: some View {
        HSplitView {
            // Conversation list
            conversationList
                .frame(minWidth: 250, maxWidth: 350)

            // Selected conversation detail
            if let selectedId = appState.selectedConversationId,
               let conversation = appState.workspace.conversations.first(where: { $0.id == selectedId }) {
                ConversationDetailView(conversation: conversation)
            } else {
                EmptyConversationDetailView()
            }
        }
        .navigationTitle(agentFilterTitle)
        .searchable(text: $searchText, prompt: "Search conversations...")
        .toolbar {
            // Clear agent filter button (when filtering by agent DM)
            if appState.selectedAgentFilter != nil {
                ToolbarItem(placement: .navigation) {
                    Button(action: { appState.selectedAgentFilter = nil }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Clear Filter")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            ToolbarItem {
                Button(action: { appState.showNewConversationSheet = true }) {
                    Label("New Conversation", systemImage: "plus")
                }
            }
        }
        .onKeyPress(.upArrow) {
            selectPreviousConversation()
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectNextConversation()
            return .handled
        }
        .onKeyPress(.delete) {
            if appState.selectedConversationId != nil {
                // Trigger delete confirmation
                NotificationCenter.default.post(name: .deleteSelectedConversation, object: nil)
            }
            return .handled
        }
    }

    private func selectNextConversation() {
        let conversations = filteredConversations
        guard !conversations.isEmpty else { return }

        if let currentId = appState.selectedConversationId,
           let currentIndex = conversations.firstIndex(where: { $0.id == currentId }) {
            let nextIndex = min(currentIndex + 1, conversations.count - 1)
            appState.selectedConversationId = conversations[nextIndex].id
        } else {
            appState.selectedConversationId = conversations.first?.id
        }
    }

    private func selectPreviousConversation() {
        let conversations = filteredConversations
        guard !conversations.isEmpty else { return }

        if let currentId = appState.selectedConversationId,
           let currentIndex = conversations.firstIndex(where: { $0.id == currentId }) {
            let prevIndex = max(currentIndex - 1, 0)
            appState.selectedConversationId = conversations[prevIndex].id
        } else {
            appState.selectedConversationId = conversations.last?.id
        }
    }

    private func deleteConversation(_ conversation: Conversation) {
        FeedbackManager.itemDeleted()
        withAnimation {
            appState.workspace.conversations.removeAll { $0.id == conversation.id }
            if appState.selectedConversationId == conversation.id {
                appState.selectedConversationId = nil
            }
        }
    }

    private func togglePin(_ conversation: Conversation) {
        if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
            FeedbackManager.itemFavorited()
            withAnimation {
                appState.workspace.conversations[index].isPinned.toggle()
            }
        }
    }

    private func toggleStar(_ conversation: Conversation) {
        if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
            FeedbackManager.itemFavorited()
            withAnimation {
                appState.workspace.conversations[index].isStarred.toggle()
            }
        }
    }

    private func toggleArchive(_ conversation: Conversation) {
        if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
            FeedbackManager.itemArchived()
            withAnimation(.easeInOut(duration: 0.3)) {
                appState.workspace.conversations[index].isArchived.toggle()
                // Deselect if archiving the selected conversation
                if appState.workspace.conversations[index].isArchived &&
                   appState.selectedConversationId == conversation.id {
                    appState.selectedConversationId = nil
                }
            }
        }
    }

    @ViewBuilder
    private func conversationContextMenu(for conversation: Conversation) -> some View {
        Button(action: { togglePin(conversation) }) {
            Label(conversation.isPinned ? "Unpin" : "Pin",
                  systemImage: conversation.isPinned ? "pin.slash" : "pin")
        }

        Button(action: { toggleStar(conversation) }) {
            Label(conversation.isStarred ? "Remove Star" : "Add Star",
                  systemImage: conversation.isStarred ? "star.slash" : "star")
        }

        Divider()

        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(conversation.title, forType: .string)
        }) {
            Label("Copy Title", systemImage: "doc.on.doc")
        }

        Divider()

        Button(action: { toggleArchive(conversation) }) {
            Label(conversation.isArchived ? "Unarchive" : "Archive",
                  systemImage: conversation.isArchived ? "tray.and.arrow.up" : "archivebox")
        }

        Button(role: .destructive, action: { deleteConversation(conversation) }) {
            Label("Delete", systemImage: "trash")
        }
    }

    private var conversationList: some View {
        Group {
            if appState.workspace.conversations.isEmpty {
                // Empty state for no conversations
                EmptyConversationListView()
            } else {
                VStack(spacing: 0) {
                    // Filter chips
                    filterChipsView
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    Divider()

                    // Conversation list
                    List(selection: $appState.selectedConversationId) {
                        if !filteredConversations.filter({ $0.isPinned }).isEmpty {
                            Section("Pinned") {
                                ForEach(filteredConversations.filter { $0.isPinned }) { conversation in
                                    ConversationRow(conversation: conversation)
                                        .tag(conversation.id)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                deleteConversation(conversation)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }

                                            Button {
                                                toggleArchive(conversation)
                                            } label: {
                                                Label(conversation.isArchived ? "Unarchive" : "Archive",
                                                      systemImage: conversation.isArchived ? "tray.and.arrow.up" : "archivebox")
                                            }
                                            .tint(.indigo)
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                togglePin(conversation)
                                            } label: {
                                                Label("Unpin", systemImage: "pin.slash")
                                            }
                                            .tint(.orange)
                                        }
                                        .contextMenu {
                                            conversationContextMenu(for: conversation)
                                        }
                                }
                            }
                        }

                        if filteredConversations.isEmpty {
                            // No results for current filter
                            noResultsView
                        } else {
                            // Group unpinned conversations by date
                            ForEach(groupedConversations, id: \.dateGroup) { group in
                                Section(group.dateGroup.displayName) {
                                    ForEach(group.conversations) { conversation in
                                        ConversationRow(conversation: conversation)
                                            .tag(conversation.id)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) {
                                                    deleteConversation(conversation)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }

                                                Button {
                                                    toggleArchive(conversation)
                                                } label: {
                                                    Label(conversation.isArchived ? "Unarchive" : "Archive",
                                                          systemImage: conversation.isArchived ? "tray.and.arrow.up" : "archivebox")
                                                }
                                                .tint(.indigo)
                                            }
                                            .swipeActions(edge: .leading) {
                                                Button {
                                                    togglePin(conversation)
                                                } label: {
                                                    Label("Pin", systemImage: "pin")
                                                }
                                                .tint(.orange)

                                                Button {
                                                    toggleStar(conversation)
                                                } label: {
                                                    Label(conversation.isStarred ? "Unstar" : "Star",
                                                          systemImage: conversation.isStarred ? "star.slash" : "star")
                                                }
                                                .tint(.yellow)
                                            }
                                            .contextMenu {
                                                conversationContextMenu(for: conversation)
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.workspace.conversations.count)
    }

    // MARK: - Date Grouping

    private var groupedConversations: [ConversationDateGroup] {
        let unpinned = filteredConversations.filter { !$0.isPinned }
        var groups: [DateGroup: [Conversation]] = [:]

        for conversation in unpinned {
            let group = DateGroup.from(conversation.updatedAt)
            groups[group, default: []].append(conversation)
        }

        // Sort groups by date (most recent first) and return
        return DateGroup.allCases.compactMap { group in
            guard let conversations = groups[group], !conversations.isEmpty else { return nil }
            return ConversationDateGroup(dateGroup: group, conversations: conversations)
        }
    }

    private var filterChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ConversationFilter.allCases) { filter in
                    FilterChip(
                        filter: filter,
                        count: filterCounts[filter] ?? 0,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 4) // Extra padding to prevent edge clipping
        }
        .frame(height: 36) // Fixed height to ensure visibility
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)

            Text("No conversations found")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if selectedFilter != .all {
                Button("Show All") {
                    withAnimation {
                        selectedFilter = .all
                        searchText = ""
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let filter: ConversationFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: 10))
                    .symbolEffect(.bounce, value: isSelected)
                Text(filter.rawValue)
                    .font(.caption)
                if count > 0 && filter != .all {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Skeleton Loading Views

/// Skeleton placeholder for conversation row
struct ConversationRowSkeleton: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Avatar skeleton
            Circle()
                .fill(Color(.separatorColor).opacity(0.3))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.separatorColor).opacity(0.3))
                    .frame(width: 140, height: 14)

                // Preview skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.separatorColor).opacity(0.2))
                    .frame(height: 12)

                // Meta row skeleton
                HStack {
                    Capsule()
                        .fill(Color(.separatorColor).opacity(0.2))
                        .frame(width: 60, height: 16)

                    Spacer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.separatorColor).opacity(0.15))
                        .frame(width: 40, height: 10)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
        .shimmer()
    }
}

/// Skeleton for conversation list (multiple rows)
struct ConversationListSkeleton: View {
    let rowCount: Int

    init(rowCount: Int = 5) {
        self.rowCount = rowCount
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { _ in
                ConversationRowSkeleton()
                    .padding(.horizontal, Spacing.md)
                Divider()
                    .padding(.leading, 56)
            }
        }
    }
}

/// Skeleton for message bubble
struct MessageBubbleSkeleton: View {
    let isUser: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.md) {
            if isUser {
                Spacer(minLength: 80)
            }

            if !isUser {
                Circle()
                    .fill(Color(.separatorColor).opacity(0.2))
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.xs) {
                if !isUser {
                    // Model info skeleton
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.separatorColor).opacity(0.2))
                            .frame(width: 80, height: 10)
                    }
                }

                // Message content skeleton
                RoundedRectangle(cornerRadius: 20)
                    .fill(isUser ? Color.accentColor.opacity(0.2) : Color(.separatorColor).opacity(0.2))
                    .frame(width: isUser ? 150 : 220, height: isUser ? 40 : 60)

                // Timestamp skeleton
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.separatorColor).opacity(0.1))
                    .frame(width: 40, height: 8)
            }

            if isUser {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .shimmer()
    }
}

/// Skeleton for chat view (alternating messages)
struct ChatSkeleton: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            MessageBubbleSkeleton(isUser: true)
            MessageBubbleSkeleton(isUser: false)
            MessageBubbleSkeleton(isUser: true)
        }
        .padding()
    }
}

/// Loading indicator with optional message
struct LoadingIndicator: View {
    let message: String
    @State private var rotation: Double = 0

    init(_ message: String = "Loading...") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 3)
                    .frame(width: 40, height: 40)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(rotation))
            }
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }

            Text(message)
                .font(Font.Envoy.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Pulsing dots loading indicator
struct PulsingDotsLoader: View {
    @State private var animationPhase = 0.0

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseScale(for: index))
                    .opacity(pulseOpacity(for: index))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                animationPhase = 1.0
            }
        }
    }

    private func pulseScale(for index: Int) -> Double {
        let offset = Double(index) * 0.2
        let phase = (animationPhase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.6 + (0.4 * sin(phase * .pi))
    }

    private func pulseOpacity(for index: Int) -> Double {
        let offset = Double(index) * 0.2
        let phase = (animationPhase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.4 + (0.6 * sin(phase * .pi))
    }
}

// MARK: - Empty State Illustrations

/// Reusable illustrated empty state component
struct IllustratedEmptyState: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let actionLabel: String?
    let action: (() -> Void)?

    @State private var isAnimating = false
    @State private var floatOffset: CGFloat = 0

    init(
        icon: String,
        iconColor: Color = .accentColor,
        title: String,
        subtitle: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Illustrated icon with floating animation
            illustrationView
                .offset(y: floatOffset)

            // Text content
            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Font.Envoy.sectionTitle)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(Font.Envoy.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            // Action button
            if let label = actionLabel, let action = action {
                Button(action: action) {
                    Label(label, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            Spacer()
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                floatOffset = -8
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }

    private var illustrationView: some View {
        ZStack {
            // Background decorative circles
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(iconColor.opacity(0.05 + Double(index) * 0.03), lineWidth: 1.5)
                    .frame(width: CGFloat(100 + index * 30), height: CGFloat(100 + index * 30))
                    .scaleEffect(isAnimating ? 1.0 : 0.95)
                    .animation(
                        .easeInOut(duration: 2.0 + Double(index) * 0.3)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }

            // Main icon container
            ZStack {
                // Glow effect
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 90, height: 90)
                    .blur(radius: 20)

                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [iconColor.opacity(0.2), iconColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                // Icon
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(iconColor)
                    .symbolEffect(.pulse, options: .speed(0.5), isActive: isAnimating)
            }
        }
    }
}

/// Empty state for archived conversations
struct EmptyArchivedState: View {
    var body: some View {
        IllustratedEmptyState(
            icon: "archivebox",
            iconColor: Color.Envoy.archive,
            title: "No Archived Conversations",
            subtitle: "Conversations you archive will appear here. Swipe left or use the context menu to archive."
        )
    }
}

/// Empty state for starred conversations
struct EmptyStarredState: View {
    var body: some View {
        IllustratedEmptyState(
            icon: "star",
            iconColor: Color.Envoy.star,
            title: "No Starred Conversations",
            subtitle: "Star your favorite conversations to find them quickly. Use the context menu or swipe to star."
        )
    }
}

/// Empty state for search results
struct EmptySearchResultsState: View {
    let searchQuery: String

    var body: some View {
        IllustratedEmptyState(
            icon: "magnifyingglass",
            iconColor: .secondary,
            title: "No Results Found",
            subtitle: "No conversations match \"\(searchQuery)\". Try a different search term."
        )
    }
}

// MARK: - Empty Conversation List View

struct EmptyConversationListView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(ChatService.self) private var chatService

    var body: some View {
        IllustratedEmptyState(
            icon: "bubble.left.and.bubble.right",
            iconColor: .accentColor,
            title: "No Conversations Yet",
            subtitle: chatService.isReady
                ? "Start a chat with your AI model to get started"
                : "Select a model first to begin chatting",
            actionLabel: chatService.isReady ? "New Chat" : "Select Model",
            action: chatService.isReady
                ? { appState.showNewConversationSheet = true }
                : { appState.showModelPicker = true }
        )
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    @Environment(ChatService.self) private var chatService
    @State private var isHovered = false

    private var messageCount: Int {
        conversation.messages.count
    }

    private var lastMessageRole: String? {
        conversation.messages.last?.role.rawValue
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Avatar/Icon with hover scale
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(isHovered ? 0.25 : 0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: avatarIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(avatarColor)
                    .scaleEffect(isHovered ? 1.1 : 1.0)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)

            // Content - Slack-like left-aligned layout with clear hierarchy
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Title row with agent/model name (Slack-style)
                HStack(spacing: Spacing.sm) {
                    // Title + Agent in one line
                    HStack(spacing: Spacing.sm) {
                        Text(conversation.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        // Agent/Model name inline (like Slack shows app name)
                        Text(modelOrAgentName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(avatarColor)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Timestamp (prominent like Slack)
                    Text(conversation.updatedAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                // Preview text with better contrast
                Text(conversation.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Bottom row: badges + message count
                HStack(spacing: Spacing.sm) {
                    // Badges with subtle animation
                    HStack(spacing: Spacing.xs) {
                        if conversation.isArchived {
                            Image(systemName: "archivebox.fill")
                                .foregroundStyle(Color.Envoy.archive)
                                .font(.caption2)
                        }
                        if conversation.isPinned {
                            Image(systemName: "pin.fill")
                                .foregroundStyle(Color.Envoy.pin)
                                .font(.caption2)
                                .symbolEffect(.pulse, options: .speed(0.5), isActive: isHovered)
                        }
                        if conversation.isStarred {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.Envoy.star)
                                .font(.caption2)
                                .symbolEffect(.pulse, options: .speed(0.5), isActive: isHovered)
                        }
                    }

                    Spacer()

                    // Message count
                    if messageCount > 0 {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 8))
                            Text("\(messageCount)")
                        }
                        .font(Font.Envoy.captionSmall)
                        .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var avatarIcon: String {
        if conversation.modelId != nil {
            return "sparkles"  // AI/model icon (Apple Intelligence style)
        } else if conversation.agentName != nil {
            return "sparkles"  // Agent icon
        }
        return "bubble.left.and.bubble.right"
    }

    private var avatarColor: Color {
        if conversation.modelId != nil {
            return Color.Envoy.model
        } else if conversation.agentName != nil {
            return Color.Envoy.agent
        }
        return Color.Envoy.info
    }

    private var modelOrAgentName: String {
        if let modelId = conversation.modelId {
            return shortModelName(modelId)
        } else if let agentName = conversation.agentName {
            return agentName
        }
        return "Chat"
    }

    private func shortModelName(_ modelId: String) -> String {
        modelId.components(separatedBy: "/").last ?? modelId
    }
}

// MARK: - Conversation Detail View

struct ConversationDetailView: View {
    let conversation: Conversation
    @EnvironmentObject private var appState: AppState
    @Environment(ChatService.self) private var chatService
    @Environment(ProviderConfigManager.self) private var providerManager
    @State private var newMessage = ""
    @State private var isLoading = false
    @State private var streamingResponse = ""
    @State private var errorMessage: String?
    @State private var showRenameAlert = false
    @State private var newTitle = ""
    @State private var showDeleteConfirmation = false
    @State private var showModelPicker = false
    @State private var showExportSheet = false
    @State private var showStats = false

    // Determine if this conversation uses direct model or A2A
    private var usesDirectModel: Bool {
        conversation.modelId != nil || conversation.providerId != nil
    }

    // Check if we can send messages
    private var canSendMessages: Bool {
        if usesDirectModel {
            return chatService.isReady
        } else {
            return appState.isAgentConnected
        }
    }

    private var connectionStatusText: String {
        if usesDirectModel {
            if chatService.isLoadingModel {
                return "Loading model..."
            } else if chatService.isReady {
                return chatService.providerDescription
            } else {
                return "No model selected"
            }
        } else {
            if appState.isAgentConnected {
                return conversation.agentName ?? "Connected"
            } else {
                return "Disconnected"
            }
        }
    }

    private var connectionStatusColor: Color {
        if usesDirectModel {
            return chatService.isReady ? .green : (chatService.isLoadingModel ? .orange : .gray)
        } else {
            return appState.isAgentConnected ? .green : .orange
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with model/agent selector
            headerView

            Divider()

            // Error banner
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        errorMessage = nil
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(.orange.opacity(0.1))
            }

            // Statistics panel (collapsible)
            if showStats && !conversation.messages.isEmpty {
                ConversationStatsView(conversation: conversation)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Welcome message for empty conversations
                        if conversation.messages.isEmpty {
                            WelcomeMessageView(
                                modelName: chatService.providerDescription,
                                isDirectModel: usesDirectModel,
                                agentName: conversation.agentName,
                                onPromptSelected: { prompt in
                                    newMessage = prompt
                                }
                            )
                        }

                        ForEach(conversation.messages) { message in
                            ConversationMessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming response
                        if isLoading && !streamingResponse.isEmpty {
                            StreamingMessageView(content: streamingResponse, modelName: chatService.providerDescription)
                                .id("streaming")
                        } else if isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(usesDirectModel ? "Generating..." : "Agent is thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    if let lastId = conversation.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: streamingResponse) { _, _ in
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input area
            inputArea
        }
        .alert("Rename Conversation", isPresented: $showRenameAlert) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                renameConversation()
            }
        }
        .alert("Delete Conversation?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteConversation()
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(conversation: conversation)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                // Model/Agent status button
                Button(action: { showModelPicker = true }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(connectionStatusColor)
                            .frame(width: 8, height: 8)

                        if chatService.isLoadingModel {
                            ProgressView()
                                .scaleEffect(0.6)
                        }

                        Text(connectionStatusText)
                            .font(.subheadline)

                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Generation stats (when available)
            if let stats = chatService.generationStats, usesDirectModel {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stats.formattedTPS)
                        .font(.caption.monospacedDigit())
                    Text("\(stats.tokensGenerated) tokens")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
            }

            Menu {
                Button(action: {
                    newTitle = conversation.title
                    showRenameAlert = true
                }) {
                    Label("Rename", systemImage: "pencil")
                }
                Button(action: { showModelPicker = true }) {
                    Label("Change Model", systemImage: "cpu")
                }
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showStats.toggle()
                    }
                }) {
                    Label(showStats ? "Hide Statistics" : "Show Statistics", systemImage: "chart.bar.xaxis")
                }
                Divider()
                Button(action: togglePin) {
                    Label(conversation.isPinned ? "Unpin" : "Pin", systemImage: conversation.isPinned ? "pin.slash" : "pin")
                }
                Button(action: toggleStar) {
                    Label(conversation.isStarred ? "Remove Star" : "Add Star", systemImage: conversation.isStarred ? "star.slash" : "star")
                }
                Divider()
                Menu {
                    Button(action: { exportConversation(format: .markdown) }) {
                        Label("Markdown", systemImage: "doc.text")
                    }
                    Button(action: { exportConversation(format: .json) }) {
                        Label("JSON", systemImage: "curlybraces")
                    }
                    Button(action: { exportConversation(format: .text) }) {
                        Label("Plain Text", systemImage: "doc.plaintext")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive, action: {
                    showDeleteConfirmation = true
                }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Input Area

    private var inputPlaceholder: String {
        if !canSendMessages {
            return "Select a model to start chatting..."
        }
        if usesDirectModel {
            return "Ask \(shortModelName(chatService.providerDescription)) anything..."
        } else if let agent = conversation.agentName {
            return "Message \(agent)..."
        }
        return "Type a message..."
    }

    private func shortModelName(_ name: String) -> String {
        name.components(separatedBy: "/").last ?? name
    }

    private var inputArea: some View {
        VStack(spacing: 0) {
            // Model loading progress
            if chatService.isLoadingModel {
                HStack(spacing: 8) {
                    ProgressView(value: chatService.loadProgress)
                        .progressViewStyle(.linear)
                    Text("\(Int(chatService.loadProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            HStack(spacing: 12) {
                // Input field with rounded background
                HStack(spacing: 8) {
                    TextField(inputPlaceholder, text: $newMessage, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .onSubmit {
                            sendMessage()
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 20))

                // Send button
                Button(action: { sendMessage() }) {
                    Image(systemName: isLoading ? "stop.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSendMessages && !newMessage.isEmpty ? Color.accentColor : Color.secondary)
                }
                .disabled(newMessage.isEmpty || !canSendMessages)
                .keyboardShortcut(.return, modifiers: [])
                .help(canSendMessages ? "Send message (⏎)" : "Select a model first")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Actions

    private func togglePin() {
        if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
            appState.workspace.conversations[index].isPinned.toggle()
        }
    }

    private func toggleStar() {
        if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
            appState.workspace.conversations[index].isStarred.toggle()
        }
    }

    private func renameConversation() {
        guard !newTitle.isEmpty else { return }
        if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
            appState.workspace.conversations[index].title = newTitle
        }
    }

    private func deleteConversation() {
        appState.workspace.conversations.removeAll { $0.id == conversation.id }
        appState.selectedConversationId = nil
    }

    enum ExportFormat {
        case markdown, json, text

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .json: return "json"
            case .text: return "txt"
            }
        }

        var contentType: String {
            switch self {
            case .markdown: return "text/markdown"
            case .json: return "application/json"
            case .text: return "text/plain"
            }
        }
    }

    private func exportConversation(format: ExportFormat) {
        let content: String

        switch format {
        case .markdown:
            content = exportAsMarkdown()
        case .json:
            content = exportAsJSON()
        case .text:
            content = exportAsText()
        }

        // Show save panel
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: format.fileExtension) ?? .plainText]
        panel.nameFieldStringValue = "\(conversation.title).\(format.fileExtension)"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Failed to export: \(error.localizedDescription)"
            }
        }
    }

    private func exportAsMarkdown() -> String {
        var lines: [String] = []
        lines.append("# \(conversation.title)")
        lines.append("")
        lines.append("*Exported \(Date().formatted())*")
        if let modelId = conversation.modelId {
            lines.append("*Model: \(modelId)*")
        }
        lines.append("")
        lines.append("---")
        lines.append("")

        for message in conversation.messages {
            let role = message.role == .user ? "**User**" : "**Assistant**"
            lines.append("\(role):")
            lines.append("")
            lines.append(message.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func exportAsJSON() -> String {
        let exportData: [String: Any] = [
            "title": conversation.title,
            "modelId": conversation.modelId ?? "",
            "createdAt": ISO8601DateFormatter().string(from: conversation.createdAt),
            "messages": conversation.messages.map { msg in
                [
                    "role": msg.role.rawValue,
                    "content": msg.content,
                    "timestamp": ISO8601DateFormatter().string(from: msg.timestamp)
                ]
            }
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    private func exportAsText() -> String {
        var lines: [String] = []
        lines.append(conversation.title)
        lines.append(String(repeating: "=", count: conversation.title.count))
        lines.append("")

        for message in conversation.messages {
            let role = message.role == .user ? "User" : "Assistant"
            lines.append("[\(role)]")
            lines.append(message.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func sendMessage() {
        guard !newMessage.isEmpty else { return }

        let messageContent = newMessage
        let userMessage = ConversationMessage(role: .user, content: messageContent)

        // Add user message to conversation
        if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
            appState.workspace.conversations[index].messages.append(userMessage)
            appState.workspace.conversations[index].updatedAt = Date()
        }

        newMessage = ""
        streamingResponse = ""
        isLoading = true
        errorMessage = nil

        if usesDirectModel {
            sendDirectModelMessage(messageContent)
        } else {
            sendA2AMessage(messageContent)
        }
    }

    private func sendDirectModelMessage(_ content: String) {
        Task {
            do {
                // Build history from conversation
                let history = conversation.messages.dropLast().map { msg in
                    ChatMessage(content: msg.content, isUser: msg.role == .user)
                }

                // Get system prompt if we have an agent template
                let systemPrompt = getSystemPrompt()

                // Stream the response
                let stream = chatService.chat(
                    prompt: content,
                    systemPrompt: systemPrompt,
                    history: Array(history)
                )

                for try await chunk in stream {
                    streamingResponse += chunk
                }

                // Add assistant response to conversation
                if !streamingResponse.isEmpty {
                    let assistantMessage = ConversationMessage(
                        role: .assistant,
                        content: streamingResponse,
                        metadata: MessageMetadata(
                            model: chatService.loadedModelId,
                            provider: chatService.selectedProvider?.name,
                            tokens: chatService.generationStats?.tokensGenerated,
                            latency: chatService.generationStats?.totalDuration
                        )
                    )
                    if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
                        appState.workspace.conversations[index].messages.append(assistantMessage)
                        appState.workspace.conversations[index].updatedAt = Date()
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                let errMsg = ConversationMessage(
                    role: .assistant,
                    content: "Sorry, I encountered an error: \(error.localizedDescription)"
                )
                if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
                    appState.workspace.conversations[index].messages.append(errMsg)
                }
            }

            streamingResponse = ""
            isLoading = false
        }
    }

    private func sendA2AMessage(_ content: String) {
        guard appState.isAgentConnected else {
            errorMessage = "Not connected to agent. Please connect first or select a model."
            isLoading = false
            return
        }

        Task {
            do {
                let stream = try await appState.sendConversationMessage(
                    conversationId: conversation.id,
                    content: content
                )

                for try await delta in stream {
                    streamingResponse += delta
                }
            } catch {
                let errMsg = ConversationMessage(
                    role: .assistant,
                    content: "Sorry, I encountered an error: \(error.localizedDescription)"
                )
                if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
                    appState.workspace.conversations[index].messages.append(errMsg)
                }
                errorMessage = error.localizedDescription
            }

            streamingResponse = ""
            isLoading = false
        }
    }

    private func getSystemPrompt() -> String? {
        // Check if conversation has an associated agent template
        if let agentName = conversation.agentName,
           let template = AgentTemplate.allTemplates.first(where: { $0.name == agentName }) {
            return template.systemPrompt
        }
        return nil
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    let conversation: Conversation
    @EnvironmentObject private var appState: AppState
    @Environment(ChatService.self) private var chatService
    @Environment(ProviderConfigManager.self) private var providerManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProviderId: UUID?
    @State private var selectedModelId: String?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Model")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Current selection
                    if chatService.isReady {
                        currentModelSection
                    }

                    // A2A Agent option
                    agentSection

                    // Provider sections
                    ForEach(providerManager.providers.filter { $0.isEnabled }) { provider in
                        providerSection(provider)
                    }
                }
                .padding()
            }

            // Error
            if let error = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                    Spacer()
                }
                .padding()
                .background(.red.opacity(0.1))
            }
        }
        .frame(width: 450, height: 500)
        .onAppear {
            Task {
                await providerManager.checkAllProviders()
            }
        }
    }

    private var currentModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Current", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            HStack {
                Image(systemName: providerIcon(chatService.selectedProvider?.type))
                    .foregroundStyle(.secondary)
                Text(chatService.providerDescription)
                    .font(.body)
                Spacer()
                if chatService.isGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding()
            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("A2A Agent", systemImage: "person.circle")
                .font(.subheadline.weight(.semibold))

            Button(action: selectA2AAgent) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.localAgent?.name ?? "Local Agent")
                            .font(.body)
                        Text(appState.isAgentConnected ? "Connected" : "Not connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(appState.isAgentConnected ? .green : .gray)
                        .frame(width: 8, height: 8)
                }
                .padding()
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private func providerSection(_ provider: ProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(provider.name, systemImage: provider.type.icon)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                // Status badge
                statusBadge(for: provider)
            }

            // Models for this provider
            if case .available = providerManager.providerStatus[provider.id] {
                modelList(for: provider)
            } else if case .checking = providerManager.providerStatus[provider.id] {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Checking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                unavailableMessage(for: provider)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for provider: ProviderConfig) -> some View {
        switch providerManager.providerStatus[provider.id] {
        case .available(let count):
            Text("\(count) models")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView()
                .scaleEffect(0.6)
        case .unavailable(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.orange)
        case .error(let msg):
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func modelList(for provider: ProviderConfig) -> some View {
        LazyVStack(spacing: 4) {
            ForEach(getModels(for: provider), id: \.self) { modelId in
                Button(action: { selectModel(provider: provider, modelId: modelId) }) {
                    HStack {
                        Text(shortModelName(modelId))
                            .font(.body)
                        Spacer()
                        if isLoading && selectedModelId == modelId {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if chatService.loadedModelId == modelId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
    }

    @ViewBuilder
    private func unavailableMessage(for provider: ProviderConfig) -> some View {
        if case .unavailable(let reason) = providerManager.providerStatus[provider.id] {
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func getModels(for provider: ProviderConfig) -> [String] {
        switch provider.type {
        case .mlx:
            // Get recommended models from the catalog (variants with .recommended or .fast tags)
            return MLXModelCatalog.families.flatMap { family in
                family.variants.filter { variant in
                    variant.tags.contains(.recommended) || variant.tags.contains(.fast)
                }.map { $0.modelId }
            }
        case .ollama:
            return provider.availableModels.isEmpty ? ["llama3.2", "qwen2.5", "mistral"] : provider.availableModels
        case .anthropic:
            return ["claude-sonnet-4-5-20251101", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"]
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "o1-preview", "o1-mini"]
        default:
            return provider.availableModels
        }
    }

    private func selectModel(provider: ProviderConfig, modelId: String) {
        isLoading = true
        selectedModelId = modelId
        error = nil

        Task {
            do {
                if provider.type == .mlx {
                    try await chatService.loadMLXModel(modelId)
                } else {
                    var updatedProvider = provider
                    updatedProvider.selectedModel = modelId
                    try await chatService.selectProvider(updatedProvider)
                }

                // Update conversation with model info
                if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
                    appState.workspace.conversations[index].modelId = modelId
                    appState.workspace.conversations[index].providerId = provider.id.uuidString
                    appState.workspace.conversations[index].agentName = nil
                }

                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func selectA2AAgent() {
        // Clear model selection, use A2A instead
        if let index = appState.workspace.conversations.firstIndex(where: { $0.id == conversation.id }) {
            appState.workspace.conversations[index].modelId = nil
            appState.workspace.conversations[index].providerId = nil
            appState.workspace.conversations[index].agentName = appState.localAgent?.name ?? "Local Agent"
        }
        dismiss()
    }

    private func shortModelName(_ modelId: String) -> String {
        modelId.components(separatedBy: "/").last ?? modelId
    }

    private func providerIcon(_ type: ProviderType?) -> String {
        type?.icon ?? "cpu"
    }
}

// MARK: - Streaming Message View

struct StreamingMessageView: View {
    let content: String
    var modelName: String = "Agent"
    @State private var animationPhase = 0.0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Header with model name and streaming indicator
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.variableColor.iterative, options: .repeating)

                    Text(shortModelName(modelName))
                        .fontWeight(.medium)

                    Spacer()

                    // Live indicator with pulse
                    HStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(.green.opacity(0.3))
                                .frame(width: 10, height: 10)
                                .scaleEffect(animationPhase > 0.5 ? 1.5 : 1.0)
                                .opacity(animationPhase > 0.5 ? 0 : 0.5)
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                        }
                        Text("Generating")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)

                // Content with subtle animation
                Text(content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    )

                // Animated typing indicator
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .scaleEffect(pulseScale(for: i))
                            .opacity(pulseOpacity(for: i))
                    }
                }
                .padding(.leading, 12)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        animationPhase = 1.0
                    }
                }
            }

            Spacer(minLength: 60)
        }
    }

    private func pulseScale(for index: Int) -> CGFloat {
        let offset = Double(index) * 0.2
        let phase = (animationPhase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.8 + (0.4 * phase)
    }

    private func pulseOpacity(for index: Int) -> Double {
        let offset = Double(index) * 0.2
        let phase = (animationPhase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.4 + (0.6 * phase)
    }

    private func shortModelName(_ name: String) -> String {
        name.components(separatedBy: "/").last ?? name
    }
}

// MARK: - Conversation Message Bubble

struct ConversationMessageBubble: View {
    let message: ConversationMessage
    var onRegenerate: (() -> Void)? = nil
    @State private var isHovered = false
    @State private var showCopiedFeedback = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.md) {
            if isUser {
                Spacer(minLength: 80)
            }

            // Avatar for assistant messages
            if !isUser {
                Circle()
                    .fill(Color.Envoy.model.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.Envoy.model)
                    )
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.xs) {
                // Show model info for assistant messages
                if !isUser, let metadata = message.metadata {
                    HStack(spacing: Spacing.sm) {
                        if let model = metadata.model {
                            Text(shortModelName(model))
                                .font(Font.Envoy.meta)
                        }
                        if let tokens = metadata.tokens {
                            Text("•")
                                .foregroundStyle(.quaternary)
                            Text("\(tokens) tokens")
                        }
                        if let latency = metadata.latencyMs {
                            Text("•")
                                .foregroundStyle(.quaternary)
                            Text("\(Double(latency) / 1000, specifier: "%.1f")s")
                        }
                    }
                    .font(Font.Envoy.captionSmall)
                    .foregroundStyle(.tertiary)
                }

                // Message content with action buttons as overlay (prevents layout shift)
                Text(message.content)
                    .font(Font.Envoy.bodyPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(
                        isUser
                            ? AnyShapeStyle(Color.accentColor.gradient)
                            : AnyShapeStyle(Color(.controlBackgroundColor))
                    )
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isHovered && !isUser ? Color.secondary.opacity(0.2) : Color.clear, lineWidth: 1)
                    )
                    .overlay(alignment: isUser ? .bottomLeading : .bottomTrailing) {
                        // Action buttons overlay - positioned outside bubble to avoid layout shift
                        if isHovered {
                            HStack(spacing: Spacing.xs) {
                                // Copy button
                                MessageActionButton(
                                    icon: showCopiedFeedback ? "checkmark" : "doc.on.doc",
                                    tooltip: showCopiedFeedback ? "Copied!" : "Copy"
                                ) {
                                    copyToClipboard()
                                }

                                // Regenerate button (assistant only)
                                if !isUser, let regenerate = onRegenerate {
                                    MessageActionButton(icon: "arrow.clockwise", tooltip: "Regenerate") {
                                        regenerate()
                                    }
                                }
                            }
                            .padding(4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .offset(x: isUser ? -8 : 8, y: 8)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(Font.Envoy.captionSmall)
                    .foregroundStyle(.quaternary)
            }

            // Avatar for user messages
            if isUser {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    )
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(action: copyToClipboard) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if !isUser, let regenerate = onRegenerate {
                Button(action: regenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        FeedbackManager.copied()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showCopiedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                showCopiedFeedback = false
            }
        }
    }

    private func shortModelName(_ modelId: String) -> String {
        modelId.components(separatedBy: "/").last ?? modelId
    }
}

// MARK: - Message Action Button

struct MessageActionButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            // Trigger press animation
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                    isPressed = false
                }
            }
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovered ? Color.Envoy.subtleBackground : Color.clear)
                )
                .scaleEffect(isPressed ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Empty State

struct EmptyConversationDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(ChatService.self) private var chatService
    @State private var showModelPicker = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: chatService.isReady ? "bubble.left.and.bubble.right" : "cpu")
                .font(.system(size: 56))
                .foregroundStyle(chatService.isReady ? Color.secondary : Color.orange)
                .symbolEffect(.pulse, options: .repeating, isActive: !chatService.isReady)

            // Title and description
            VStack(spacing: 8) {
                Text(chatService.isReady ? "Start a Conversation" : "Select a Model First")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(chatService.isReady
                    ? "Choose a conversation from the list or start a new one."
                    : "Pick an AI model to power your conversations.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            // Actions
            VStack(spacing: 12) {
                if chatService.isReady {
                    Button(action: { appState.showNewConversationSheet = true }) {
                        Label("New Conversation", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button(action: { showModelPicker = true }) {
                        Label("Select Model", systemImage: "cpu")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("or configure models in Settings")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Model status
            if chatService.isReady {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text(shortModelName(chatService.providerDescription))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(action: { showModelPicker = true }) {
                        Text("Change")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showModelPicker) {
            QuickModelSetupSheet()
        }
    }

    private func shortModelName(_ name: String) -> String {
        name.components(separatedBy: "/").last ?? name
    }
}

// MARK: - Quick Model Setup Sheet

struct QuickModelSetupSheet: View {
    @Environment(ChatService.self) private var chatService
    @Environment(ProviderConfigManager.self) private var providerManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var selectedModelId: String?
    @State private var error: String?

    private let quickModels: [(id: String, name: String, desc: String, size: String)] = [
        ("mlx-community/Llama-3.2-1B-Instruct-4bit", "Llama 3.2 1B", "Ultra-fast, great for simple tasks", "~700MB"),
        ("mlx-community/Llama-3.2-3B-Instruct-4bit", "Llama 3.2 3B", "Good balance of speed and capability", "~2GB"),
        ("mlx-community/Qwen2.5-7B-Instruct-4bit", "Qwen 2.5 7B", "Excellent quality, recommended", "~5GB"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange.gradient)

                Text("Choose Your AI Model")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Models run locally on your Mac. No internet needed after download.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 24)

            Divider()

            // Model options
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(quickModels, id: \.id) { model in
                        Button(action: { selectModel(model.id) }) {
                            HStack(spacing: 16) {
                                // Icon
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.1))
                                        .frame(width: 48, height: 48)

                                    if isLoading && selectedModelId == model.id {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else if chatService.loadedModelId == model.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "cpu")
                                            .font(.title3)
                                            .foregroundStyle(.orange)
                                    }
                                }

                                // Info
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.name)
                                        .font(.headline)

                                    Text(model.desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                // Size badge
                                Text(model.size)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .padding()
                            .background(
                                chatService.loadedModelId == model.id
                                    ? Color.green.opacity(0.1)
                                    : Color(.controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        chatService.loadedModelId == model.id
                                            ? Color.green.opacity(0.3)
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                }
                .padding()
            }

            // Error
            if let error = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                }
                .padding()
                .background(.red.opacity(0.1))
            }

            Divider()

            // Footer
            HStack {
                Button("More Models") {
                    appState.targetSettingsCategory = "models"
                    appState.selectedSidebarItem = .settings
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                if chatService.isReady {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 450, height: 550)
    }

    private func selectModel(_ modelId: String) {
        isLoading = true
        selectedModelId = modelId
        error = nil

        Task {
            do {
                try await chatService.loadMLXModel(modelId)
                // Don't dismiss automatically - let user see success state
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - New Conversation Sheet

struct NewConversationSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(ChatService.self) private var chatService
    @Environment(ProviderConfigManager.self) private var providerManager
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedMode: ConversationMode = .directModel
    @State private var selectedProviderId: UUID?
    @State private var selectedAgentTemplate: AgentTemplate?

    enum ConversationMode: String, CaseIterable {
        case directModel = "Direct Model"
        case agent = "Agent Template"
        case a2aAgent = "A2A Agent"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("New Conversation")
                .font(.headline)

            TextField("Conversation Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)

            // Mode picker
            Picker("Mode", selection: $selectedMode) {
                ForEach(ConversationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Mode-specific options
            Group {
                switch selectedMode {
                case .directModel:
                    directModelOptions
                case .agent:
                    agentTemplateOptions
                case .a2aAgent:
                    a2aAgentOptions
                }
            }
            .frame(minHeight: 100)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    createConversation()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding()
        .frame(width: 450)
        .onAppear {
            // Default to current model if available
            if chatService.isReady {
                selectedMode = .directModel
            }
        }
    }

    private var canCreate: Bool {
        switch selectedMode {
        case .directModel:
            return chatService.isReady || selectedProviderId != nil
        case .agent:
            return selectedAgentTemplate != nil
        case .a2aAgent:
            return true
        }
    }

    private var directModelOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if chatService.isReady {
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Using: \(chatService.providerDescription)")
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Select a model from Settings > Models first")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Open Models Settings") {
                    appState.selectedSidebarItem = .settings
                    dismiss()
                }
            }
        }
    }

    private var agentTemplateOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select an agent personality:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                    ForEach(AgentTemplate.allTemplates.prefix(9), id: \.id) { template in
                        Button(action: { selectedAgentTemplate = template }) {
                            VStack(spacing: 4) {
                                Text(template.personality.emoji)
                                    .font(.title2)
                                Text(template.name)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(
                                selectedAgentTemplate?.id == template.id
                                    ? Color.accentColor.opacity(0.2)
                                    : Color(.controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        selectedAgentTemplate?.id == template.id
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 150)
        }
    }

    private var a2aAgentOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(appState.isAgentConnected ? .green : .gray)
                    .frame(width: 8, height: 8)
                Text(appState.localAgent?.name ?? "Local Agent")
                    .font(.subheadline)
                Text(appState.isAgentConnected ? "Connected" : "Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            if !appState.isAgentConnected {
                Text("Connect to an agent server first for full agent capabilities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func createConversation() {
        var conversation = Conversation(
            title: title.isEmpty ? generateTitle() : title
        )

        switch selectedMode {
        case .directModel:
            conversation.modelId = chatService.loadedModelId
            conversation.providerId = chatService.selectedProvider?.id.uuidString

        case .agent:
            if let template = selectedAgentTemplate {
                conversation.agentName = template.name
                conversation.title = title.isEmpty ? "Chat with \(template.name)" : title
            }

        case .a2aAgent:
            conversation.agentName = appState.localAgent?.name ?? "Local Agent"
        }

        appState.workspace.conversations.insert(conversation, at: 0)
        appState.selectedConversationId = conversation.id
        dismiss()
    }

    private func generateTitle() -> String {
        switch selectedMode {
        case .directModel:
            return "Chat - \(chatService.providerDescription)"
        case .agent:
            return "Chat with \(selectedAgentTemplate?.name ?? "Agent")"
        case .a2aAgent:
            return "Chat with \(appState.localAgent?.name ?? "Agent")"
        }
    }
}

// MARK: - Welcome Message View

/// A warm welcome message displayed at the start of empty conversations
struct WelcomeMessageView: View {
    let modelName: String
    let isDirectModel: Bool
    let agentName: String?
    var onPromptSelected: ((String) -> Void)?

    @State private var hasAppeared = false
    @State private var iconPulse = false

    private var welcomeTitle: String {
        if isDirectModel {
            return "Chat with \(shortModelName(modelName))"
        } else if let agent = agentName {
            return "Chat with \(agent)"
        } else {
            return "Start a Conversation"
        }
    }

    private var welcomeSubtitle: String {
        if isDirectModel {
            return "Running locally on your Mac. Your conversations stay private."
        } else {
            return "Ask questions, get help, or explore ideas together."
        }
    }

    // Quick prompts - tappable templates that fill the input
    private var quickPrompts: [QuickPromptTemplate] {
        if isDirectModel {
            return [
                QuickPromptTemplate(icon: "lightbulb", title: "Explain a concept", prompt: "Explain to me how "),
                QuickPromptTemplate(icon: "doc.text", title: "Help me write", prompt: "Help me write a "),
                QuickPromptTemplate(icon: "hammer", title: "Debug code", prompt: "Help me debug this code:\n\n```\n\n```"),
                QuickPromptTemplate(icon: "sparkles", title: "Brainstorm", prompt: "Help me brainstorm ideas for "),
                QuickPromptTemplate(icon: "arrow.triangle.2.circlepath", title: "Refactor", prompt: "Refactor this code to be more readable:\n\n```\n\n```"),
                QuickPromptTemplate(icon: "checkmark.shield", title: "Review", prompt: "Review this code for potential issues:\n\n```\n\n```"),
            ]
        } else {
            return [
                QuickPromptTemplate(icon: "list.bullet", title: "Organize tasks", prompt: "Help me organize my tasks for today"),
                QuickPromptTemplate(icon: "calendar", title: "Plan schedule", prompt: "Help me plan my schedule for "),
                QuickPromptTemplate(icon: "envelope", title: "Draft email", prompt: "Help me draft an email to "),
                QuickPromptTemplate(icon: "magnifyingglass", title: "Research", prompt: "Research and summarize information about "),
                QuickPromptTemplate(icon: "doc.text.magnifyingglass", title: "Summarize", prompt: "Summarize the key points of "),
                QuickPromptTemplate(icon: "lightbulb", title: "Suggest", prompt: "Suggest ways to improve "),
            ]
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            // Icon with entrance animation
            ZStack {
                // Outer glow pulse
                Circle()
                    .fill(Color.Envoy.model.opacity(0.1))
                    .frame(width: 100, height: 100)
                    .scaleEffect(iconPulse ? 1.1 : 1.0)
                    .opacity(iconPulse ? 0.5 : 0.2)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.Envoy.model.opacity(0.2), Color.pink.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: isDirectModel ? "cpu" : "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.Envoy.model.gradient)
                    .symbolEffect(.pulse, options: .speed(0.5), isActive: hasAppeared)
            }
            .scaleEffect(hasAppeared ? 1.0 : 0.5)
            .opacity(hasAppeared ? 1.0 : 0.0)

            // Text with staggered entrance
            VStack(spacing: 8) {
                Text(welcomeTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .opacity(hasAppeared ? 1.0 : 0.0)
                    .offset(y: hasAppeared ? 0 : 10)

                Text(welcomeSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(hasAppeared ? 1.0 : 0.0)
                    .offset(y: hasAppeared ? 0 : 10)
            }

            // Quick prompts with entrance animation
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick prompts:")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(quickPrompts.enumerated()), id: \.element.id) { index, template in
                        QuickPromptChip(template: template) {
                            onPromptSelected?(template.prompt)
                        }
                        .opacity(hasAppeared ? 1.0 : 0.0)
                        .offset(y: hasAppeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.08), value: hasAppeared)
                    }
                }
            }
            .frame(maxWidth: 500)
            .opacity(hasAppeared ? 1.0 : 0.0)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                hasAppeared = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                iconPulse = true
            }
        }
    }

    private func shortModelName(_ name: String) -> String {
        name.components(separatedBy: "/").last ?? name
    }
}

// MARK: - Quick Prompt Template

struct QuickPromptTemplate: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let prompt: String
}

// MARK: - Quick Prompt Chip

struct QuickPromptChip: View {
    let template: QuickPromptTemplate
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                    isPressed = false
                }
                action()
            }
        }) {
            VStack(spacing: 6) {
                Image(systemName: template.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isHovered ? Color.Envoy.model : .secondary)
                    .frame(height: 20)

                Text(template.title)
                    .font(.caption)
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.Envoy.model.opacity(0.1) : Color.Envoy.subtleBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Color.Envoy.model.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.02 : 1.0))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.15, dampingFraction: 0.5), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(template.prompt.prefix(50) + "...")
    }
}

// MARK: - Welcome Suggestion Chip (legacy)

struct WelcomeSuggestionChip: View {
    let icon: String
    let text: String

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(isHovered ? Color.Envoy.model : .secondary)
                .frame(width: 16)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(isHovered ? .primary : .secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.Envoy.model.opacity(0.1) : Color.Envoy.subtleBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.Envoy.model.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Conversation Statistics View

struct ConversationStatsView: View {
    let conversation: Conversation
    @State private var isExpanded = false

    // Computed statistics
    private var totalTokens: Int {
        conversation.messages.compactMap { $0.metadata?.tokens }.reduce(0, +)
    }

    private var totalMessages: Int {
        conversation.messages.count
    }

    private var userMessages: Int {
        conversation.messages.filter { $0.role == .user }.count
    }

    private var assistantMessages: Int {
        conversation.messages.filter { $0.role == .assistant }.count
    }

    private var averageTokensPerMessage: Int {
        guard assistantMessages > 0 else { return 0 }
        return totalTokens / assistantMessages
    }

    private var conversationDuration: String {
        guard let first = conversation.messages.first?.timestamp,
              let last = conversation.messages.last?.timestamp else {
            return "N/A"
        }
        let duration = last.timeIntervalSince(first)
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m"
        } else {
            return "\(Int(duration / 3600))h \(Int((duration.truncatingRemainder(dividingBy: 3600)) / 60))m"
        }
    }

    private var averageLatency: String {
        let latencies = conversation.messages.compactMap { $0.metadata?.latencyMs }
        guard !latencies.isEmpty else { return "N/A" }
        let avgMs = latencies.reduce(0, +) / latencies.count
        return String(format: "%.1fs", Double(avgMs) / 1000)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Collapsible header
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.caption)
                        .foregroundStyle(Color.Envoy.info)

                    Text("Statistics")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Quick stats preview
                    if !isExpanded {
                        HStack(spacing: 12) {
                            StatBadge(value: "\(totalMessages)", label: "msgs")
                            StatBadge(value: formatTokenCount(totalTokens), label: "tokens")
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.Envoy.subtleBackground.opacity(0.5))
            }
            .buttonStyle(.plain)

            // Expanded stats
            if isExpanded {
                VStack(spacing: 12) {
                    // Stats grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        StatCard(
                            icon: "bubble.left.and.bubble.right",
                            value: "\(totalMessages)",
                            label: "Messages",
                            color: .blue
                        )
                        StatCard(
                            icon: "number",
                            value: formatTokenCount(totalTokens),
                            label: "Tokens",
                            color: .green
                        )
                        StatCard(
                            icon: "clock",
                            value: conversationDuration,
                            label: "Duration",
                            color: .orange
                        )
                        StatCard(
                            icon: "person",
                            value: "\(userMessages)",
                            label: "You",
                            color: .purple
                        )
                        StatCard(
                            icon: "cpu",
                            value: "\(assistantMessages)",
                            label: "Model",
                            color: Color.Envoy.model
                        )
                        StatCard(
                            icon: "gauge.medium",
                            value: averageLatency,
                            label: "Avg Latency",
                            color: .cyan
                        )
                    }

                    // Token usage breakdown
                    if totalTokens > 0 {
                        TokenUsageBar(
                            userTokens: estimateUserTokens(),
                            assistantTokens: totalTokens
                        )
                    }
                }
                .padding(12)
                .background(Color.Envoy.subtleBackground.opacity(0.3))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }

    private func estimateUserTokens() -> Int {
        // Rough estimate: ~4 chars per token
        let userChars = conversation.messages
            .filter { $0.role == .user }
            .map { $0.content.count }
            .reduce(0, +)
        return userChars / 4
    }
}

// MARK: - Stat Badge (compact)

private struct StatBadge: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Stat Card (expanded)

private struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .scaleEffect(isHovered ? 1.15 : 1.0)

            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(isHovered ? 0.15 : 0.08))
        )
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Token Usage Bar

private struct TokenUsageBar: View {
    let userTokens: Int
    let assistantTokens: Int

    private var total: Int { userTokens + assistantTokens }
    private var userRatio: Double {
        guard total > 0 else { return 0 }
        return Double(userTokens) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Token Distribution")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    // User portion
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.Envoy.user.gradient)
                        .frame(width: max(geometry.size.width * userRatio, 4))

                    // Assistant portion
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.Envoy.model.gradient)
                }
            }
            .frame(height: 8)

            // Legend
            HStack(spacing: 16) {
                LegendItem(color: Color.Envoy.user, label: "Input", value: "~\(userTokens)")
                LegendItem(color: Color.Envoy.model, label: "Output", value: "\(assistantTokens)")
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Keyboard Shortcuts Help Overlay

/// Data model for a keyboard shortcut
struct KeyboardShortcut: Identifiable {
    let id = UUID()
    let keys: [String]
    let description: String
    let category: ShortcutCategory

    enum ShortcutCategory: String, CaseIterable {
        case navigation = "Navigation"
        case conversations = "Conversations"
        case editing = "Editing"
        case general = "General"
    }
}

/// Help overlay showing all available keyboard shortcuts
struct KeyboardShortcutsOverlay: View {
    @Binding var isPresented: Bool
    @State private var hasAppeared = false

    private let shortcuts: [KeyboardShortcut] = [
        // Navigation
        KeyboardShortcut(keys: ["↑"], description: "Select previous conversation", category: .navigation),
        KeyboardShortcut(keys: ["↓"], description: "Select next conversation", category: .navigation),
        KeyboardShortcut(keys: ["⌘", "K"], description: "Open command palette", category: .navigation),
        KeyboardShortcut(keys: ["⌘", ","], description: "Open settings", category: .navigation),

        // Conversations
        KeyboardShortcut(keys: ["⌘", "N"], description: "New conversation", category: .conversations),
        KeyboardShortcut(keys: ["⌘", "⇧", "N"], description: "New conversation (alternate)", category: .conversations),
        KeyboardShortcut(keys: ["⌫"], description: "Delete selected conversation", category: .conversations),
        KeyboardShortcut(keys: ["⌘", "M"], description: "Select model", category: .conversations),

        // Editing
        KeyboardShortcut(keys: ["⌘", "C"], description: "Copy selected text", category: .editing),
        KeyboardShortcut(keys: ["⌘", "V"], description: "Paste", category: .editing),
        KeyboardShortcut(keys: ["⏎"], description: "Send message", category: .editing),
        KeyboardShortcut(keys: ["⇧", "⏎"], description: "New line in message", category: .editing),

        // General
        KeyboardShortcut(keys: ["?"], description: "Show this help", category: .general),
        KeyboardShortcut(keys: ["Esc"], description: "Close overlay / Cancel", category: .general),
    ]

    private var groupedShortcuts: [KeyboardShortcut.ShortcutCategory: [KeyboardShortcut]] {
        Dictionary(grouping: shortcuts, by: { $0.category })
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(hasAppeared ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Content card
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Keyboard Shortcuts")
                            .font(Font.Envoy.pageTitle)

                        Text("Press ? anytime to show this help")
                            .font(Font.Envoy.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(Spacing.xl)

                Divider()

                // Shortcuts grid
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        ForEach(KeyboardShortcut.ShortcutCategory.allCases, id: \.self) { category in
                            if let categoryShortcuts = groupedShortcuts[category] {
                                shortcutSection(title: category.rawValue, shortcuts: categoryShortcuts)
                            }
                        }
                    }
                    .padding(Spacing.xl)
                }
            }
            .frame(width: 500, height: 520)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.windowBackgroundColor))
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            )
            .scaleEffect(hasAppeared ? 1.0 : 0.9)
            .opacity(hasAppeared ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                hasAppeared = true
            }
        }
    }

    private func shortcutSection(title: String, shortcuts: [KeyboardShortcut]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(Font.Envoy.sectionTitle)
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                ForEach(shortcuts) { shortcut in
                    shortcutRow(shortcut)
                }
            }
        }
    }

    private func shortcutRow(_ shortcut: KeyboardShortcut) -> some View {
        HStack(spacing: Spacing.sm) {
            // Keys
            HStack(spacing: Spacing.xxs) {
                ForEach(shortcut.keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.controlBackgroundColor))
                                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(.separatorColor), lineWidth: 0.5)
                        )
                }
            }
            .frame(minWidth: 60, alignment: .leading)

            // Description
            Text(shortcut.description)
                .font(Font.Envoy.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            hasAppeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}

/// View modifier to add keyboard shortcut help overlay
struct KeyboardShortcutsHelpModifier: ViewModifier {
    @State private var showShortcuts = false

    func body(content: Content) -> some View {
        content
            .onKeyPress("/", phases: .down) { _ in
                // Check if Shift is held (? = Shift + /)
                showShortcuts = true
                return .handled
            }
            .overlay {
                if showShortcuts {
                    KeyboardShortcutsOverlay(isPresented: $showShortcuts)
                }
            }
    }
}

extension View {
    /// Add keyboard shortcuts help overlay (triggered by ?)
    func keyboardShortcutsHelp() -> some View {
        modifier(KeyboardShortcutsHelpModifier())
    }
}
