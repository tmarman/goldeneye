import AgentKit
import SwiftUI

// MARK: - Agent Recruitment View

/// A gallery view for browsing and recruiting agent templates
struct AgentRecruitmentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: AgentCategory? = nil
    @State private var searchText = ""
    @State private var selectedTemplate: AgentTemplate? = nil
    @State private var showingRecruitSheet = false

    var filteredTemplates: [AgentTemplate] {
        var templates = AgentTemplate.allTemplates

        if let category = selectedCategory {
            templates = templates.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            templates = templates.filter {
                $0.name.lowercased().contains(query) ||
                $0.role.lowercased().contains(query) ||
                $0.tagline.lowercased().contains(query) ||
                $0.skills.contains { $0.lowercased().contains(query) }
            }
        }

        return templates
    }

    var body: some View {
        NavigationSplitView {
            // Category sidebar
            categorySidebar
        } detail: {
            // Template gallery
            VStack(spacing: 0) {
                // Header
                headerView

                Divider()

                // Gallery
                if filteredTemplates.isEmpty {
                    emptyState
                } else {
                    templateGallery
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showingRecruitSheet) {
            if let template = selectedTemplate {
                RecruitAgentSheet(template: template)
            }
        }
    }

    // MARK: - Category Sidebar

    private var categorySidebar: some View {
        List(selection: $selectedCategory) {
            Section {
                Label("All Agents", systemImage: "person.2")
                    .tag(nil as AgentCategory?)
            }

            Section("Categories") {
                ForEach(AgentCategory.allCases, id: \.self) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .tag(category as AgentCategory?)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Recruit")
        .frame(minWidth: 200)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedCategory?.rawValue ?? "All Agents")
                    .font(.title)
                    .fontWeight(.bold)

                Text("\(filteredTemplates.count) agents available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search agents...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
            }
            .padding(8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            // Build custom agent button
            Button(action: {
                dismiss()
                appState.showAgentBuilder = true
            }) {
                Label("Build Custom", systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Template Gallery

    private var templateGallery: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 320, maximum: 400), spacing: 20)
            ], spacing: 20) {
                ForEach(filteredTemplates) { template in
                    AgentTemplateCard(
                        template: template,
                        onRecruit: {
                            selectedTemplate = template
                            showingRecruitSheet = true
                        }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No agents found")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Try a different search or category")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Agent Template Card

struct AgentTemplateCard: View {
    let template: AgentTemplate
    let onRecruit: () -> Void
    @State private var isHovered = false
    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with avatar
            HStack(spacing: 12) {
                // Avatar - muted gray with subtle accent
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 56, height: 56)

                    Text(template.personality.emoji)
                        .font(.title)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)

                    Text(template.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Category badge - subtle gray
                Text(template.category.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
            .padding()

            Divider()

            // Tagline
            Text("\"\(template.tagline)\"")
                .font(.subheadline)
                .italic()
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)

            // Skills preview
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(template.skills.prefix(4), id: \.self) { skill in
                        Text(skill)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(Capsule())
                    }
                    if template.skills.count > 4 {
                        Text("+\(template.skills.count - 4)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal)
            }

            Spacer(minLength: 12)

            // Actions
            HStack {
                Button(action: { showingDetail = true }) {
                    Label("Learn More", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button(action: onRecruit) {
                    Label("Recruit", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.background)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(isHovered ? 0.15 : 0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.12 : 0.06), radius: isHovered ? 8 : 4, y: isHovered ? 3 : 1)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .sheet(isPresented: $showingDetail) {
            AgentTemplateDetailView(template: template, onRecruit: onRecruit)
        }
    }
}

// MARK: - Agent Template Detail View

struct AgentTemplateDetailView: View {
    let template: AgentTemplate
    let onRecruit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hero section
                HStack(spacing: 20) {
                    // Large avatar - muted style
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 100, height: 100)

                        Text(template.personality.emoji)
                            .font(.system(size: 48))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(template.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text(template.role)
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Label(template.category.rawValue, systemImage: template.category.icon)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.06))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())

                            Label(template.personality.communicationStyle.rawValue, systemImage: "bubble.left")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.06))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()
                }
                .padding(.bottom)

                // Tagline
                Text("\"\(template.tagline)\"")
                    .font(.title3)
                    .italic()
                    .foregroundStyle(.secondary)

                Divider()

                // Backstory
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backstory")
                        .font(.headline)

                    Text(template.backstory)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }

                Divider()

                // Skills
                VStack(alignment: .leading, spacing: 12) {
                    Text("Skills & Expertise")
                        .font(.headline)

                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 150), spacing: 8)
                    ], spacing: 8) {
                        ForEach(template.skills, id: \.self) { skill in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                                Text(skill)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                Divider()

                // Personality
                VStack(alignment: .leading, spacing: 12) {
                    Text("Personality")
                        .font(.headline)

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trait")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(template.personality.trait)
                                .font(.body)
                        }

                        Divider()
                            .frame(height: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Style")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(template.personality.communicationStyle.rawValue)
                                .font(.body)
                        }
                    }
                    .padding()
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(32)
        }
        .frame(width: 600, height: 700)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button(action: {
                    dismiss()
                    onRecruit()
                }) {
                    Label("Recruit \(template.name)", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Recruit Agent Sheet

struct RecruitAgentSheet: View {
    let template: AgentTemplate
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var customName: String
    @State private var selectedModel = "claude-3-opus"
    @State private var isRecruiting = false

    let availableModels = [
        "claude-3-opus",
        "claude-3-sonnet",
        "gpt-4o",
        "gpt-4-turbo",
        "local-ollama"
    ]

    init(template: AgentTemplate) {
        self.template = template
        self._customName = State(initialValue: template.name)
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 64, height: 64)

                    Text(template.personality.emoji)
                        .font(.largeTitle)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recruiting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(template.role)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Spacer()
            }

            Divider()

            // Configuration
            VStack(alignment: .leading, spacing: 16) {
                // Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Agent Name")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("Name", text: $customName)
                        .textFieldStyle(.roundedBorder)

                    Text("You can give your agent a custom name")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Model selection
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Model")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("Model", selection: $selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()

                    Text("Choose which AI model powers this agent")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // What you'll get
            VStack(alignment: .leading, spacing: 8) {
                Text("This agent will help you with:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(template.skills.prefix(3), id: \.self) { skill in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tertiary)
                        Text(skill)
                    }
                    .font(.subheadline)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button(action: recruitAgent) {
                    if isRecruiting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Recruit \(customName)", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(customName.isEmpty || isRecruiting)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    private func recruitAgent() {
        isRecruiting = true

        // Create the agent from template
        Task {
            // Simulate recruitment process
            try? await Task.sleep(for: .milliseconds(800))

            await MainActor.run {
                // Add to registered agents
                let recruitedAgent = RecruitedAgent(
                    id: UUID().uuidString,
                    name: customName,
                    templateId: template.id,
                    template: template,
                    model: selectedModel,
                    createdAt: Date()
                )

                appState.recruitedAgents.append(recruitedAgent)
                isRecruiting = false
                dismiss()
            }
        }
    }
}

// MARK: - Recruited Agent Model

struct RecruitedAgent: Identifiable, Hashable {
    let id: String
    let name: String
    let templateId: String
    let template: AgentTemplate
    let model: String
    let createdAt: Date

    static func == (lhs: RecruitedAgent, rhs: RecruitedAgent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
