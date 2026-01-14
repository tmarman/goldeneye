import AgentKit
import Combine
import Foundation
import SwiftUI

/// Global application state for the Console app
@MainActor
public final class AppState: ObservableObject {
    /// Shared instance for AppKit window creation
    static let shared = AppState()
    // MARK: - Navigation

    @Published var selectedSidebarItem: SidebarItem = .openSpace
    @Published var showNewTaskSheet = false
    @Published var showConnectSheet = false
    @Published var showNewDocumentSheet = false
    @Published var showNewConversationSheet = false
    @Published var showNewCoachingSheet = false
    @Published var showNewSpaceSheet = false
    @Published var showCommandPalette = false
    @Published var showAgentRecruitment = false
    @Published var showAgentBuilder = false

    // MARK: - Space Management

    /// The space manager handles all Git-backed spaces
    let spaceManager: SpaceManager

    /// Capture processor for Open Space
    let captureProcessor: CaptureProcessor

    /// Decision card manager for approval workflows
    let decisionManager: DecisionCardManager

    /// Agent registry - knows all available agents
    let agentRegistry: AgentRegistry

    /// Agent delegation manager - handles agent-to-agent task delegation
    let delegationManager: AgentDelegationManager

    /// MCP connection manager - handles connections to MCP servers
    let mcpManager: MCPManager

    /// Current spaces loaded from SpaceManager (for UI binding)
    @Published var spaces: [SpaceViewModel] = []

    /// Selected space for detail view
    @Published var selectedSpaceId: SpaceID?

    // MARK: - Open Space

    /// Timeline items for display (view model layer)
    @Published var timelineItems: [TimelineItemViewModel] = []

    /// Pending captures being processed
    @Published var processingCaptures: Set<UUID> = []

    /// Decision cards for UI binding
    @Published var decisionCards: [DecisionCard] = []

    /// Registered agents for UI binding
    @Published var registeredAgents: [RegisteredAgent] = []

    /// Active delegations for UI binding
    @Published var activeDelegations: [AgentDelegation] = []

    // MARK: - Legacy Workspace (Shared Context) - kept for migration

    @Published var workspace: WorkspaceState = WorkspaceState()

    // MARK: - Selected Items

    @Published var selectedDocumentId: DocumentID?
    @Published var selectedConversationId: ConversationID?
    @Published var selectedCoachingSessionId: CoachingSessionID?

    // MARK: - Agent Panel

    @Published var isAgentPanelVisible = false

    // MARK: - Agents

    @Published var connectedAgents: [ConnectedAgent] = []
    @Published var localAgent: ConnectedAgent?

    /// Recruited agents from templates
    @Published var recruitedAgents: [RecruitedAgent] = []

    // MARK: - Tasks

    @Published var activeTasks: [TaskInfo] = []
    @Published var recentTasks: [TaskInfo] = []

    // MARK: - A2A Client

    /// A2A client for communicating with the local agent server
    private var a2aClient: A2AClient?

    /// Whether the agent client is available for requests
    var hasAgentClient: Bool { a2aClient != nil }

    /// Send a message to the agent and collect the full response
    func sendAgentMessage(_ prompt: String) async -> String? {
        guard let client = a2aClient else { return nil }

        let message = A2AMessage(
            role: .user,
            parts: [.text(A2APart.TextPart(text: prompt))]
        )

        var response = ""
        let stream = await client.sendStreamingMessage(message)

        do {
            for try await event in stream {
                if case .message(let msg) = event {
                    for part in msg.parts {
                        if case .text(let textPart) = part {
                            response += textPart.text
                        }
                    }
                }
            }
            return response.isEmpty ? nil : response
        } catch {
            print("Agent message failed: \(error)")
            return nil
        }
    }

    // MARK: - Approvals

    @Published var pendingApprovals: [PendingApproval] = []

    // MARK: - Menu Bar

    var menuBarIcon: String {
        if !pendingApprovals.isEmpty {
            return "brain.fill"
        } else if activeTasks.contains(where: { $0.state == .working }) {
            return "brain"
        }
        return "brain"
    }

    // MARK: - Initialization

    init() {
        // Initialize SpaceManager
        self.spaceManager = SpaceManager()

        // Initialize CaptureProcessor with SpaceManager's OpenSpace
        let openSpace = spaceManager.openSpace
        self.captureProcessor = CaptureProcessor(openSpace: openSpace, spaceManager: spaceManager)

        // Initialize DecisionCardManager
        self.decisionManager = DecisionCardManager()

        // Initialize AgentRegistry and DelegationManager
        self.agentRegistry = AgentRegistry()
        self.delegationManager = AgentDelegationManager(registry: agentRegistry)

        // Initialize MCP Manager
        self.mcpManager = MCPManager()

        // Initialize local agent using settings
        updateLocalAgentFromSettings()

        // Load content in background
        Task {
            await loadSpaces()
            await loadDocuments()

            // Auto-connect if enabled
            if UserDefaults.standard.bool(forKey: "autoConnectLocal") {
                await autoConnectToServer()
            }
        }

        // Keep sample conversation for development
        setupSampleConversation()

        // Observe settings changes
        setupSettingsObservers()
    }

    /// Update local agent URL from UserDefaults
    private func updateLocalAgentFromSettings() {
        let host = UserDefaults.standard.string(forKey: "localAgentHost") ?? "127.0.0.1"
        let port = UserDefaults.standard.integer(forKey: "localAgentPort")
        let effectivePort = port == 0 ? 8080 : port
        let url = URL(string: "http://\(host):\(effectivePort)")!

        if localAgent == nil {
            localAgent = ConnectedAgent(
                id: "local",
                name: "Local Agent",
                url: url,
                status: .disconnected
            )
        } else {
            localAgent?.url = url
        }
    }

