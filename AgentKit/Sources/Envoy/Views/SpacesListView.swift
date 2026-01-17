import AgentKit
import AppKit
import SwiftUI

// MARK: - Spaces List View

/// View showing all your Spaces (like GitHub repos list)
struct SpacesListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    var filteredSpaces: [SpaceViewModel] {
        // Only use actual spaces - no sample data
        if searchText.isEmpty {
            return appState.spaces
        }
        return appState.spaces.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search spaces...", text: $searchText)
                    .textFieldStyle(.plain)

                Button(action: { appState.showNewSpaceSheet = true }) {
                    Label("New Space", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Spaces grid or empty state
            if filteredSpaces.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    Text(searchText.isEmpty ? "No Spaces Yet" : "No Results")
                        .font(.title3.weight(.medium))

                    Text(searchText.isEmpty
                        ? "Create your first space to organize your work, documents, and conversations."
                        : "No spaces match \"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)

                    if searchText.isEmpty {
                        Button(action: { appState.showNewSpaceSheet = true }) {
                            Label("Create Space", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
                    ], spacing: 16) {
                        ForEach(filteredSpaces) { space in
                            SpaceCard(space: space)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Spaces")
        .sheet(isPresented: $appState.showNewSpaceSheet) {
            NewSpaceSheet()
        }
        .task {
            await appState.loadSpaces()
        }
    }
}

// MARK: - Space Card

struct SpaceCard: View {
    let space: SpaceViewModel
    @EnvironmentObject private var appState: AppState
    @State private var isHovered = false
    @State private var isStarred: Bool = false

    init(space: SpaceViewModel) {
        self.space = space
        self._isStarred = State(initialValue: space.isStarred)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Icon with subtle animation
                RoundedRectangle(cornerRadius: 8)
                    .fill(space.color.gradient)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: space.icon)
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .shadow(color: space.color.opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 6 : 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(space.name)
                        .font(.headline)

                    Text(space.ownerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Star button with animation
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        isStarred.toggle()
                    }
                }) {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .foregroundStyle(isStarred ? .yellow : .secondary)
                        .scaleEffect(isStarred ? 1.1 : 1.0)
                }
                .buttonStyle(.plain)
            }

            // Description
            if let description = space.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            // Stats with hover highlight
            HStack(spacing: 16) {
                Label("\(space.documentCount)", systemImage: "doc.text")
                Label("\(space.contributorCount)", systemImage: "person.2")

                Spacer()

                Text(space.updatedAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: isHovered
                            ? [space.color.opacity(0.5), space.color.opacity(0.2)]
                            : [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(isHovered ? 0.18 : 0.08), radius: isHovered ? 16 : 6, y: isHovered ? 6 : 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            // Navigate to space detail
            appState.selectedSpaceId = SpaceID(space.id)
        }
        .contextMenu {
            Button(action: {
                appState.selectedSpaceId = SpaceID(space.id)
            }) {
                Label("Open Space", systemImage: "arrow.right.circle")
            }

            if let path = space.path {
                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path.path)
                }) {
                    Label("Show in Finder", systemImage: "folder")
                }
            }

            Divider()

            Button(action: {
                withAnimation {
                    isStarred.toggle()
                }
            }) {
                Label(isStarred ? "Unstar" : "Star", systemImage: isStarred ? "star.slash" : "star")
            }

            Divider()

            if let path = space.path {
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "vscode://file/\(path.path)")!)
                }) {
                    Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button(action: {
                    NSWorkspace.shared.openApplication(
                        at: URL(fileURLWithPath: "/Applications/Xcode.app"),
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }) {
                    Label("Open in Xcode", systemImage: "hammer")
                }
            }

            Divider()

            Button(role: .destructive, action: {
                // Archive space
            }) {
                Label("Archive Space", systemImage: "archivebox")
            }
        }
    }
}

// MARK: - New Space Sheet

struct NewSpaceSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var selectedColor: Color = .blue
    @State private var selectedIcon = "folder"
    @State private var isCreating = false

    let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .cyan]
    let icons = ["folder", "briefcase", "book", "gearshape", "house", "star", "heart", "flag"]

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Space")
                .font(.title2.weight(.semibold))

            // Preview
            HStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedColor.gradient)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: selectedIcon)
                            .font(.title2)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading) {
                    Text(name.isEmpty ? "New Space" : name)
                        .font(.headline)
                    Text("0 documents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.subheadline.weight(.medium))
                TextField("Space name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.subheadline.weight(.medium))
                TextField("Optional description", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    ForEach(colors, id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if selectedColor == color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture {
                                selectedColor = color
                            }
                    }
                }
            }

            // Icon picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    ForEach(icons, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture {
                                selectedIcon = icon
                            }
                    }
                }
            }

            Spacer()

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Create Space") {
                    createSpace()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || isCreating)
            }
        }
        .padding(24)
        .frame(width: 400, height: 480)
    }

    private func createSpace() {
        isCreating = true
        Task {
            do {
                try await appState.createSpace(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    icon: selectedIcon,
                    color: colorToSpaceColor(selectedColor)
                )
                dismiss()
            } catch {
                print("Failed to create space: \(error)")
                isCreating = false
            }
        }
    }

    private func colorToSpaceColor(_ color: Color) -> SpaceColor {
        switch color {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .cyan: return .cyan
        case .red: return .red
        case .yellow: return .yellow
        default: return .blue
        }
    }
}
