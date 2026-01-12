import AgentKit
import SwiftUI

// MARK: - Documents View

struct DocumentsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid

    enum ViewMode: String, CaseIterable {
        case grid, list
    }

    var filteredDocuments: [Document] {
        if searchText.isEmpty {
            return appState.workspace.documents
        }
        return appState.workspace.documents.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedDocument: Binding<Document>? {
        guard let id = appState.selectedDocumentId,
              let index = appState.workspace.documents.firstIndex(where: { $0.id == id })
        else { return nil }

        return Binding(
            get: { appState.workspace.documents[index] },
            set: { appState.workspace.documents[index] = $0 }
        )
    }

    var body: some View {
        HSplitView {
            // Document list sidebar
            Group {
                if appState.workspace.documents.isEmpty {
                    EmptyDocumentsView()
                } else {
                    documentsList
                }
            }
            .frame(minWidth: 250, idealWidth: 300)

            // Document editor
            if let document = selectedDocument {
                DocumentEditorView(document: document)
                    .frame(minWidth: 400)
            } else {
                DocumentPlaceholder()
                    .frame(minWidth: 400)
            }
        }
        .navigationTitle("Documents")
        .searchable(text: $searchText, prompt: "Search documents...")
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                }
                .pickerStyle(.segmented)

                Button(action: { appState.showNewDocumentSheet = true }) {
                    Label("New Document", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var documentsList: some View {
        if viewMode == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300))], spacing: 16) {
                    ForEach(filteredDocuments) { document in
                        DocumentCard(document: document)
                            .onTapGesture {
                                appState.selectedDocumentId = document.id
                            }
                    }
                }
                .padding()
            }
        } else {
            List(filteredDocuments) { document in
                DocumentRow(document: document)
                    .onTapGesture {
                        appState.selectedDocumentId = document.id
                    }
            }
        }
    }
}

// MARK: - Document Card

struct DocumentCard: View {
    let document: Document
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Preview area
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 120)
                .overlay {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(document.blocks.prefix(3), id: \.id) { block in
                            blockPreview(block)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

            // Title and metadata
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(document.title.isEmpty ? "Untitled" : document.title)
                        .font(.headline)
                        .lineLimit(1)

                    if document.isStarred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }

                Text(document.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contextMenu {
            Button(action: { toggleStar() }) {
                Label(document.isStarred ? "Remove Star" : "Add Star", systemImage: document.isStarred ? "star.slash" : "star")
            }
            Divider()
            Button(role: .destructive, action: { deleteDocument() }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func blockPreview(_ block: Block) -> some View {
        switch block {
        case .text(let textBlock):
            Text(textBlock.content)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.secondary)
        case .heading(let headingBlock):
            Text(headingBlock.content)
                .font(headingBlock.level == .h1 ? .caption.bold() : .caption)
                .lineLimit(1)
        case .bulletList(let listBlock):
            if let first = listBlock.items.first {
                HStack(spacing: 4) {
                    Text("•")
                    Text(first.content)
                }
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    private func toggleStar() {
        Task {
            await appState.toggleDocumentStar(document.id)
        }
    }

    private func deleteDocument() {
        Task {
            await appState.deleteDocument(document.id)
        }
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: Document

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(document.title.isEmpty ? "Untitled" : document.title)
                        .font(.headline)

                    if document.isStarred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }

                Text(document.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty State

struct EmptyDocumentsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Documents Yet")
                .font(.title2)
                .fontWeight(.medium)

            Text("Create your first document to start building your knowledge base.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button(action: { appState.showNewDocumentSheet = true }) {
                Label("New Document", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - New Document Sheet

struct NewDocumentSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("New Document")
                .font(.headline)

            TextField("Document Title", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Create") {
                    createDocument()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func createDocument() {
        Task {
            let document = await appState.createDocument(title: title)
            appState.selectedDocumentId = document.id
            dismiss()
        }
    }
}

// MARK: - Document Placeholder

struct DocumentPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Select a document")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Choose a document from the list to start editing")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.textBackgroundColor))
    }
}
