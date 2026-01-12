import AgentKit
import SwiftUI

// MARK: - Document Editor View

/// Block-based document editor inspired by Craft/Notion
struct DocumentEditorView: View {
    @Binding var document: Document
    @EnvironmentObject private var appState: AppState
    @State private var focusedBlockId: BlockID?
    @State private var showBlockMenu = false
    @State private var blockMenuPosition: CGPoint = .zero
    @State private var insertIndex: Int = 0
    @State private var saveTask: Task<Void, Never>?
    @State private var isDropTargeted = false
    @State private var showImportSheet = false
    @State private var importContent: ImportContent?

    var body: some View {
        mainContent
            .background(Color(.textBackgroundColor))
            .overlay { dropTargetOverlay }
            .overlay { blockMenuOverlay }
            .onDrop(of: [.fileURL, .plainText, .utf8PlainText], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
            .sheet(isPresented: $showImportSheet) { importSheet }
            .onChange(of: document.updatedAt) { _, _ in debouncedSave() }
    }

    // MARK: - View Components

    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DocumentTitleField(title: $document.title)
                    .padding(.bottom, 16)

                blocksContent

                AddBlockButton { showBlockMenuAt(index: document.blocks.count) }
                    .padding(.top, 8)

                if document.blocks.isEmpty {
                    ImportDropHint()
                        .padding(.top, 40)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var blocksContent: some View {
        ForEach(Array(document.blocks.enumerated()), id: \.element.id) { index, block in
            BlockRow(
                block: binding(for: index),
                documentId: document.id,
                isFocused: focusedBlockId == block.id,
                onFocus: { focusedBlockId = block.id },
                onAddBlock: { showBlockMenuAt(index: index + 1) },
                onDelete: { deleteBlock(at: index) },
                onMoveUp: index > 0 ? { moveBlock(from: index, to: index - 1) } : nil,
                onMoveDown: index < document.blocks.count - 1 ? { moveBlock(from: index, to: index + 1) } : nil
            )
        }
    }

    @ViewBuilder
    private var dropTargetOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                .background(Color.accentColor.opacity(0.05))
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.largeTitle)
                        Text("Drop to import")
                            .font(.headline)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .padding(8)
        }
    }

    @ViewBuilder
    private var blockMenuOverlay: some View {
        if showBlockMenu {
            BlockTypeMenu(
                position: blockMenuPosition,
                onSelect: { type in
                    insertBlock(type: type, at: insertIndex)
                    showBlockMenu = false
                },
                onDismiss: { showBlockMenu = false }
            )
        }
    }

    @ViewBuilder
    private var importSheet: some View {
        if let content = importContent {
            ImportPreviewSheet(
                content: content,
                onImport: { blocks in
                    document.blocks.append(contentsOf: blocks)
                    document.updatedAt = Date()
                    showImportSheet = false
                    importContent = nil
                },
                onCancel: {
                    showImportSheet = false
                    importContent = nil
                }
            )
        }
    }

    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(for: .seconds(1))
                try await appState.saveDocument(document)
            } catch {
                // Cancelled or save failed - ignore
            }
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // Handle file URLs
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }

                    Task { @MainActor in
                        await processFileImport(url: url)
                    }
                }
            }
            // Handle plain text
            else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    guard let text = string else { return }

                    Task { @MainActor in
                        importContent = ImportContent(
                            source: .clipboard,
                            rawText: text,
                            suggestedTitle: nil
                        )
                        showImportSheet = true
                    }
                }
            }
        }
    }

    private func processFileImport(url: URL) async {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            importContent = ImportContent(
                source: .file(url.lastPathComponent),
                rawText: content,
                suggestedTitle: url.deletingPathExtension().lastPathComponent
            )
            showImportSheet = true
        } catch {
            print("Failed to read file: \(error)")
        }
    }

    // MARK: - Helpers

    private func binding(for index: Int) -> Binding<Block> {
        Binding(
            get: { document.blocks[index] },
            set: { document.blocks[index] = $0 }
        )
    }

    private func showBlockMenuAt(index: Int) {
        insertIndex = index
        showBlockMenu = true
    }

    private func insertBlock(type: BlockType, at index: Int) {
        let newBlock = type.createBlock()
        document.blocks.insert(newBlock, at: index)
        focusedBlockId = newBlock.id
        document.updatedAt = Date()
    }

    private func deleteBlock(at index: Int) {
        guard document.blocks.count > 1 else { return }
        document.blocks.remove(at: index)
        document.updatedAt = Date()
    }

    private func moveBlock(from source: Int, to destination: Int) {
        let block = document.blocks.remove(at: source)
        document.blocks.insert(block, at: destination)
        document.updatedAt = Date()
    }
}

