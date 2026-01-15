import AgentKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Link Space View

/// View for linking an external folder as a space
struct LinkSpaceView: View {
    let onLink: (LinkedSpace) -> Void
    let onCancel: () -> Void

    @State private var selectedPath: URL?
    @State private var spaceName: String = ""
    @State private var spaceType: SpaceType = .code
    @State private var defaultRunner: TaskRunner = .claudeCode
    @State private var useAutoRunner = true
    @State private var description: String = ""
    @State private var isDetectingGit = false
    @State private var detectedGitInfo: GitInfo?
    @State private var isLinking = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Folder selection
                    folderSelection

                    if selectedPath != nil {
                        // Space name
                        nameSection

                        // Space type
                        typeSection

                        // Default runner
                        runnerSection

                        // Git info (if detected)
                        if let gitInfo = detectedGitInfo {
                            gitInfoSection(gitInfo)
                        }

                        // Optional description
                        descriptionSection
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            actionBar
        }
        .frame(width: 500, height: 560)
        .onChange(of: spaceType) { _, newType in
            if useAutoRunner {
                defaultRunner = newType.defaultRunner
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Link Folder")
                    .font(.headline)

                Text("Add an existing folder as a workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Folder Selection

    private var folderSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Folder")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                if let path = selectedPath {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(path.lastPathComponent)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(path.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        if isDetectingGit {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("No folder selected")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button("Browse...") {
                    selectFolder()
                }
                .buttonStyle(.bordered)
            }

            if let error = error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("Space name", text: $spaceName)
                .textFieldStyle(.roundedBorder)

            Text("A friendly name for this workspace")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Type Section

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Type")
                .font(.subheadline)
                .fontWeight(.medium)

            VStack(spacing: 8) {
                ForEach(SpaceType.allCases, id: \.self) { type in
                    SpaceTypeRow(
                        type: type,
                        isSelected: spaceType == type,
                        onSelect: { spaceType = type }
                    )
                }
            }
        }
    }

    // MARK: - Runner Section

    private var runnerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Default Agent")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Toggle("Auto from type", isOn: $useAutoRunner)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if !useAutoRunner {
                Picker("Runner", selection: $defaultRunner) {
                    ForEach(TaskRunner.allCases, id: \.self) { runner in
                        Label(runner.displayName, systemImage: runner.icon)
                            .tag(runner)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: spaceType.defaultRunner.icon)
                        .foregroundStyle(.secondary)

                    Text(spaceType.defaultRunner.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("(from space type)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Git Info Section

    private func gitInfoSection(_ info: GitInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Git Repository", systemImage: "arrow.triangle.branch")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                if let remote = info.remote {
                    HStack {
                        Text("Remote:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(remote)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }

                if let branch = info.branch {
                    HStack {
                        Text("Branch:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(branch)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description (optional)")
                .font(.subheadline)
                .fontWeight(.medium)

            TextField("What is this workspace for?", text: $description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            Spacer()

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)

            Button(action: linkSpace) {
                if isLinking {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 60)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Link")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canLink || isLinking)
        }
        .padding()
    }

    // MARK: - Computed Properties

    private var canLink: Bool {
        selectedPath != nil && !spaceName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to link as a workspace"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url
            spaceName = url.lastPathComponent
            error = nil

            // Detect git info
            Task {
                await detectGitInfo(at: url)
            }
        }
    }

    private func detectGitInfo(at path: URL) async {
        isDetectingGit = true
        defer { isDetectingGit = false }

        let gitDir = path.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            detectedGitInfo = nil
            return
        }

        // Run git commands to get info
        let remote = try? await runGit(["config", "--get", "remote.origin.url"], at: path)
        let branch = try? await runGit(["symbolic-ref", "--short", "HEAD"], at: path)

        detectedGitInfo = GitInfo(
            remote: remote?.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: branch?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        // Auto-detect space type based on git repo contents
        if detectedGitInfo != nil {
            // If it's a git repo, likely code
            spaceType = .code
        }
    }

    private func runGit(_ args: [String], at directory: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func linkSpace() {
        guard let path = selectedPath else { return }

        isLinking = true

        Task {
            do {
                let space = try await SpaceRegistry.shared.linkSpace(
                    name: spaceName.trimmingCharacters(in: .whitespaces),
                    path: path,
                    type: spaceType,
                    defaultRunner: useAutoRunner ? nil : defaultRunner
                )

                await MainActor.run {
                    isLinking = false
                    onLink(space)
                }
            } catch {
                await MainActor.run {
                    isLinking = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Space Type Row

struct SpaceTypeRow: View {
    let type: SpaceType
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .medium : .regular)

                    Text(typeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var typeDescription: String {
        switch type {
        case .code:
            return "Software projects, repositories"
        case .content:
            return "Documents, writing, research"
        case .mixed:
            return "Both code and content"
        }
    }
}

// MARK: - Git Info

struct GitInfo {
    let remote: String?
    let branch: String?
}

// MARK: - Spaces Management View

/// Main view for managing linked spaces
struct SpacesManagementView: View {
    @State private var spaces: [LinkedSpace] = []
    @State private var isLoading = true
    @State private var showingLinkSheet = false
    @State private var selectedSpace: LinkedSpace?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Content
            if isLoading {
                ProgressView("Loading spaces...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if spaces.isEmpty {
                emptyState
            } else {
                spacesList
            }
        }
        .task {
            await loadSpaces()
        }
        .sheet(isPresented: $showingLinkSheet) {
            LinkSpaceView(
                onLink: { space in
                    spaces.append(space)
                    spaces.sort { $0.name < $1.name }
                    showingLinkSheet = false
                },
                onCancel: {
                    showingLinkSheet = false
                }
            )
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("Linked Spaces")
                .font(.headline)

            Spacer()

            Button {
                showingLinkSheet = true
            } label: {
                Label("Link Folder", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Linked Spaces")
                .font(.title2)
                .fontWeight(.medium)

            Text("Link folders to work with them as dedicated workspaces")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingLinkSheet = true
            } label: {
                Label("Link Your First Folder", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Spaces List

    private var spacesList: some View {
        List(spaces) { space in
            SpaceRowView(space: space)
                .contextMenu {
                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: space.path.path)
                    }

                    Divider()

                    Button("Unlink", role: .destructive) {
                        Task {
                            try? await SpaceRegistry.shared.unlinkSpace(space.id)
                            await loadSpaces()
                        }
                    }
                }
        }
        .listStyle(.inset)
    }

    // MARK: - Actions

    private func loadSpaces() async {
        isLoading = true
        try? await SpaceRegistry.shared.load()
        spaces = await SpaceRegistry.shared.listSpaces()
        isLoading = false
    }
}

// MARK: - Space Row View

struct SpaceRowView: View {
    let space: LinkedSpace

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: space.type.icon)
                .font(.title2)
                .foregroundStyle(typeColor)
                .frame(width: 40, height: 40)
                .background(typeColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Label(space.type.displayName, systemImage: space.type.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let branch = space.defaultBranch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(space.path.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Default runner badge
            HStack(spacing: 4) {
                Image(systemName: space.defaultRunner.icon)
                Text(space.defaultRunner.displayName)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    private var typeColor: Color {
        switch space.type {
        case .code: return .blue
        case .content: return .green
        case .mixed: return .purple
        }
    }
}
