import AgentKit
import SwiftUI

// MARK: - Task Creation View

/// View for creating a new task with explicit agent assignment
/// Shows suggestions based on workspace type and prompt analysis
struct TaskCreationView: View {
    let space: LinkedSpace?
    let onSubmit: (TaskSubmission) -> Void
    let onCancel: () -> Void

    @State private var prompt: String = ""
    @State private var selectedRunner: TaskRunner?
    @State private var suggestedRunner: TaskRunner = .claudeCode
    @State private var showingAdvanced = false
    @State private var priority: TaskPriority = .normal
    @State private var isAnalyzing = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Workspace context
                    if let space = space {
                        workspaceContext(space)
                    }

                    // Prompt input
                    promptInput

                    // Agent selection
                    agentSelection

                    // Advanced options (collapsible)
                    if showingAdvanced {
                        advancedOptions
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            actionBar
        }
        .frame(width: 500, height: 480)
        .onChange(of: prompt) { _, newValue in
            analyzePrompt(newValue)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Task")
                    .font(.headline)

                if let space = space {
                    Text("in \(space.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    // MARK: - Workspace Context

    @ViewBuilder
    private func workspaceContext(_ space: LinkedSpace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: space.type.icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
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
            }

            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Prompt Input

    private var promptInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What do you need?")
                .font(.subheadline)
                .fontWeight(.medium)

            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 150)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            // Prompt hints
            if prompt.isEmpty {
                Text("Examples: \"Fix the authentication bug\" or \"Write a blog post about...\"")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Agent Selection

    private var agentSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Assign to")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            // Runner options
            VStack(spacing: 8) {
                ForEach(TaskRunner.allCases, id: \.self) { runner in
                    RunnerOptionRow(
                        runner: runner,
                        isSelected: effectiveRunner == runner,
                        isSuggested: runner == suggestedRunner && selectedRunner == nil,
                        onSelect: { selectedRunner = runner }
                    )
                }
            }

            // Suggestion explanation
            if selectedRunner == nil {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.purple)

                    Text(suggestionReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var effectiveRunner: TaskRunner {
        selectedRunner ?? suggestedRunner
    }

    private var suggestionReason: String {
        guard let space = space else {
            return "Suggested based on your prompt"
        }

        switch space.type {
        case .code:
            return "Code workspace → Claude Code suggested"
        case .content:
            return "Content workspace → Content Agent suggested"
        case .mixed:
            return "Analyzed your prompt for best fit"
        }
    }

    // MARK: - Advanced Options

    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Text("Options")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Priority picker
            HStack {
                Text("Priority")
                    .font(.subheadline)

                Spacer()

                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            Button {
                showingAdvanced.toggle()
            } label: {
                Label(
                    showingAdvanced ? "Hide Options" : "More Options",
                    systemImage: showingAdvanced ? "chevron.up" : "chevron.down"
                )
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)

            Button(action: submitTask) {
                HStack(spacing: 4) {
                    Image(systemName: effectiveRunner.icon)
                    Text("Create Task")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    // MARK: - Actions

    private func analyzePrompt(_ text: String) {
        guard !text.isEmpty, let space = space, space.type == .mixed else {
            // Use space default for non-mixed spaces
            if let space = space {
                suggestedRunner = space.defaultRunner
            }
            return
        }

        // For mixed spaces, do quick local analysis
        // TODO: Could use LLM for smarter analysis
        isAnalyzing = true

        // Simple heuristic analysis (runs inline, no delay needed)
        suggestedRunner = space.routeTask(text)
        isAnalyzing = false
    }

    private func submitTask() {
        let submission = TaskSubmission(
            prompt: prompt.trimmingCharacters(in: .whitespaces),
            runner: effectiveRunner,
            spaceId: space?.id,
            priority: priority
        )
        onSubmit(submission)
    }
}

// MARK: - Runner Option Row

struct RunnerOptionRow: View {
    let runner: TaskRunner
    let isSelected: Bool
    let isSuggested: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: runner.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(runner.displayName)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .medium : .regular)

                        if isSuggested {
                            Text("Suggested")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }

                    Text(runnerDescription)
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

    private var runnerDescription: String {
        switch runner {
        case .claudeCode:
            return "Coding tasks with file editing, git, and terminal"
        case .contentAgent:
            return "Writing, research, and content creation"
        case .auto:
            return "Analyze task and choose the best agent"
        }
    }
}

// MARK: - Supporting Types

public struct TaskSubmission: Sendable {
    public let prompt: String
    public let runner: TaskRunner
    public let spaceId: String?
    public let priority: TaskPriority

    public init(
        prompt: String,
        runner: TaskRunner,
        spaceId: String? = nil,
        priority: TaskPriority = .normal
    ) {
        self.prompt = prompt
        self.runner = runner
        self.spaceId = spaceId
        self.priority = priority
    }
}

// Note: TaskPriority is defined in AgentKit/CLIRunner/TaskRouter.swift