    /// Setup observers for settings changes
    private func setupSettingsObservers() {
        // Observe host/port changes
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateLocalAgentFromSettings()
            }
        }
    }

    /// Auto-connect to server if it's running
    private func autoConnectToServer() async {
        // Check if server is already running
        let serverManager = ServerManager.shared
        if serverManager.isRunning {
            await connectToLocalAgent()
        } else if await serverManager.checkServerHealth() {
            // Server is running externally
            await connectToLocalAgent()
        }
    }

    private func setupSampleConversation() {
        // Sample conversation for development
        let sampleConversation = Conversation(
            title: "Getting started chat",
            messages: [
                ConversationMessage(role: .user, content: "Hello! What can you help me with?"),
                ConversationMessage(role: .assistant, content: "I can help you with a wide range of tasks! I can assist with writing, research, coding, analysis, and creative projects. I can also coach you on career development, fitness, and more. What would you like to explore?")
            ],
            agentName: "Primary Agent"
        )
        workspace.conversations.append(sampleConversation)
    }

    // MARK: - Space Operations

    /// Load all spaces from SpaceManager
    func loadSpaces() async {
        do {
            try await spaceManager.discoverSpaces()
            let loadedSpaces = await spaceManager.spaces

            // Build view models sequentially to avoid Sendable issues
            var viewModels: [SpaceViewModel] = []
            for space in loadedSpaces {
                let vm = await SpaceViewModel(from: space)
                viewModels.append(vm)
            }
            self.spaces = viewModels
        } catch {
            print("Failed to load spaces: \(error)")
        }
    }

    /// Create a new space
    func createSpace(name: String, description: String?, icon: String, color: SpaceColor) async throws {
        let space = try await spaceManager.createSpace(
            name: name,
            description: description,
            owner: .user,
            icon: icon,
            color: color
        )

        let viewModel = await SpaceViewModel(from: space)
        spaces.insert(viewModel, at: 0)
    }

    /// Delete a space
    func deleteSpace(_ id: SpaceID) async throws {
        try await spaceManager.deleteSpace(id)
        spaces.removeAll { $0.id == id.rawValue }
    }

    /// Star/unstar a space
    func toggleSpaceStar(_ id: SpaceID) async {
        guard let space = await spaceManager.space(id: id) else { return }

        if await space.isStarred {
            await space.unstar()
        } else {
            await space.star()
        }

        // Update view model
        if let index = spaces.firstIndex(where: { $0.id == id.rawValue }) {
            spaces[index].isStarred.toggle()
        }
    }

    // MARK: - Actions

    func connectToLocalAgent() async {
        guard var agent = localAgent else { return }
        agent.status = .connecting
        localAgent = agent

        do {
            // Create A2A client for the agent's URL
            let client = A2AClient(baseURL: agent.url)

            // Health check first
            guard try await client.healthCheck() else {
                agent.status = .error("Server not responding")
                localAgent = agent
                return
            }

            // Fetch agent card to verify it's a valid A2A agent
            let card = try await client.fetchAgentCard()

            // Success - store client and update agent
            self.a2aClient = client
            agent.card = card
            agent.name = card.name
            agent.status = .connected
            localAgent = agent

            // Add to connected agents list
            if !connectedAgents.contains(where: { $0.id == agent.id }) {
                connectedAgents.append(agent)
            }

            print("Connected to agent: \(card.name) v\(card.version)")
        } catch {
            agent.status = .error(error.localizedDescription)
            localAgent = agent
            print("Failed to connect to local agent: \(error)")
        }
    }

    /// Disconnect from the local agent
    func disconnectFromLocalAgent() {
        guard var agent = localAgent else { return }
        agent.status = .disconnected
        agent.card = nil
        localAgent = agent
        a2aClient = nil
        connectedAgents.removeAll { $0.id == agent.id }
    }

    func approveAllPending() async {
        guard let client = a2aClient else { return }

        // Approve each pending approval
        for approval in pendingApprovals {
            do {
                try await client.respondToApproval(id: approval.id, approved: true)
            } catch {
                print("Failed to approve \(approval.id): \(error)")
            }
        }

        // Clear local list (will be refreshed on next poll)
        pendingApprovals.removeAll()
    }

    func approveRequest(_ approval: PendingApproval) async {
        guard let client = a2aClient else { return }

        do {
            try await client.respondToApproval(id: approval.id, approved: true)
            pendingApprovals.removeAll { $0.id == approval.id }
        } catch {
            print("Failed to approve \(approval.id): \(error)")
        }
    }

    func denyRequest(_ approval: PendingApproval, reason: String? = nil) async {
        guard let client = a2aClient else { return }

        do {
            try await client.respondToApproval(id: approval.id, approved: false, reason: reason)
            pendingApprovals.removeAll { $0.id == approval.id }
        } catch {
            print("Failed to deny \(approval.id): \(error)")
        }
    }

    func refreshPendingApprovals() async {
        guard let client = a2aClient else { return }

        do {
            let approvals = try await client.fetchPendingApprovals()

            // Convert to PendingApproval format
            pendingApprovals = approvals.map { approval in
                PendingApproval(
                    id: approval.id,
                    taskId: approval.taskId,
                    agentId: localAgent?.id ?? "unknown",
                    toolName: approval.action,
                    description: approval.description,
                    riskLevel: RiskLevel(rawValue: approval.riskLevel) ?? .medium,
                    parameters: [:],
                    createdAt: Date()
                )
            }
        } catch {
            print("Failed to fetch pending approvals: \(error)")
        }
    }

    // MARK: - Conversation Messaging

    /// Send a message in a conversation via A2A protocol
    /// Returns an async stream of text deltas for real-time display
    func sendConversationMessage(
        conversationId: ConversationID,
        content: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let client = a2aClient else {
            throw ConversationError.notConnected
        }

        // Find the conversation
        guard let index = workspace.conversations.firstIndex(where: { $0.id == conversationId }) else {
            throw ConversationError.conversationNotFound
        }

        // Create A2A message with optional context ID for continuity
        let contextId = workspace.conversations[index].contextId
        let message = A2AMessage(
            contextId: contextId,
            role: .user,
            parts: [.text(A2APart.TextPart(text: content))]
        )

        // Capture values needed for the stream
        let conversationIndex = index
        let agentName = localAgent?.card?.name

        // Return a stream that handles both response and state updates
        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }

                do {
                    var fullResponse = ""

                    // Use streaming message for real-time updates (await to cross actor boundary)
                    let stream = await client.sendStreamingMessage(message, contextId: contextId)
                    for try await event in stream {
                        switch event {
                        case .message(let msg):
                            // Extract text from message parts
                            for part in msg.parts {
                                if case .text(let textPart) = part {
                                    let delta = textPart.text
                                    fullResponse += delta
                                    continuation.yield(delta)
                                }
                            }

                        case .task(let task):
                            // Store context ID for future continuity
                            if self.workspace.conversations[conversationIndex].contextId == nil {
                                self.workspace.conversations[conversationIndex].contextId = task.contextId
                            }

                            // Check for input required (approvals)
                            if task.status.state == .inputRequired {
                                await self.refreshPendingApprovals()
                            }

                        case .statusUpdate(let update):
                            if update.status.state == .inputRequired {
                                await self.refreshPendingApprovals()
                            }

                        case .artifactUpdate:
                            // Handle artifacts if needed in future
                            break
                        }
                    }

                    // Add the assistant response to local conversation
                    if !fullResponse.isEmpty {
                        let assistantMessage = ConversationMessage(
                            role: .assistant,
                            content: fullResponse,
                            metadata: MessageMetadata(
                                model: agentName,
                                provider: "AgentKit"
                            )
                        )
                        self.workspace.conversations[conversationIndex].messages.append(assistantMessage)
                        self.workspace.conversations[conversationIndex].updatedAt = Date()
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Non-streaming version for simpler use cases
    func sendConversationMessageBlocking(
        conversationId: ConversationID,
        content: String
    ) async throws -> String {
        guard let client = a2aClient else {
            throw ConversationError.notConnected
        }

        // Find the conversation
        guard let index = workspace.conversations.firstIndex(where: { $0.id == conversationId }) else {
            throw ConversationError.conversationNotFound
        }

        // Create A2A message
        let contextId = workspace.conversations[index].contextId
        let message = A2AMessage(
            contextId: contextId,
            role: .user,
            parts: [.text(A2APart.TextPart(text: content))]
        )

        // Send blocking message
        let task = try await client.sendMessage(message, contextId: contextId, blocking: true)

        // Store context ID for future messages
        if workspace.conversations[index].contextId == nil {
            workspace.conversations[index].contextId = task.contextId
        }

        // Extract response text from task history
        if let lastMessage = task.history?.last,
           lastMessage.role == A2AMessage.Role.agent,
           case .text(let textPart) = lastMessage.parts.first {
            let response = textPart.text

            // Add to local conversation
            let assistantMessage = ConversationMessage(
                role: .assistant,
                content: response,
                metadata: MessageMetadata(
                    model: localAgent?.card?.name,
                    provider: "AgentKit"
                )
            )
            workspace.conversations[index].messages.append(assistantMessage)
            workspace.conversations[index].updatedAt = Date()

            return response
        }

        return ""
    }

    /// Check if A2A client is connected and ready for conversations
    var isAgentConnected: Bool {
        a2aClient != nil && localAgent?.status.isConnected == true
    }

    // MARK: - Document Storage

    /// Load documents from the personal Space
    func loadDocuments() async {
        do {
            let space = try await spaceManager.personalSpace()
            let spaceDocuments = await space.documents()

            // Update workspace documents from Space
            workspace.documents = spaceDocuments

            // If no documents exist, create the welcome document
            if workspace.documents.isEmpty {
                let welcomeDoc = Document(
                    title: "Welcome to Goldeneye",
                    blocks: [
                        .heading(HeadingBlock(content: "Welcome to Goldeneye", level: .h1)),
                        .text(TextBlock(content: "This is your personal knowledge workspace with AI agent integration.")),
                        .text(TextBlock(content: "Create documents, have conversations with agents, and track your coaching sessions—all in one place.")),
                        .heading(HeadingBlock(content: "Getting Started", level: .h2)),
                        .bulletList(BulletListBlock(items: [
                            ListItem(content: "Create your first document using ⌘N"),
                            ListItem(content: "Start a conversation with an agent"),
                            ListItem(content: "Try a coaching session for career or fitness")
                        ]))
                    ],
                    isStarred: true
                )
                try await saveDocument(welcomeDoc)
            }
        } catch {
            print("Failed to load documents: \(error)")
        }
    }

    /// Save a document to the personal Space
    func saveDocument(_ document: Document) async throws {
        let space = try await spaceManager.personalSpace()

        // Check if document exists (update) or is new (add)
        if await space.document(document.id) != nil {
            try await space.updateDocument(document)
        } else {
            try await space.addDocument(document)
        }

        // Update local workspace copy
        if let index = workspace.documents.firstIndex(where: { $0.id == document.id }) {
            workspace.documents[index] = document
        } else {
            workspace.documents.insert(document, at: 0)
        }
    }

    /// Create a new document
    func createDocument(title: String) async -> Document {
        let document = Document.blank(title: title)

        do {
            try await saveDocument(document)
        } catch {
            // If save fails, still add to local workspace for UI
            workspace.documents.insert(document, at: 0)
            print("Failed to save document to Space: \(error)")
        }

        return document
    }

    /// Delete a document from the personal Space
    func deleteDocument(_ id: DocumentID) async {
        do {
            let space = try await spaceManager.personalSpace()
            try await space.removeDocument(id)
        } catch {
            print("Failed to delete document from Space: \(error)")
        }

        // Remove from local workspace
        workspace.documents.removeAll { $0.id == id }
    }

    /// Toggle star status for a document
    func toggleDocumentStar(_ id: DocumentID) async {
        guard let index = workspace.documents.firstIndex(where: { $0.id == id }) else { return }

        workspace.documents[index].isStarred.toggle()

        do {
            try await saveDocument(workspace.documents[index])
        } catch {
            print("Failed to save document star status: \(error)")
        }
    }

    // MARK: - Agent Block Refresh

    /// Refresh an agent block by sending its prompt to the A2A server
    func refreshAgentBlock(documentId: DocumentID, blockId: BlockID) async {
        guard let client = a2aClient else {
            updateAgentBlockError(documentId: documentId, blockId: blockId, error: "Not connected to agent server")
            return
        }

        // Find document and block
        guard let docIndex = workspace.documents.firstIndex(where: { $0.id == documentId }),
              let blockIndex = workspace.documents[docIndex].blocks.firstIndex(where: { $0.id == blockId }),
              case .agent(let agentBlock) = workspace.documents[docIndex].blocks[blockIndex]
        else {
            return
        }

        // Ensure we have a prompt
        guard !agentBlock.prompt.isEmpty else {
            updateAgentBlockError(documentId: documentId, blockId: blockId, error: "No prompt specified")
            return
        }

        // Set loading state
        updateAgentBlockState(documentId: documentId, blockId: blockId, isLoading: true, error: nil)

        // Create A2A message from the block's prompt
        let message = A2AMessage(
            role: .user,
            parts: [.text(A2APart.TextPart(text: agentBlock.prompt))]
        )

        do {
            // Use streaming to get the response
            var fullResponse = ""
            let stream = await client.sendStreamingMessage(message)

            for try await event in stream {
                switch event {
                case .message(let msg):
                    // Accumulate text from message parts
                    for part in msg.parts {
                        if case .text(let textPart) = part {
                            fullResponse += textPart.text
                        }
                    }
                default:
                    break
                }
            }

            // Update block with response
            updateAgentBlockContent(
                documentId: documentId,
                blockId: blockId,
                content: fullResponse,
                lastUpdated: Date()
            )

            // Save document
            try await saveDocument(workspace.documents[docIndex])
        } catch {
            updateAgentBlockError(documentId: documentId, blockId: blockId, error: error.localizedDescription)
        }
    }

    private func updateAgentBlockState(documentId: DocumentID, blockId: BlockID, isLoading: Bool, error: String?) {
        guard let docIndex = workspace.documents.firstIndex(where: { $0.id == documentId }),
              let blockIndex = workspace.documents[docIndex].blocks.firstIndex(where: { $0.id == blockId }),
              case .agent(var agentBlock) = workspace.documents[docIndex].blocks[blockIndex]
        else {
            return
        }

        agentBlock.isLoading = isLoading
        agentBlock.error = error
        workspace.documents[docIndex].blocks[blockIndex] = .agent(agentBlock)
    }

    private func updateAgentBlockContent(documentId: DocumentID, blockId: BlockID, content: String, lastUpdated: Date) {
        guard let docIndex = workspace.documents.firstIndex(where: { $0.id == documentId }),
              let blockIndex = workspace.documents[docIndex].blocks.firstIndex(where: { $0.id == blockId }),
              case .agent(var agentBlock) = workspace.documents[docIndex].blocks[blockIndex]
        else {
            return
        }

        agentBlock.content = content
        agentBlock.lastUpdated = lastUpdated
        agentBlock.isLoading = false
        agentBlock.error = nil
        workspace.documents[docIndex].blocks[blockIndex] = .agent(agentBlock)
    }

    private func updateAgentBlockError(documentId: DocumentID, blockId: BlockID, error: String) {
        guard let docIndex = workspace.documents.firstIndex(where: { $0.id == documentId }),
              let blockIndex = workspace.documents[docIndex].blocks.firstIndex(where: { $0.id == blockId }),
              case .agent(var agentBlock) = workspace.documents[docIndex].blocks[blockIndex]
        else {
            return
        }

        agentBlock.isLoading = false
        agentBlock.error = error
        workspace.documents[docIndex].blocks[blockIndex] = .agent(agentBlock)
    }

    func submitTask(_ prompt: String, to agent: ConnectedAgent) async {
        // Create initial task info
        let task = TaskInfo(
            id: UUID().uuidString,
            agentId: agent.id,
            prompt: prompt,
            state: .submitted,
            createdAt: Date()
        )
        activeTasks.append(task)

        // If we have an A2A client and it's for this agent, send the message
        guard let client = a2aClient, agent.id == localAgent?.id else {
            print("No A2A client available for agent \(agent.id)")
            return
        }

        do {
            // Create A2A message
            let message = A2AMessage(
                role: .user,
                parts: [.text(A2APart.TextPart(text: prompt))]
            )

            // Send message and get task
            let a2aTask = try await client.sendMessage(message)

            // Update our task with the A2A task ID
            if let index = activeTasks.firstIndex(where: { $0.id == task.id }) {
                activeTasks[index].a2aTaskId = a2aTask.id
                activeTasks[index].state = a2aTask.status.state
            }

            print("Task submitted to A2A: \(a2aTask.id)")

            // Poll for completion (or use streaming in the future)
            await pollTaskCompletion(a2aTaskId: a2aTask.id, localTaskId: task.id)
        } catch {
            print("Failed to submit task via A2A: \(error)")
            // Mark task as failed
            if let index = activeTasks.firstIndex(where: { $0.id == task.id }) {
                activeTasks[index].state = .failed
            }
        }
    }

    /// Poll for task completion
    private func pollTaskCompletion(a2aTaskId: String, localTaskId: String) async {
        guard let client = a2aClient else { return }

        var attempts = 0
        let maxAttempts = 300  // 5 minutes max (tasks with approvals can take longer)

        while attempts < maxAttempts {
            do {
                let task = try await client.getTask(id: a2aTaskId)

                // Update local task state
                if let index = activeTasks.firstIndex(where: { $0.id == localTaskId || $0.a2aTaskId == a2aTaskId }) {
                    activeTasks[index].state = task.status.state

                    // If waiting for input (approval), refresh pending approvals
                    if task.status.state == .inputRequired {
                        await refreshPendingApprovals()
                    }

                    // If completed, add to recent and remove from active
                    if task.status.state.isTerminal {
                        activeTasks[index].completedAt = Date()
                        let completedTask = activeTasks.remove(at: index)
                        recentTasks.insert(completedTask, at: 0)

                        // Extract response message if available
                        if let lastMessage = task.history?.last,
                           case .text(let textPart) = lastMessage.parts.first {
                            print("Agent response: \(textPart.text)")
                        }
                        return
                    }
                }

                try await Task.sleep(for: .seconds(1))
                attempts += 1
            } catch {
                print("Error polling task: \(error)")
                return
            }
        }

        print("Task polling timed out")
    }

    // MARK: - Open Space Capture

    /// Submit a quick capture for processing
    func submitCapture(_ content: String, type: CaptureType = .text) async {
        let input = CapturedInput(
            content: content,
            inputType: type
        )

        // Add to processing set
        processingCaptures.insert(input.id)

        // Add placeholder item to timeline immediately
        let placeholderItem = TimelineItemViewModel(
            id: input.id,
            type: .note,
            title: content,
            subtitle: "Processing...",
            timestamp: Date(),
            icon: "text.bubble",
            iconColor: .blue,
            isProcessing: true
        )
        timelineItems.insert(placeholderItem, at: 0)

        // Capture to OpenSpace
        await spaceManager.openSpace.capture(input)

        // Process asynchronously
        let result = await captureProcessor.process(input)

        // Update the timeline item with results
        processingCaptures.remove(input.id)

        if let index = timelineItems.firstIndex(where: { $0.id == input.id }) {
            var updatedItem = timelineItems[index]
            updatedItem.isProcessing = false
            updatedItem.subtitle = formatProcessingResult(result)
            updatedItem.processingResult = result
            timelineItems[index] = updatedItem

            // If tasks were extracted, add them to timeline too
            for task in result.createdTasks {
                let taskItem = TimelineItemViewModel(
                    id: task.id,
                    type: .task,
                    title: task.title,
                    subtitle: "Extracted from capture",
                    timestamp: Date(),
                    icon: "checklist",
                    iconColor: .orange,
                    linkedTask: task
                )
                timelineItems.insert(taskItem, at: 1) // After the note
            }
        }
    }

    /// Load timeline items from OpenSpace and real Calendar
    func loadTimelineItems() async {
        // Load items from space manager
        let items = await spaceManager.openSpace.items()
        var allItems = items.map { item in
            timelineItemViewModel(from: item)
        }

        // Load real calendar events
        let calendarService = CalendarService.shared

        // Request access if needed
        if calendarService.authorizationStatus == .notDetermined {
            _ = await calendarService.requestAccess()
        }

        // If we have calendar access, load real events
        if calendarService.authorizationStatus == .fullAccess ||
           calendarService.authorizationStatus == .authorized {
            await calendarService.refreshEvents()

            // Convert calendar events to timeline items
            let calendarItems = calendarService.todayEvents.map { event in
                TimelineItemViewModel(
                    type: .event,
                    title: event.title,
                    subtitle: event.location,
                    timestamp: event.startDate,
                    icon: event.isAllDay ? "calendar" : "clock",
                    iconColor: event.calendarColor,
                    eventDetails: EventDetails(
                        title: event.title,
                        timeRange: event.timeRange,
                        attendees: event.attendees,
                        notes: event.notes,
                        color: event.calendarColor
                    )
                )
            }

            allItems.append(contentsOf: calendarItems)
        }

        // Sort by timestamp
        timelineItems = allItems.sorted { $0.timestamp < $1.timestamp }

        // Add sample items only if completely empty
        if timelineItems.isEmpty {
            setupSampleTimelineItems()
        }
    }

    private func formatProcessingResult(_ result: ProcessingResult) -> String {
        var parts: [String] = []

        if result.linkedEventId != nil {
            parts.append("Linked to event")
        }

        if !result.createdTasks.isEmpty {
            parts.append("\(result.createdTasks.count) task(s) extracted")
        }

        if !result.learnings.isEmpty {
            parts.append("\(result.learnings.count) learning(s) noted")
        }

        if parts.isEmpty {
            return "Added to timeline"
        }

        return parts.joined(separator: " • ")
    }

    private func timelineItemViewModel(from item: TimelineItem) -> TimelineItemViewModel {
        switch item.type {
        case .event(let event):
            return TimelineItemViewModel(
                id: UUID(uuidString: event.id) ?? UUID(),
                type: .event,
                title: event.title,
                subtitle: formatEventTime(event),
                timestamp: event.startTime,
                icon: "calendar",
                iconColor: .blue,
                eventDetails: EventDetails(
                    title: event.title,
                    timeRange: formatEventTime(event),
                    attendees: event.attendees.map { $0.name },
                    notes: event.notes.first?.content,
                    color: .blue
                )
            )

        case .note(let note):
            return TimelineItemViewModel(
                id: UUID(),
                type: .note,
                title: note.content,
                subtitle: note.linkedEventId != nil ? "Linked to event" : nil,
                timestamp: item.timestamp,
                icon: "text.bubble",
                iconColor: .blue
            )

        case .task(let task):
            return TimelineItemViewModel(
                id: task.id,
                type: .task,
                title: task.title,
                subtitle: task.sourceSpaceId != nil ? "From Space" : nil,
                timestamp: item.timestamp,
                icon: "checklist",
                iconColor: .orange,
                linkedTask: task
            )

        case .reminder(let reminder):
            return TimelineItemViewModel(
                id: reminder.id,
                type: .reminder,
                title: reminder.title,
                subtitle: "Reminder",
                timestamp: reminder.triggerTime,
                icon: "bell",
                iconColor: .yellow
            )

        case .activity(let activity):
            return TimelineItemViewModel(
                id: UUID(),
                type: .activity,
                title: activity.description,
                subtitle: nil,
                timestamp: activity.timestamp,
                icon: "bolt",
                iconColor: .purple
            )

        case .agentUpdate(let update):
            return TimelineItemViewModel(
                id: UUID(),
                type: .activity,
                title: update.message,
                subtitle: update.agentName,
                timestamp: item.timestamp,
                icon: "sparkles",
                iconColor: .purple
            )
        }
    }

    private func formatEventTime(_ event: CalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(formatter.string(from: event.startTime)) - \(formatter.string(from: event.endTime))"
    }

    private func setupSampleTimelineItems() {
        // Add sample items for development
        let today = Date()
        let calendar = Calendar.current

        timelineItems = [
            TimelineItemViewModel(
                id: UUID(),
                type: .event,
                title: "Team Standup",
                subtitle: "Daily sync with engineering team",
                timestamp: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!,
                icon: "video",
                iconColor: .blue,
                eventDetails: EventDetails(
                    title: "Team Standup",
                    timeRange: "10:00 AM - 10:30 AM",
                    attendees: ["Alice", "Bob", "Carol"],
                    notes: "Discuss Q1 priorities",
                    color: .blue
                )
            ),
            TimelineItemViewModel(
                id: UUID(),
                type: .task,
                title: "Review PR #123",
                subtitle: "From Code Space • Assigned by Technical Agent",
                timestamp: calendar.date(bySettingHour: 11, minute: 30, second: 0, of: today)!,
                icon: "checklist",
                iconColor: .orange
            ),
            TimelineItemViewModel(
                id: UUID(),
                type: .activity,
                title: "Research Agent completed literature review",
                subtitle: "3 documents added to Research Space",
                timestamp: calendar.date(bySettingHour: 9, minute: 15, second: 0, of: today)!,
                icon: "sparkles",
                iconColor: .purple
            )
        ]
    }

    // MARK: - Decision Card Operations

    /// Load decision cards from manager
    func loadDecisionCards() async {
        decisionCards = await decisionManager.cards

        // If empty, set up sample cards for development
        if decisionCards.isEmpty {
            await setupSampleDecisionCards()
            decisionCards = await decisionManager.cards
        }
    }

    /// Approve a decision card
    func approveDecisionCard(_ cardId: DecisionCardID, comment: String? = nil) async {
        await decisionManager.approve(cardId, by: "User", comment: comment)
        decisionCards = await decisionManager.cards
    }

    /// Request changes on a decision card
    func requestChangesOnCard(_ cardId: DecisionCardID, comment: String) async {
        await decisionManager.requestChanges(cardId, by: "User", comment: comment)
        decisionCards = await decisionManager.cards
    }

    /// Dismiss a decision card
    func dismissDecisionCard(_ cardId: DecisionCardID, reason: String? = nil) async {
        await decisionManager.dismiss(cardId, by: "User", reason: reason)
        decisionCards = await decisionManager.cards
    }

    /// Add a comment to a decision card
    func addCommentToCard(_ cardId: DecisionCardID, content: String) async {
        let comment = DecisionComment(content: content, author: "User")
        await decisionManager.addComment(cardId, comment: comment)
        decisionCards = await decisionManager.cards
    }

    /// Get pending decision count for badges
    var pendingDecisionCount: Int {
        decisionCards.filter { $0.isActionable }.count
    }

    // MARK: - Review Operations

    /// All reviews loaded from storage
    @Published var reviews: [Review] = []

    /// Load reviews (from storage or sample data for development)
    func loadReviews(status: ReviewStatus? = nil, searchText: String = "") async {
        // For development, set up sample reviews if empty
        if reviews.isEmpty {
            setupSampleReviews()
        }

        // Filter would happen here with real storage
    }

    /// Open a draft review for comments and approvals
    func openReview(_ reviewId: ReviewID) async {
        guard let index = reviews.firstIndex(where: { $0.id == reviewId }) else { return }
        guard reviews[index].status == .draft else { return }

        reviews[index].status = .open
        reviews[index].updatedAt = Date()
    }

    /// Approve a review
    func approveReview(_ reviewId: ReviewID, comment: String? = nil) async {
        guard let index = reviews.firstIndex(where: { $0.id == reviewId }) else { return }

        let approval = Approval(
            reviewer: Author(name: "You"),
            status: .approved,
            comment: comment
        )
        reviews[index].approvals.append(approval)
        reviews[index].status = .approved
        reviews[index].updatedAt = Date()
    }

    /// Request changes on a review
    func requestChangesOnReview(_ reviewId: ReviewID, comment: String) async {
        guard let index = reviews.firstIndex(where: { $0.id == reviewId }) else { return }

        let approval = Approval(
            reviewer: Author(name: "You"),
            status: .changesRequested,
            comment: comment
        )
        reviews[index].approvals.append(approval)
        reviews[index].status = .changesRequested
        reviews[index].updatedAt = Date()
    }

    /// Merge an approved review
    func mergeReview(_ reviewId: ReviewID) async {
        guard let index = reviews.firstIndex(where: { $0.id == reviewId }) else { return }
        guard reviews[index].status == .approved else { return }

        reviews[index].status = .merged
        reviews[index].mergedAt = Date()
        reviews[index].updatedAt = Date()
    }

    /// Get a review by ID
    func getReview(_ reviewId: ReviewID) -> Review? {
        reviews.first { $0.id == reviewId }
    }

    private func setupSampleReviews() {
        // Sample reviews for development
        let review1 = Review(
            title: "Update documentation for Q4 release",
            description: "Comprehensive update to the user guide and API documentation.",
            author: Author.agent("Research Agent"),
            baseCommit: "abc123",
            headCommit: "def456",
            targetBranch: "main",
            sourceBranch: "docs/q4-update",
            status: .open,
            summary: ReviewSummary(
                overview: "Added new sections for agent configuration and updated API examples.",
                filesChanged: 5,
                additions: 342,
                deletions: 87,
                keyChanges: [
                    KeyChange(type: .content, description: "Added agent setup guide", files: ["docs/agents.md"]),
                    KeyChange(type: .content, description: "Updated API reference", files: ["docs/api.md"])
                ],
                impact: .moderate
            ),
            changes: []
        )

        let review2 = Review(
            title: "Add fitness tracking integration",
            description: "Connects to Apple Health for workout data.",
            author: Author.agent("Technical Agent"),
            baseCommit: "ghi789",
            headCommit: "jkl012",
            targetBranch: "main",
            sourceBranch: "feature/fitness",
            status: .draft,
            summary: ReviewSummary(
                overview: "New fitness tracking module with Health app integration.",
                filesChanged: 8,
                additions: 567,
                deletions: 12,
                keyChanges: [
                    KeyChange(type: .code, description: "Added HealthKit integration", files: ["Sources/Fitness/HealthService.swift"])
                ],
                impact: .major
            ),
            changes: []
        )

        reviews = [review1, review2]
    }

    private func setupSampleDecisionCards() async {
        // Sample decision cards for development
        let card1 = DecisionCard(
            title: "Publish Draft: Q4 Strategy Document",
            description: "Research Agent completed the Q4 strategy document based on your notes. Ready for review before publishing to the Strategy Space.",
            sourceType: .document,
            sourceId: "doc-strategy-q4",
            requestedBy: "Research Agent"
        )

        let card2 = DecisionCard(
            title: "Execute: Database Schema Update",
            description: "Technical Agent wants to run database migration to add user preferences table. This affects the Users Space.",
            sourceType: .agentAction,
            sourceId: "task-db-migration",
            comments: [
                DecisionComment(content: "Tested in staging - migration completes in ~30 seconds with no downtime.", author: "Technical Agent")
            ],
            requestedBy: "Technical Agent"
        )

        let card3 = DecisionCard(
            title: "Generated: Weekly Summary Email",
            description: "Created your weekly summary email based on completed tasks and upcoming calendar events.",
            sourceType: .generatedContent,
            requestedBy: "Concierge Agent"
        )

        _ = await decisionManager.submit(card1)
        _ = await decisionManager.submit(card2)
        _ = await decisionManager.submit(card3)
    }

    // MARK: - Agent Registry Operations

    /// Load registered agents
    func loadRegisteredAgents() async {
        registeredAgents = await agentRegistry.agents

        // If empty, set up sample agents for development
        if registeredAgents.isEmpty {
            await setupSampleAgents()
            registeredAgents = await agentRegistry.agents
        }
    }

    /// Register a new agent
    func registerAgent(_ agent: RegisteredAgent) async {
        await agentRegistry.register(agent)
        registeredAgents = await agentRegistry.agents
    }

    /// Get available agents (ready to accept tasks)
    var availableAgents: [RegisteredAgent] {
        registeredAgents.filter { $0.status.canAcceptTasks }
    }

    private func setupSampleAgents() async {
        // Sample agents matching the profiles from agent_profiles.md
        let concierge = RegisteredAgent(
            id: AgentID("concierge"),
            name: "Concierge",
            profile: .concierge,
            capabilities: [.routing, .scheduling, .conversation, .summarization],
            status: .available
        )

        let researchAgent = RegisteredAgent(
            id: AgentID("research-agent"),
            name: "Research Agent",
            profile: .founder,
            capabilities: [.research, .synthesis, .retrieval, .writing],
            status: .available,
            ownedSpaces: [SpaceID("research-space")]
        )

        let technicalAgent = RegisteredAgent(
            id: AgentID("technical-agent"),
            name: "Technical Agent",
            profile: .integrator,
            capabilities: [.coding, .debugging, .architecture, .integration],
            status: .available
        )

        let careerCoach = RegisteredAgent(
            id: AgentID("career-coach"),
            name: "Career Coach",
            profile: .coach,
            capabilities: [.careerCoaching, .conversation, .patternRecognition],
            status: .available
        )

        await agentRegistry.register(concierge)
        await agentRegistry.register(researchAgent)
        await agentRegistry.register(technicalAgent)
        await agentRegistry.register(careerCoach)
    }

    // MARK: - Delegation Operations

    /// Load active delegations
    func loadDelegations() async {
        activeDelegations = await delegationManager.activeDelegations
    }

    /// Delegate a task to another agent
    func delegateTask(
        _ task: TimelineTask,
        from sourceId: AgentID,
        to targetId: AgentID,
        reason: String
    ) async -> AgentDelegation {
        let delegation = await delegationManager.delegate(
            task: task,
            from: sourceId,
            to: targetId,
            reason: reason
        )
        activeDelegations = await delegationManager.activeDelegations
        return delegation
    }

    /// Delegate to the best available agent for capabilities
    func delegateToCapableAgent(
        _ task: TimelineTask,
        from sourceId: AgentID,
        capabilities: [AgentCapability],
        reason: String
    ) async -> AgentDelegation? {
        let delegation = await delegationManager.delegateToCapableAgent(
            task: task,
            from: sourceId,
            requiredCapabilities: capabilities,
            reason: reason
        )
        activeDelegations = await delegationManager.activeDelegations
        return delegation
    }

    /// Accept a pending delegation
    func acceptDelegation(_ delegationId: UUID) async {
        await delegationManager.accept(delegationId)
        activeDelegations = await delegationManager.activeDelegations
    }

    /// Complete a delegation
    func completeDelegation(_ delegationId: UUID, result: TaskResult) async {
        await delegationManager.complete(delegationId, result: result)
        activeDelegations = await delegationManager.activeDelegations
    }
}

// MARK: - Supporting Types

enum SidebarItem: String, CaseIterable, Identifiable {
    // Primary - Open Space is the default entry point
    case openSpace

    // Spaces (replaces Knowledge Workspace)
    case spaces
    case documents
    case conversations

    // Operations
    case tasks
    case decisions
    case approvals

    // Infrastructure
    case agents
    case connections
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openSpace: "Open Space"
        case .spaces: "Spaces"
        case .documents: "Documents"
        case .conversations: "Conversations"
        case .tasks: "Tasks"
        case .decisions: "Decisions"
        case .approvals: "Approvals"
        case .agents: "Agents"
        case .connections: "Connections"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .openSpace: "square.and.pencil"
        case .spaces: "folder"
        case .documents: "doc.text"
        case .conversations: "bubble.left.and.bubble.right"
        case .tasks: "checklist"
        case .decisions: "checkmark.seal"
        case .approvals: "checkmark.shield"
        case .agents: "person.2"
        case .connections: "link"
        case .settings: "gearshape"
        }
    }

    /// Group for sidebar sections
    var group: SidebarGroup {
        switch self {
        case .openSpace:
            return .primary
        case .spaces, .documents, .conversations:
            return .workspace
        case .tasks, .decisions, .approvals:
            return .activity
        case .agents, .connections, .settings:
            return .infrastructure
        }
    }

    static var primaryItems: [SidebarItem] {
        [.openSpace]
    }

    static var workspaceItems: [SidebarItem] {
        [.spaces, .documents, .conversations]
    }

    static var activityItems: [SidebarItem] {
        [.tasks, .decisions, .approvals]
    }

    static var infrastructureItems: [SidebarItem] {
        [.agents, .connections, .settings]
    }
}

