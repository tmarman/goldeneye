import AgentKit
import SwiftUI

struct SessionsView: View {
    @State private var sessions: [SessionListItem] = []
    @State private var selectedSession: SessionListItem?
    @State private var isLoading = true

    var body: some View {
        HSplitView {
            // Session list
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sessions.isEmpty {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "No Sessions",
                        message: "Sessions will appear here when agents run tasks"
                    )
                } else {
                    List(selection: $selectedSession) {
                        ForEach(sessions) { session in
                            SessionListRow(session: session)
                                .tag(session)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 250)

            // Session detail
            if let session = selectedSession {
                SessionDetailView(session: session)
            } else {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No Session Selected",
                    message: "Select a session to view its history"
                )
            }
        }
        .navigationTitle("Sessions")
        .task {
            await loadSessions()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadSessions() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func loadSessions() async {
        isLoading = true
        // Simulate loading
        try? await Task.sleep(for: .milliseconds(300))

        // Mock data for development
        sessions = [
            SessionListItem(
                id: "session-1",
                name: "research-task",
                createdAt: Date().addingTimeInterval(-3600),
                taskCount: 5,
                isActive: true
            ),
            SessionListItem(
                id: "session-2",
                name: nil,
                createdAt: Date().addingTimeInterval(-86400),
                taskCount: 12,
                isActive: false
            ),
        ]

        isLoading = false
    }
}

// MARK: - Supporting Types

struct SessionListItem: Identifiable, Hashable {
    let id: String
    let name: String?
    let createdAt: Date
    let taskCount: Int
    let isActive: Bool
}

// MARK: - Session List Row

struct SessionListRow: View {
    let session: SessionListItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.name ?? session.id)
                        .fontWeight(.medium)

                    if session.isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                    }
                }

                Text("\(session.taskCount) tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(session.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    let session: SessionListItem
    @State private var commits: [GitCommitInfo] = []
    @State private var isLoadingCommits = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(session.name ?? "Session")
                            .font(.title2)
                            .fontWeight(.semibold)

                        if session.isActive {
                            Text("Active")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.2))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }

                        Spacer()
                    }

                    Text(session.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Divider()

                // Git integration
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Git History", systemImage: "arrow.triangle.branch")
                            .font(.headline)

                        Spacer()

                        Button {
                            // Clone repo
                        } label: {
                            Label("Clone", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }

                    if isLoadingCommits {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if commits.isEmpty {
                        Text("No commits yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(commits) { commit in
                                CommitRow(commit: commit)
                                if commit.id != commits.last?.id {
                                    Divider()
                                        .padding(.leading, 40)
                                }
                            }
                        }
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Session stats
                VStack(alignment: .leading, spacing: 12) {
                    Text("Statistics")
                        .font(.headline)

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        StatBox(label: "Tasks", value: "\(session.taskCount)")
                        StatBox(label: "Created", value: session.createdAt.formatted(date: .abbreviated, time: .shortened))
                        StatBox(label: "Commits", value: "\(commits.count)")
                        StatBox(label: "Duration", value: formatDuration())
                    }
                }

                Spacer()
            }
            .padding()
        }
        .task {
            await loadCommits()
        }
    }

    private func loadCommits() async {
        isLoadingCommits = true
        try? await Task.sleep(for: .milliseconds(200))

        // Mock data
        commits = [
            GitCommitInfo(
                id: "abc123",
                message: "Read file: Package.swift",
                author: "AgentKit",
                date: Date().addingTimeInterval(-1800)
            ),
            GitCommitInfo(
                id: "def456",
                message: "Write file: Sources/main.swift",
                author: "AgentKit",
                date: Date().addingTimeInterval(-3600)
            ),
        ]

        isLoadingCommits = false
    }

    private func formatDuration() -> String {
        if session.isActive {
            let interval = Date().timeIntervalSince(session.createdAt)
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
        return "—"
    }
}

// MARK: - Supporting Views

struct GitCommitInfo: Identifiable {
    let id: String
    let message: String
    let author: String
    let date: Date
}

struct CommitRow: View {
    let commit: GitCommitInfo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(commit.message)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(commit.id.prefix(7))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)

                    Text(commit.date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

struct StatBox: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