// MARK: - Document Title

struct DocumentTitleField: View {
    @Binding var title: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Untitled", text: $title, axis: .vertical)
            .font(.system(size: 32, weight: .bold))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .lineLimit(1...3)
    }
}

// MARK: - Block Row

struct BlockRow: View {
    @Binding var block: Block
    let documentId: DocumentID
    let isFocused: Bool
    let onFocus: () -> Void
    let onAddBlock: () -> Void
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Block handle (visible on hover)
            BlockHandle(
                isVisible: isHovered || isFocused,
                onAdd: onAddBlock,
                onDelete: onDelete,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )

            // Block content
            BlockContentView(block: $block, documentId: documentId, isFocused: isFocused)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Block Handle

struct BlockHandle: View {
    let isVisible: Bool
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            // Add button
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            // Drag handle with menu
            Menu {
                Button("Delete", role: .destructive, action: onDelete)
                Divider()
                if let onMoveUp {
                    Button("Move Up", action: onMoveUp)
                }
                if let onMoveDown {
                    Button("Move Down", action: onMoveDown)
                }
                Divider()
                Button("Duplicate") { /* TODO */ }
                Button("Turn into...") { /* TODO */ }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(width: 40)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isVisible)
    }
}

// MARK: - Block Content View

struct BlockContentView: View {
    @Binding var block: Block
    let documentId: DocumentID
    let isFocused: Bool

    var body: some View {
        switch block {
        case .text(let textBlock):
            TextBlockView(
                block: binding(for: textBlock),
                isFocused: isFocused,
                onConvertBlock: { type in
                    block = type.createBlock()
                }
            )
        case .heading(let headingBlock):
            HeadingBlockView(block: binding(for: headingBlock), isFocused: isFocused)
        case .bulletList(let listBlock):
            BulletListBlockView(block: binding(for: listBlock), isFocused: isFocused)
        case .numberedList(let listBlock):
            NumberedListBlockView(block: binding(for: listBlock), isFocused: isFocused)
        case .todo(let todoBlock):
            TodoBlockView(block: binding(for: todoBlock), isFocused: isFocused)
        case .code(let codeBlock):
            CodeBlockView(block: binding(for: codeBlock), isFocused: isFocused)
        case .quote(let quoteBlock):
            QuoteBlockView(block: binding(for: quoteBlock), isFocused: isFocused)
        case .divider:
            DividerBlockView()
        case .callout(let calloutBlock):
            CalloutBlockView(block: binding(for: calloutBlock), isFocused: isFocused)
        case .image(let imageBlock):
            ImageBlockView(block: binding(for: imageBlock))
        case .agent(let agentBlock):
            AgentBlockView(block: binding(for: agentBlock), documentId: documentId)
        }
    }

