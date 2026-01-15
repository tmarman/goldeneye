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
    @State private var saveStatus: SaveStatus = .saved

    enum SaveStatus {
        case saved, saving, unsaved
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mainContent
                .background(Color(.textBackgroundColor))
                .overlay { dropTargetOverlay.animation(.liquidGlassQuick, value: isDropTargeted) }
                .overlay { blockMenuOverlay }
                .onDrop(of: [.fileURL, .plainText, .utf8PlainText], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers: providers)
                    return true
                }
                .sheet(isPresented: $showImportSheet) { importSheet }
                .onChange(of: document.updatedAt) { _, _ in debouncedSave() }

            // Save indicator
            saveIndicator
                .padding(12)
        }
    }

    @ViewBuilder
    private var saveIndicator: some View {
        HStack(spacing: 6) {
            switch saveStatus {
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green.opacity(0.7))
                Text("Saved")
            case .saving:
                ProgressView()
                    .scaleEffect(0.6)
                Text("Saving...")
            case .unsaved:
                Image(systemName: "circle.fill")
                    .foregroundStyle(.orange.opacity(0.7))
                Text("Unsaved")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(saveStatus == .saved ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: saveStatus)
    }

    // MARK: - View Components

    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DocumentTitleField(title: $document.title)
                    .padding(.bottom, 16)

                blocksContent

                AddBlockButton(
                    onAdd: { insertBlock(type: .text, at: document.blocks.count) },
                    onShowMenu: { showBlockMenuAt(index: document.blocks.count) }
                )
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
                onDelete: { withAnimation(.liquidGlass) { deleteBlock(at: index) } },
                onMoveUp: index > 0 ? { withAnimation(.liquidGlass) { moveBlock(from: index, to: index - 1) } } : nil,
                onMoveDown: index < document.blocks.count - 1 ? { withAnimation(.liquidGlass) { moveBlock(from: index, to: index + 1) } } : nil,
                onDuplicate: { withAnimation(.liquidGlass) { duplicateBlock(at: index) } },
                onTurnInto: { type in withAnimation(.liquidGlass) { turnBlockInto(at: index, type: type) } },
                onNewBlockAfter: { insertBlock(type: .text, at: index + 1) },
                onReorder: { fromIndex in
                    withAnimation(.liquidGlass) {
                        moveBlock(from: fromIndex, to: fromIndex < index ? index : index)
                    }
                },
                index: index
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .offset(y: -8)),
                removal: .opacity.combined(with: .scale(scale: 0.95))
            ))
        }
    }

    @ViewBuilder
    private var dropTargetOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [10, 5]))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accentColor.opacity(0.08))
                )
                .overlay {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 72, height: 72)

                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 32))
                        }
                        Text("Drop to import")
                            .font(.headline)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .padding(12)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
        saveStatus = .unsaved
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(for: .seconds(1))
                await MainActor.run { saveStatus = .saving }
                try await appState.saveDocument(document)
                await MainActor.run {
                    saveStatus = .saved
                    // Hide saved indicator after a moment
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if saveStatus == .saved {
                            // Already saved, stays hidden via opacity
                        }
                    }
                }
            } catch is CancellationError {
                // Cancelled - ignore
            } catch {
                await MainActor.run { saveStatus = .unsaved }
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
        withAnimation(.liquidGlass) {
            document.blocks.insert(newBlock, at: index)
        }
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

    private func duplicateBlock(at index: Int) {
        let original = document.blocks[index]
        let duplicate = original.duplicate()
        document.blocks.insert(duplicate, at: index + 1)
        focusedBlockId = duplicate.id
        document.updatedAt = Date()
    }

    private func turnBlockInto(at index: Int, type: BlockType) {
        let currentBlock = document.blocks[index]
        let content = currentBlock.extractContent()

        // Create new block with the content from the old one
        var newBlock = type.createBlock()
        newBlock.setContent(content)

        document.blocks[index] = newBlock
        focusedBlockId = newBlock.id
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
    let onDuplicate: () -> Void
    let onTurnInto: (BlockType) -> Void
    var onNewBlockAfter: (() -> Void)? = nil
    var onReorder: ((Int) -> Void)? = nil
    let index: Int

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var isDropTarget = false

    var body: some View {
        HStack(alignment: .top, spacing: EditorTokens.Spacing.blockHorizontal) {
            // Block handle (visible on hover)
            BlockHandle(
                isVisible: isHovered || isFocused,
                onAdd: onAddBlock,
                onDelete: onDelete,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                onDuplicate: onDuplicate,
                onTurnInto: onTurnInto
            )

            // Block content
            BlockContentView(
                block: $block,
                documentId: documentId,
                isFocused: isFocused,
                onNewBlockAfter: onNewBlockAfter,
                onDeleteIfEmpty: { if case .text(let t) = block, t.content.isEmpty { onDelete() } }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .editorBlock(isHovered: isHovered, isFocused: isFocused)
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .offset(y: -4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
        .onHover { isHovered = $0 }
        .opacity(isDragging ? 0.5 : 1)
        .draggable(BlockDragData(blockId: block.id.rawValue, index: index)) {
            // Drag preview
            HStack(spacing: 8) {
                Image(systemName: block.iconName)
                    .foregroundStyle(.secondary)
                Text(block.previewText.prefix(40) + (block.previewText.count > 40 ? "..." : ""))
                    .lineLimit(1)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: BlockDragData.self) { items, _ in
            guard let dragData = items.first,
                  dragData.index != index else { return false }
            onReorder?(dragData.index)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
    }
}

/// Drag data for block reordering
struct BlockDragData: Codable, Transferable {
    let blockId: String
    let index: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - Block Handle

struct BlockHandle: View {
    let isVisible: Bool
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    let onDuplicate: () -> Void
    let onTurnInto: (BlockType) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            // Add button - appears on hover
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(isHovered ? Color.accentColor.opacity(0.1) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.6)

            // Drag handle with context menu
            Menu {
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])

                Divider()

                if let onMoveUp {
                    Button(action: onMoveUp) {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .keyboardShortcut(.upArrow, modifiers: [.option])
                }
                if let onMoveDown {
                    Button(action: onMoveDown) {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    .keyboardShortcut(.downArrow, modifiers: [.option])
                }

                Divider()

                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .keyboardShortcut("d", modifiers: [.command])

                // Turn into submenu
                Menu {
                    ForEach(BlockType.allCases, id: \.self) { type in
                        Button(action: { onTurnInto(type) }) {
                            Label(type.displayName, systemImage: type.icon)
                        }
                    }
                } label: {
                    Label("Turn into...", systemImage: "arrow.triangle.swap")
                }
            } label: {
                // Craft-style grip dots
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 2) {
                            Circle()
                                .fill(isHovered ? Color.primary.opacity(0.5) : Color.secondary.opacity(0.35))
                                .frame(width: 3, height: 3)
                            Circle()
                                .fill(isHovered ? Color.primary.opacity(0.5) : Color.secondary.opacity(0.35))
                                .frame(width: 3, height: 3)
                        }
                    }
                }
                .frame(width: 16, height: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: EditorTokens.Spacing.handleWidth)
        .opacity(isVisible ? 1 : 0)
        .animation(.liquidGlassQuick, value: isVisible)
        .animation(.liquidGlassQuick, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

/// A small handle button with hover feedback
private struct HandleButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.liquidGlassQuick, value: isHovered)
    }
}

// MARK: - Block Content View

struct BlockContentView: View {
    @Binding var block: Block
    let documentId: DocumentID
    let isFocused: Bool
    var onNewBlockAfter: (() -> Void)? = nil
    var onDeleteIfEmpty: (() -> Void)? = nil

    var body: some View {
        switch block {
        case .text(let textBlock):
            TextBlockView(
                block: binding(for: textBlock),
                isFocused: isFocused,
                onConvertBlock: { type in
                    block = type.createBlock()
                },
                onNewBlockAfter: onNewBlockAfter,
                onDeleteIfEmpty: onDeleteIfEmpty
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
    var onNewBlockAfter: (() -> Void)? = nil
    var onDeleteIfEmpty: (() -> Void)? = nil

    @State private var showSlashMenu = false
    @State private var previousContent = ""

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
                .onChange(of: block.content) { oldValue, newValue in
                    showSlashMenu = newValue.hasPrefix("/")

                    // Detect backspace on empty block
                    if newValue.isEmpty && oldValue.isEmpty {
                        onDeleteIfEmpty?()
                    }
                    previousContent = newValue
                }
                .onSubmit {
                    // Enter key creates new block after
                    if !showSlashMenu {
                        onNewBlockAfter?()
                    }
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
                .contextMenu {
                    Button("Replace Image...", action: pickImage)
                    Button("Remove Image", role: .destructive) {
                        block.url = nil
                    }
                }
            } else {
                // Placeholder for adding image
                Button(action: pickImage) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                Text("Click to add image")
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

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            block.url = url
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
    let onAdd: () -> Void      // Click to add text block immediately
    let onShowMenu: () -> Void // Right-click for other block types
    @State private var isHovered = false
    @State private var showQuickMenu = false

    // Convenience init for simple case
    init(action: @escaping () -> Void) {
        self.onAdd = action
        self.onShowMenu = action
    }

    init(onAdd: @escaping () -> Void, onShowMenu: @escaping () -> Void) {
        self.onAdd = onAdd
        self.onShowMenu = onShowMenu
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left line
            Rectangle()
                .fill(Color.primary.opacity(isHovered ? 0.12 : 0.06))
                .frame(height: 1)

            // Center button group
            HStack(spacing: 4) {
                // Main add button
                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add block")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)

                // Quick block type menu
                Menu {
                    ForEach(BlockType.allCases.prefix(6), id: \.self) { type in
                        Button(action: { onShowMenu() }) {
                            Label(type.displayName, systemImage: type.icon)
                        }
                    }
                    Divider()
                    Button(action: onShowMenu) {
                        Label("More blocks...", systemImage: "ellipsis.circle")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isHovered ? .secondary : .tertiary)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0.5)
            }

            // Right line
            Rectangle()
                .fill(Color.primary.opacity(isHovered ? 0.12 : 0.06))
                .frame(height: 1)
        }
        .frame(height: 32)
        .animation(.liquidGlassQuick, value: isHovered)
        .onHover { isHovered = $0 }
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
            GlassMenu {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                        Text("Add Block")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider()
                        .opacity(0.5)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(BlockType.allCases, id: \.self) { type in
                                GlassMenuItem(
                                    title: type.displayName,
                                    icon: type.icon,
                                    iconColor: type == .agent ? EditorTokens.Colors.agentAccent : .secondary
                                ) {
                                    onSelect(type)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 320)
                }
                .frame(width: 220)
            }
        }
    }
}

// MARK: - Slash Command Menu

struct SlashCommandMenu: View {
    let query: String
    let onSelect: (BlockType) -> Void
    let onDismiss: () -> Void
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    var filteredTypes: [BlockType] {
        if query.isEmpty {
            return BlockType.allCases.filter { $0 != .text }
        }
        return BlockType.allCases.filter { $0.matches(query: query) }
    }

    var body: some View {
        GlassMenu {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text("Turn into")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        KeyboardHint(key: "↑↓")
                        KeyboardHint(key: "↵")
                        KeyboardHint(key: "esc")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()
                    .opacity(0.5)

                if filteredTypes.isEmpty {
                    emptyState
                } else {
                    menuItems
                }
            }
            .frame(width: 300)
        }
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            selectCurrentItem()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onChange(of: filteredTypes.count) { _, newCount in
            if selectedIndex >= newCount {
                selectedIndex = max(0, newCount - 1)
            }
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    private func moveSelection(by offset: Int) {
        let count = filteredTypes.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + offset + count) % count
    }

    private func selectCurrentItem() {
        guard selectedIndex < filteredTypes.count else { return }
        onSelect(filteredTypes[selectedIndex])
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.quaternary)
            Text("No matching blocks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var menuItems: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(filteredTypes.enumerated()), id: \.element) { index, type in
                        SlashMenuItem(
                            type: type,
                            isSelected: index == selectedIndex,
                            action: { onSelect(type) }
                        )
                        .id(index)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

/// Individual item in slash command menu with selection state
private struct SlashMenuItem: View {
    let type: BlockType
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon with colored background
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconBackgroundColor.opacity(0.15))
                        .frame(width: 28, height: 28)

                    Image(systemName: type.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(iconBackgroundColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(type.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Text("/" + (type.slashAliases.first ?? ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "return")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.05) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var iconBackgroundColor: Color {
        switch type {
        case .heading1, .heading2, .heading3, .text:
            return .blue
        case .bulletList, .numberedList, .todo:
            return .green
        case .code:
            return .orange
        case .quote:
            return .purple
        case .callout:
            return .yellow
        case .divider:
            return .secondary
        case .image:
            return .pink
        case .agent:
            return EditorTokens.Colors.agentAccent
        }
    }
}

/// A small keyboard hint badge
private struct KeyboardHint: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.06))
            )
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
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
            }

            VStack(spacing: 6) {
                Text("Drop files to import")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Markdown, plain text, and more")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                ForEach(["doc.text", "doc.plaintext", "link"], id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isHovered ? Color.accentColor.opacity(0.03) : Color(.controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                .foregroundStyle(isHovered ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08))
        )
        .animation(.liquidGlassQuick, value: isHovered)
        .onHover { isHovered = $0 }
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
            headerView
                .padding()
                .background(.ultraThinMaterial)

            Divider()
                .opacity(0.5)

            // Preview
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if isProcessing {
                        processingView
                    } else if parsedBlocks.isEmpty {
                        emptyPreviewView
                    } else {
                        ForEach(parsedBlocks, id: \.id) { block in
                            ImportBlockPreview(block: block)
                        }
                    }
                }
                .padding()
            }
            .frame(minHeight: 300)
            .background(Color(.textBackgroundColor))

            Divider()
                .opacity(0.5)

            // Actions
            footerView
                .padding()
                .background(.ultraThinMaterial)
        }
        .frame(width: 600, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await processContent()
        }
        .onChange(of: useAgent) { _, _ in
            Task { await processContent() }
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Content")
                    .font(.headline)

                sourceLabel
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Curator agent toggle with pill style
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(useAgent ? EditorTokens.Colors.agentAccent : .secondary)
                Text("Curator")
                    .font(.caption.weight(.medium))
                Toggle("", isOn: $useAgent)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(useAgent ? EditorTokens.Colors.agentAccent.opacity(0.1) : Color.primary.opacity(0.05))
            )
        }
    }

    @ViewBuilder
    private var sourceLabel: some View {
        switch content.source {
        case .file(let name):
            Label(name, systemImage: "doc.fill")
        case .clipboard:
            Label("From clipboard", systemImage: "doc.on.clipboard.fill")
        case .url(let url):
            Label(url.host ?? url.absoluteString, systemImage: "link")
        }
    }

    @ViewBuilder
    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            VStack(spacing: 4) {
                Text("Processing with Curator")
                    .font(.subheadline.weight(.medium))
                Text("Analyzing content structure...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private var emptyPreviewView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("Preview will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .frame(minWidth: 80)
            }
            .buttonStyle(GlassButtonStyle())
            .keyboardShortcut(.escape)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption2)
                Text("\(parsedBlocks.count) blocks")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.05)))

            Button(action: { onImport(parsedBlocks) }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import")
                }
                .frame(minWidth: 80)
            }
            .buttonStyle(GlassButtonStyle(isProminent: true))
            .keyboardShortcut(.return)
            .disabled(parsedBlocks.isEmpty || isProcessing)
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
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: block.iconName)
                .font(.caption)
                .foregroundStyle(iconColor)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(iconColor.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(block.previewText)
                    .font(block.previewFont)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text(block.typeName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.03) : Color(.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .animation(.liquidGlassQuick, value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var iconColor: Color {
        switch block {
        case .agent: return EditorTokens.Colors.agentAccent
        case .code: return .orange
        case .heading: return .blue
        default: return .secondary
        }
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

    var typeName: String {
        switch self {
        case .text: return "Text"
        case .heading(let h): return "Heading \(h.level == .h1 ? "1" : h.level == .h2 ? "2" : "3")"
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