enum SidebarGroup: String {
    case primary = ""  // No header for primary items
    case workspace = "Spaces"
    case activity = "Activity"
    case infrastructure = "Infrastructure"
}

// MARK: - Workspace State

/// Observable state for the workspace (documents, conversations, coaching)
class WorkspaceState: ObservableObject {
    @Published var documents: [Document] = []
    @Published var conversations: [Conversation] = []
    @Published var coachingSessions: [CoachingSession] = []
    @Published var folders: [Folder] = []
    @Published var tags: [Tag] = []

    // Starred items across all types
    var starredDocuments: [Document] {
        documents.filter { $0.isStarred }
    }

    var starredConversations: [Conversation] {
        conversations.filter { $0.isStarred }
    }

    // Recent items (last 7 days)
    var recentDocuments: [Document] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return documents.filter { $0.updatedAt > cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var recentConversations: [Conversation] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return conversations.filter { $0.updatedAt > cutoff }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // Active coaching sessions
    var activeCoachingSessions: [CoachingSession] {
        coachingSessions.filter { $0.isActive }
    }
}

struct ConnectedAgent: Identifiable, Hashable {
    let id: String
    var name: String
    var url: URL
    var status: AgentConnectionStatus
    var card: AgentCard?

    static func == (lhs: ConnectedAgent, rhs: ConnectedAgent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum AgentConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var color: Color {
        switch self {
        case .disconnected: .secondary
        case .connecting: .orange
        case .connected: .green
        case .error: .red
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct TaskInfo: Identifiable, Hashable {
    let id: String
    let agentId: String
    let prompt: String
    var state: TaskState
    let createdAt: Date
    var completedAt: Date?
    var messages: [Message] = []

    /// A2A protocol task ID (may differ from local ID)
    var a2aTaskId: String?

    static func == (lhs: TaskInfo, rhs: TaskInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PendingApproval: Identifiable, Hashable {
    let id: String
    let taskId: String
    let agentId: String
    let toolName: String
    let description: String
    let riskLevel: RiskLevel
    let parameters: [String: String]
    let createdAt: Date

    static func == (lhs: PendingApproval, rhs: PendingApproval) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Space View Model

/// SwiftUI-friendly view model for Space display
struct SpaceViewModel: Identifiable {
    let id: String
    let name: String
    let description: String?
    let ownerName: String
    let icon: String
    let color: Color
    let documentCount: Int
    let contributorCount: Int
    let updatedAt: Date
    var isStarred: Bool
    var path: URL?

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        ownerName: String = "You",
        icon: String = "folder",
        color: Color = .blue,
        documentCount: Int = 0,
        contributorCount: Int = 1,
        updatedAt: Date = Date(),
        isStarred: Bool = false,
        path: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.ownerName = ownerName
        self.icon = icon
        self.color = color
        self.documentCount = documentCount
        self.path = path
        self.contributorCount = contributorCount
        self.updatedAt = updatedAt
        self.isStarred = isStarred
    }

    /// Create from AgentKit Space
    init(from space: Space) async {
        self.id = space.id.rawValue
        self.name = space.name
        self.description = space.description
        self.ownerName = await space.owner.displayName
        self.icon = space.icon
        self.color = SpaceViewModel.color(from: space.color)
        self.documentCount = await space.documents().count
        self.contributorCount = await space.contributors().count + 1
        self.updatedAt = Date()  // TODO: Get from space
        self.isStarred = await space.isStarred
    }

    private static func color(from spaceColor: SpaceColor) -> Color {
        switch spaceColor {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .cyan: return .cyan
        case .red: return .red
        case .yellow: return .yellow
        case .gray: return .gray
        }
    }
}

// MARK: - Conversation Errors

enum ConversationError: Error, LocalizedError {
    case notConnected
    case conversationNotFound
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to agent. Please connect first."
        case .conversationNotFound:
            return "Conversation not found."
        case .sendFailed(let reason):
            return "Failed to send message: \(reason)"
        }
    }
}