    // Create bindings that update the parent block
    private func binding<T>(for innerBlock: T) -> Binding<T> {
        Binding(
            get: { innerBlock },
            set: { newValue in
                // Update the block based on type
                if let text = newValue as? TextBlock {
                    block = .text(text)
                } else if let heading = newValue as? HeadingBlock {
                    block = .heading(heading)
                } else if let bullet = newValue as? BulletListBlock {
                    block = .bulletList(bullet)
                } else if let numbered = newValue as? NumberedListBlock {
                    block = .numberedList(numbered)
                } else if let todo = newValue as? TodoBlock {
                    block = .todo(todo)
                } else if let code = newValue as? CodeBlock {
                    block = .code(code)
                } else if let quote = newValue as? QuoteBlock {
                    block = .quote(quote)
                } else if let callout = newValue as? CalloutBlock {
                    block = .callout(callout)
                } else if let image = newValue as? ImageBlock {
                    block = .image(image)
                } else if let agent = newValue as? AgentBlock {
                    block = .agent(agent)
                }
            }
        )
    }
}

// MARK: - Individual Block Views

struct TextBlockView: View {
    @Binding var block: TextBlock
    let isFocused: Bool
    var onConvertBlock: ((BlockType) -> Void)? = nil

    @State private var showSlashMenu = false

    /// Extract the slash command query (text after "/")
    private var slashQuery: String? {
        guard block.content.hasPrefix("/") else { return nil }
        return String(block.content.dropFirst())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Type '/' for commands...", text: $block.content, axis: .vertical)
                .textFieldStyle(.plain)
                .font(block.style.font)
                .lineLimit(1...100)
                .onChange(of: block.content) { _, newValue in
                    showSlashMenu = newValue.hasPrefix("/")
                }

            // Slash command menu appears below the text field
            if showSlashMenu, let query = slashQuery {
                SlashCommandMenu(
                    query: query,
                    onSelect: { type in
                        showSlashMenu = false
                        block.content = "" // Clear the slash command
                        onConvertBlock?(type)
                    },
                    onDismiss: {
                        showSlashMenu = false
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: showSlashMenu)
    }
}

struct HeadingBlockView: View {
    @Binding var block: HeadingBlock
    let isFocused: Bool

    var body: some View {
        TextField("Heading", text: $block.content, axis: .vertical)
            .textFieldStyle(.plain)
            .font(block.level.font)
            .lineLimit(1...5)
    }
}

struct BulletListBlockView: View {
    @Binding var block: BulletListBlock
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(block.items.enumerated()), id: \.element.id) { index, _ in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    TextField("List item", text: itemBinding(at: index), axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...10)
                }
            }

            // Add item button
            Button(action: addItem) {
                HStack(spacing: 8) {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text("Add item")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func itemBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { block.items[index].content },
            set: { block.items[index].content = $0 }
        )
    }

    private func addItem() {
        block.items.append(ListItem(content: ""))
    }
}

struct NumberedListBlockView: View {
    @Binding var block: NumberedListBlock
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(block.items.enumerated()), id: \.element.id) { index, _ in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    TextField("List item", text: itemBinding(at: index), axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...10)
                }
            }

            Button(action: addItem) {
                HStack(spacing: 8) {
                    Text("\(block.items.count + 1).")
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, alignment: .trailing)
                    Text("Add item")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func itemBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { block.items[index].content },
            set: { block.items[index].content = $0 }
        )
    }

    private func addItem() {
        block.items.append(ListItem(content: ""))
    }
}

struct TodoBlockView: View {
    @Binding var block: TodoBlock
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(block.items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Button(action: { toggleItem(at: index) }) {
                        Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.isCompleted ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    TextField("To-do", text: itemBinding(at: index), axis: .vertical)
                        .textFieldStyle(.plain)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .lineLimit(1...10)
                }
            }

            Button(action: addItem) {
                HStack(spacing: 8) {
                    Image(systemName: "square")
                        .foregroundStyle(.tertiary)
                    Text("Add to-do")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func itemBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { block.items[index].content },
            set: { block.items[index].content = $0 }
        )
    }

    private func toggleItem(at index: Int) {
        block.items[index].isCompleted.toggle()
    }

    private func addItem() {
        block.items.append(TodoItem(content: ""))
    }
}

