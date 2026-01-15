import AgentKit
import SwiftUI

// MARK: - Space Detail View

/// Detailed view of a Space showing channel chat, documents, and markdown viewer
struct SpaceDetailView: View {
    let spaceId: SpaceID
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: DetailTab = .chat
    @State private var selectedDocument: Document?
    @State private var messageInput = ""

    enum DetailTab: String, CaseIterable {
        case chat = "Chat"
        case documents = "Documents"
        case both = "Split View"
    }

    var space: SpaceViewModel? {
        appState.spaces.first { SpaceID($0.id) == spaceId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            spaceHeader

            Divider()

            // Tab selector
            tabSelector

            Divider()

            // Content based on selected tab
            contentView
        }
        .navigationTitle(space?.name ?? "Space")
        .task {
            await loadSpaceContent()
        }
    }

    // MARK: - Header

    private var spaceHeader: some View {
        HStack {
            if let space = space {
                // Space icon
                RoundedRectangle(cornerRadius: 8)
                    .fill(space.color.gradient)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: space.icon)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(space.name)
                        .font(.headline)

                    if let description = space.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Stats
                HStack(spacing: 16) {
                    Label("\(space.documentCount)", systemImage: "doc.text")
                    Label("\(space.contributorCount)", systemImage: "person.2")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Edit button
                Button(action: { /* TODO: Edit space */ }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit space settings")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack {
                        Image(systemName: tabIcon(for: tab))
                        Text(tab.rawValue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func tabIcon(for tab: DetailTab) -> String {
        switch tab {
        case .chat: return "message"
        case .documents: return "doc.text.fill"
        case .both: return "rectangle.split.2x1"
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .chat:
            chatView
        case .documents:
            documentsView
        case .both:
            splitView
        }
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // TODO: Real messages from channel
                    ForEach(sampleMessages) { message in
                        SpaceMessageBubble(message: message)
                    }
                }
                .padding()
            }

            Divider()

            // Input field
            HStack(spacing: 12) {
                TextField("Type a message...", text: $messageInput)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(messageInput.isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Documents View

    private var documentsView: some View {
        HSplitView {
            // Document tree
            documentTree
                .frame(minWidth: 200, idealWidth: 250)

            // Document viewer
            if let doc = selectedDocument {
                documentViewer(for: doc)
                    .frame(minWidth: 400)
            } else {
                emptyDocumentState
            }
        }
    }

    private var documentTree: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tree header
            HStack {
                Text("Documents")
                    .font(.headline)

                Spacer()

                Button(action: { /* TODO: New document */ }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Document list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    // TODO: Real documents from space
                    ForEach(sampleDocuments) { doc in
                        SpaceDocumentRow(document: doc, isSelected: selectedDocument?.id == doc.id)
                            .onTapGesture {
                                selectedDocument = doc
                            }
                    }
                }
                .padding(8)
            }
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func documentViewer(for document: Document) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Document header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.title3.weight(.semibold))

                    Text("Updated \(document.updatedAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { /* TODO: Edit document */ }) {
                    Image(systemName: "pencil.circle")
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Markdown renderer
            ScrollView {
                MarkdownView(document: document)
                    .padding()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyDocumentState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Select a document")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Choose a document from the list to view it here")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Split View

    private var splitView: some View {
        HSplitView {
            // Chat on left
            chatView
                .frame(minWidth: 300, idealWidth: 400)

            // Documents on right
            documentsView
                .frame(minWidth: 400)
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageInput.isEmpty else { return }

        // TODO: Send message to channel
        print("Sending message: \(messageInput)")

        messageInput = ""
    }

    private func loadSpaceContent() async {
        // TODO: Load real space content
        // - Load channel messages
        // - Load documents
        // - Load participants
    }
}

// MARK: - Message Bubble

private struct SpaceMessageBubble: View {
    let message: SampleMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(message.isUser ? Color.blue.gradient : Color.purple.gradient)
                .frame(width: 32, height: 32)
                .overlay {
                    Text(message.senderInitial)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.sender)
                        .font(.subheadline.weight(.semibold))

                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .font(.body)

                // Tool call indicator
                if message.isTool {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.caption)
                        Text("Tool: \(message.toolName ?? "unknown")")
                            .font(.caption)
                    }
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

// MARK: - Document Row

private struct SpaceDocumentRow: View {
    let document: Document
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: documentIcon)
                .foregroundStyle(.blue)
                .frame(width: 20)

            Text(document.title.isEmpty ? "Untitled" : document.title)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var documentIcon: String {
        // Determine icon based on document content
        return "doc.text"
    }
}

// MARK: - Markdown View

private struct MarkdownView: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(document.blocks) { block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: Block) -> some View {
        switch block {
        case .text(let textBlock):
            Text(textBlock.content)
                .font(fontFor(textBlock.style))

        case .heading(let heading):
            Text(heading.content)
                .font(headingFont(for: heading.level))
                .fontWeight(.bold)

        case .code(let code):
            Text(code.content)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

        case .quote(let quote):
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(quote.content)
                        .font(.body.italic())

                    if let attribution = quote.attribution {
                        Text("— \(attribution)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)

        case .bulletList(let list):
            ForEach(list.items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item.content)
                }
            }

        case .numberedList(let list):
            ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .fontWeight(.semibold)
                    Text(item.content)
                }
            }

        case .divider:
            Divider()

        case .callout(let callout):
            HStack(alignment: .top, spacing: 12) {
                Text(callout.icon)
                    .font(.title2)

                Text(callout.content)
            }
            .padding(12)
            .background(calloutColor(for: callout.style), in: RoundedRectangle(cornerRadius: 8))

        default:
            Text(block.extractContent())
        }
    }

    private func fontFor(_ style: TextStyle) -> Font {
        switch style {
        case .body: return .body
        case .caption: return .caption
        case .strong: return .body.weight(.semibold)
        }
    }

    private func headingFont(for level: HeadingLevel) -> Font {
        switch level {
        case .h1: return .largeTitle
        case .h2: return .title
        case .h3: return .title3
        }
    }

    private func calloutColor(for style: CalloutStyle) -> Color {
        switch style {
        case .info: return .blue.opacity(0.1)
        case .warning: return .orange.opacity(0.1)
        case .success: return .green.opacity(0.1)
        case .error: return .red.opacity(0.1)
        }
    }
}

// MARK: - Sample Data (for demo)

private struct SampleMessage: Identifiable {
    let id = UUID()
    let sender: String
    let content: String
    let timestamp: Date
    let isUser: Bool
    let isTool: Bool
    let toolName: String?

    var senderInitial: String {
        String(sender.prefix(1))
    }
}

private let sampleMessages: [SampleMessage] = [
    SampleMessage(sender: "You", content: "Let's review the architecture for the new channel system", timestamp: Date().addingTimeInterval(-3600), isUser: true, isTool: false, toolName: nil),
    SampleMessage(sender: "Technical Agent", content: "I'll analyze the codebase structure", timestamp: Date().addingTimeInterval(-3500), isUser: false, isTool: true, toolName: "analyze_code"),
    SampleMessage(sender: "Technical Agent", content: "The architecture looks good. I'd suggest adding the EventBus enhancement first, then wire up the ChannelView.", timestamp: Date().addingTimeInterval(-3400), isUser: false, isTool: false, toolName: nil),
]

private let sampleDocuments: [Document] = [
    Document(title: "Architecture Overview", blocks: [
        .heading(HeadingBlock(content: "System Architecture", level: .h1)),
        .text(TextBlock(content: "This document describes the overall system architecture.")),
    ]),
    Document(title: "Meeting Notes", blocks: [
        .heading(HeadingBlock(content: "Team Meeting - Jan 14", level: .h2)),
    ]),
    Document(title: "TODO List", blocks: [
        .heading(HeadingBlock(content: "Tasks", level: .h2)),
    ]),
]