struct CodeBlockView: View {
    @Binding var block: CodeBlock
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Language selector
            HStack {
                TextField("Language", text: languageBinding)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 100)
                Spacer()
            }

            // Code content
            TextEditor(text: $block.content)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 60)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { block.language ?? "" },
            set: { block.language = $0.isEmpty ? nil : $0 }
        )
    }
}

struct QuoteBlockView: View {
    @Binding var block: QuoteBlock
    let isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Quote", text: $block.content, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body.italic())
                    .lineLimit(1...20)

                TextField("Attribution", text: attributionBinding)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var attributionBinding: Binding<String> {
        Binding(
            get: { block.attribution ?? "" },
            set: { block.attribution = $0.isEmpty ? nil : $0 }
        )
    }
}

struct DividerBlockView: View {
    var body: some View {
        Divider()
            .padding(.vertical, 8)
    }
}

struct CalloutBlockView: View {
    @Binding var block: CalloutBlock
    let isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(block.icon)
                .font(.title2)

            TextField("Callout", text: $block.content, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...10)
        }
        .padding(12)
        .background(block.style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ImageBlockView: View {
    @Binding var block: ImageBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = block.url {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.controlBackgroundColor))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay {
                            ProgressView()
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Placeholder for adding image
                Button(action: { /* TODO: Image picker */ }) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                Text("Add Image")
                            }
                            .foregroundStyle(.secondary)
                        }
                }
                .buttonStyle(.plain)
            }

            // Caption
            TextField("Caption", text: captionBinding)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var captionBinding: Binding<String> {
        Binding(
            get: { block.caption ?? "" },
            set: { block.caption = $0.isEmpty ? nil : $0 }
        )
    }
}

struct AgentBlockView: View {
    @Binding var block: AgentBlock
    let documentId: DocumentID
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Agent Block")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if block.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let lastUpdated = block.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Button(action: { refreshBlock() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(block.isLoading || block.prompt.isEmpty)
            }

            // Prompt
            TextField("What should this agent maintain?", text: $block.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1...3)

            // Content
            if !block.content.isEmpty {
                Text(block.content)
                    .font(.body)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Error
            if let error = block.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }

    private func refreshBlock() {
        Task {
            await appState.refreshAgentBlock(documentId: documentId, blockId: block.id)
        }
    }
}

// MARK: - Add Block Button

struct AddBlockButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Add block")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Block Type Menu

struct BlockTypeMenu: View {
    let position: CGPoint
    let onSelect: (BlockType) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.001)
                .onTapGesture { onDismiss() }

            // Menu
            VStack(alignment: .leading, spacing: 0) {
                Text("Add Block")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()

                ForEach(BlockType.allCases, id: \.self) { type in
                    Button(action: { onSelect(type) }) {
                        HStack(spacing: 12) {
                            Image(systemName: type.icon)
                                .frame(width: 20)
                            Text(type.displayName)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 200)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        }
    }
}

// MARK: - Slash Command Menu

struct SlashCommandMenu: View {
    let query: String
    let onSelect: (BlockType) -> Void
    let onDismiss: () -> Void
    @State private var selectedIndex = 0

    var filteredTypes: [BlockType] {
        if query.isEmpty {
            return BlockType.allCases.filter { $0 != .text }
        }
        return BlockType.allCases.filter { $0.matches(query: query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Turn into")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↑↓ to navigate, ↵ to select")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if filteredTypes.isEmpty {
                Text("No matching blocks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filteredTypes.enumerated()), id: \.element) { index, type in
                            Button(action: { onSelect(type) }) {
                                HStack(spacing: 12) {
                                    Image(systemName: type.icon)
                                        .frame(width: 20)
                                        .foregroundStyle(type == .agent ? .purple : .secondary)
                                    Text(type.displayName)
                                    Spacer()
                                    Text(type.slashAliases.first ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(index == selectedIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .onChange(of: filteredTypes.count) { _, newCount in
            if selectedIndex >= newCount {
                selectedIndex = max(0, newCount - 1)
            }
        }
    }
}

// MARK: - Block Type Enum

enum BlockType: String, CaseIterable {
    case text
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case todo
    case code
    case quote
    case divider
    case callout
    case image
    case agent

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bulletList: return "Bullet List"
        case .numberedList: return "Numbered List"
        case .todo: return "To-do"
        case .code: return "Code"
        case .quote: return "Quote"
        case .divider: return "Divider"
        case .callout: return "Callout"
        case .image: return "Image"
        case .agent: return "Agent Block"
        }
    }

    var icon: String {
        switch self {
        case .text: return "text.alignleft"
        case .heading1: return "textformat.size.larger"
        case .heading2: return "textformat.size"
        case .heading3: return "textformat.size.smaller"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        case .todo: return "checkmark.square"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .quote: return "text.quote"
        case .divider: return "minus"
        case .callout: return "exclamationmark.circle"
        case .image: return "photo"
        case .agent: return "sparkles"
        }
    }

    /// Aliases for slash command filtering (e.g., "/h1" matches heading1)
    var slashAliases: [String] {
        switch self {
        case .text: return ["text", "paragraph", "p"]
        case .heading1: return ["h1", "heading1", "heading", "title"]
        case .heading2: return ["h2", "heading2", "subheading"]
        case .heading3: return ["h3", "heading3"]
        case .bulletList: return ["bullet", "list", "ul", "-"]
        case .numberedList: return ["numbered", "number", "ol", "1."]
        case .todo: return ["todo", "task", "checkbox", "[]"]
        case .code: return ["code", "```"]
        case .quote: return ["quote", "blockquote", ">"]
        case .divider: return ["divider", "hr", "---", "line"]
        case .callout: return ["callout", "note", "tip", "warning"]
        case .image: return ["image", "img", "photo"]
        case .agent: return ["agent", "ai", "sparkle"]
        }
    }

    /// Check if this block type matches a slash command query
    func matches(query: String) -> Bool {
        let lowercased = query.lowercased()
        if displayName.lowercased().contains(lowercased) { return true }
        return slashAliases.contains { $0.contains(lowercased) }
    }

    func createBlock() -> Block {
        switch self {
        case .text:
            return .text(TextBlock(content: ""))
        case .heading1:
            return .heading(HeadingBlock(content: "", level: .h1))
        case .heading2:
            return .heading(HeadingBlock(content: "", level: .h2))
        case .heading3:
            return .heading(HeadingBlock(content: "", level: .h3))
        case .bulletList:
            return .bulletList(BulletListBlock(items: [ListItem(content: "")]))
        case .numberedList:
            return .numberedList(NumberedListBlock(items: [ListItem(content: "")]))
        case .todo:
            return .todo(TodoBlock(items: [TodoItem(content: "")]))
        case .code:
            return .code(CodeBlock(content: ""))
        case .quote:
            return .quote(QuoteBlock(content: ""))
        case .divider:
            return .divider(DividerBlock())
        case .callout:
            return .callout(CalloutBlock(content: ""))
        case .image:
            return .image(ImageBlock())
        case .agent:
            return .agent(AgentBlock(prompt: ""))
        }
    }
}

// MARK: - Style Extensions

extension TextStyle {
    var font: Font {
        switch self {
        case .body: return .body
        case .caption: return .caption
        case .strong: return .body.bold()
        }
    }
}

extension HeadingLevel {
    var font: Font {
        switch self {
        case .h1: return .system(size: 28, weight: .bold)
        case .h2: return .system(size: 22, weight: .semibold)
        case .h3: return .system(size: 18, weight: .semibold)
        }
    }
}

extension CalloutStyle {
    var backgroundColor: Color {
        switch self {
        case .info: return Color.blue.opacity(0.1)
        case .warning: return Color.orange.opacity(0.1)
        case .success: return Color.green.opacity(0.1)
        case .error: return Color.red.opacity(0.1)
        }
    }
}

// MARK: - Import Types

enum ImportSource: Equatable {
    case file(String)
    case clipboard
    case url(URL)
}

struct ImportContent {
    let source: ImportSource
    let rawText: String
    var suggestedTitle: String?
}

// MARK: - Import Drop Hint

struct ImportDropHint: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("Drop files here to import")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Supports Markdown, plain text, and more")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                .foregroundStyle(.quaternary)
        )
    }
}

// MARK: - Import Preview Sheet

struct ImportPreviewSheet: View {
    let content: ImportContent
    let onImport: ([Block]) -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var parsedBlocks: [Block] = []
    @State private var isProcessing = false
    @State private var useAgent = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import Content")
                        .font(.headline)

                    Group {
                        switch content.source {
                        case .file(let name):
                            Label(name, systemImage: "doc")
                        case .clipboard:
                            Label("From clipboard", systemImage: "doc.on.clipboard")
                        case .url(let url):
                            Label(url.host ?? url.absoluteString, systemImage: "link")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(isOn: $useAgent) {
                    Label("Curator Agent", systemImage: "sparkles")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding()
            .background(Color(.controlBackgroundColor))

            Divider()

            // Preview
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isProcessing {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Processing with curator agent...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    } else if parsedBlocks.isEmpty {
                        Text("Preview will appear here")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    } else {
                        ForEach(parsedBlocks, id: \.id) { block in
                            ImportBlockPreview(block: block)
                        }
                    }
                }
                .padding()
            }
            .frame(minHeight: 300)

            Divider()

            // Actions
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)

                Spacer()

                Text("\(parsedBlocks.count) blocks")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Import") {
                    onImport(parsedBlocks)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(parsedBlocks.isEmpty || isProcessing)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .task {
            await processContent()
        }
        .onChange(of: useAgent) { _, _ in
            Task { await processContent() }
        }
    }

    private func processContent() async {
        isProcessing = true
        defer { isProcessing = false }

        if useAgent && appState.hasAgentClient {
            // Use curator agent to process content
            parsedBlocks = await processWithAgent()
        } else {
            // Simple parsing without agent
            parsedBlocks = parseSimple(content.rawText)
        }
    }

    private func processWithAgent() async -> [Block] {
        let prompt = """
        You are a content curator. Parse the following content into structured document blocks.
        Return ONLY a JSON array of blocks with this format:
        [{"type": "heading", "level": 1, "content": "..."}, {"type": "text", "content": "..."}, ...]

        Supported types: heading (with level 1-3), text, bullet (with items array), code (with language), quote

        Content to parse:
        ---
        \(content.rawText.prefix(4000))
        ---
        """

        if let response = await appState.sendAgentMessage(prompt),
           let blocks = parseAgentResponse(response) {
            return blocks
        }

        // Fall back to simple parsing
        return parseSimple(content.rawText)
    }

    private func parseAgentResponse(_ response: String) -> [Block]? {
        // Extract JSON from response
        guard let jsonStart = response.firstIndex(of: "["),
              let jsonEnd = response.lastIndex(of: "]")
        else { return nil }

        let jsonString = String(response[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8) else { return nil }

        do {
            let parsed = try JSONDecoder().decode([ParsedBlock].self, from: data)
            return parsed.compactMap { $0.toBlock() }
        } catch {
            return nil
        }
    }

    private func parseSimple(_ text: String) -> [Block] {
        // Simple line-by-line parsing
        var blocks: [Block] = []
        let lines = text.components(separatedBy: .newlines)
        var currentParagraph = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if !currentParagraph.isEmpty {
                    blocks.append(.text(TextBlock(content: currentParagraph)))
                    currentParagraph = ""
                }
            } else if trimmed.hasPrefix("# ") {
                if !currentParagraph.isEmpty {
                    blocks.append(.text(TextBlock(content: currentParagraph)))
                    currentParagraph = ""
                }
                blocks.append(.heading(HeadingBlock(content: String(trimmed.dropFirst(2)), level: .h1)))
            } else if trimmed.hasPrefix("## ") {
                if !currentParagraph.isEmpty {
                    blocks.append(.text(TextBlock(content: currentParagraph)))
                    currentParagraph = ""
                }
                blocks.append(.heading(HeadingBlock(content: String(trimmed.dropFirst(3)), level: .h2)))
            } else if trimmed.hasPrefix("### ") {
                if !currentParagraph.isEmpty {
                    blocks.append(.text(TextBlock(content: currentParagraph)))
                    currentParagraph = ""
                }
                blocks.append(.heading(HeadingBlock(content: String(trimmed.dropFirst(4)), level: .h3)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !currentParagraph.isEmpty {
                    blocks.append(.text(TextBlock(content: currentParagraph)))
                    currentParagraph = ""
                }
                blocks.append(.bulletList(BulletListBlock(items: [ListItem(content: String(trimmed.dropFirst(2)))])))
            } else {
                if currentParagraph.isEmpty {
                    currentParagraph = trimmed
                } else {
                    currentParagraph += " " + trimmed
                }
            }
        }

        if !currentParagraph.isEmpty {
            blocks.append(.text(TextBlock(content: currentParagraph)))
        }

        return blocks
    }
}

// MARK: - Import Block Preview

struct ImportBlockPreview: View {
    let block: Block

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: block.iconName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(block.previewText)
                .font(block.previewFont)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Parsed Block (for JSON decoding)

private struct ParsedBlock: Decodable {
    let type: String
    var level: Int?
    var content: String?
    var items: [String]?
    var language: String?

    func toBlock() -> Block? {
        switch type {
        case "heading":
            let headingLevel: HeadingLevel = {
                switch level {
                case 1: return .h1
                case 2: return .h2
                default: return .h3
                }
            }()
            return .heading(HeadingBlock(content: content ?? "", level: headingLevel))
        case "text":
            return .text(TextBlock(content: content ?? ""))
        case "bullet":
            let listItems = (items ?? []).map { ListItem(content: $0) }
            return .bulletList(BulletListBlock(items: listItems.isEmpty ? [ListItem(content: content ?? "")] : listItems))
        case "code":
            return .code(CodeBlock(content: content ?? "", language: language))
        case "quote":
            return .quote(QuoteBlock(content: content ?? ""))
        default:
            return nil
        }
    }
}

// MARK: - Block Preview Extensions

extension Block {
    var iconName: String {
        switch self {
        case .text: return "text.alignleft"
        case .heading: return "textformat.size"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        case .todo: return "checkmark.square"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .quote: return "text.quote"
        case .divider: return "minus"
        case .callout: return "exclamationmark.circle"
        case .image: return "photo"
        case .agent: return "sparkles"
        }
    }

    var previewText: String {
        switch self {
        case .text(let b): return b.content
        case .heading(let b): return b.content
        case .bulletList(let b): return b.items.map { "• " + $0.content }.joined(separator: "\n")
        case .numberedList(let b): return b.items.enumerated().map { "\($0.offset + 1). " + $0.element.content }.joined(separator: "\n")
        case .todo(let b): return b.items.map { ($0.isCompleted ? "☑" : "☐") + " " + $0.content }.joined(separator: "\n")
        case .code(let b): return b.content
        case .quote(let b): return b.content
        case .divider: return "───"
        case .callout(let b): return b.content
        case .image: return "[Image]"
        case .agent(let b): return b.prompt.isEmpty ? "[Agent Block]" : b.prompt
        }
    }

    var previewFont: Font {
        switch self {
        case .heading(let b):
            switch b.level {
            case .h1: return .headline
            case .h2: return .subheadline
            case .h3: return .subheadline
            }
        case .code:
            return .system(.caption, design: .monospaced)
        default:
            return .caption
        }
    }
}
