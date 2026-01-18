# Agentic Operating System

## Vision

An operating system where **agents are the fundamental compute primitive**, like processes in Unix. Each agent runs in isolation (its own VM), communicates through well-defined channels, and operates on shared state through git.

```
┌─────────────────────────────────────────────────────────────────┐
│                     EXPERIENCE LAYER                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐    │
│  │  Work    │  │  Quest   │  │ Journal  │  │   Custom     │    │
│  │  Mode    │  │  RPG     │  │  Mode    │  │   Skin       │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     SPACE LAYER (Contexts)                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   Work Space    │  │  Personal Space │  │  Project X      │ │
│  │   (git repo)    │  │   (git repo)    │  │  (git repo)     │ │
│  │                 │  │                 │  │                 │ │
│  │ docs, threads,  │  │ journal, goals, │  │ code, specs,    │ │
│  │ decisions       │  │ memories        │  │ artifacts       │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     ORCHESTRATION LAYER                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   EventBus   │  │  Scheduler   │  │   Message Router     │  │
│  │              │  │  (cron-like) │  │   (A2A, PRs)         │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     AGENT LAYER (Processes/VMs)                 │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐           │
│  │ Agent A │  │ Agent B │  │ Agent C │  │ Agent D │           │
│  │ (VM)    │  │ (VM)    │  │ (VM)    │  │ (VM)    │           │
│  │         │  │         │  │         │  │         │           │
│  │worktree │  │worktree │  │worktree │  │worktree │           │
│  │sandbox  │  │sandbox  │  │sandbox  │  │sandbox  │           │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     KERNEL (AgentKit Core)                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌──────────┐ │
│  │ AgentLoop  │  │ToolRegistry│  │ GitManager │  │ Approvals│ │
│  └────────────┘  └────────────┘  └────────────┘  └──────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Core OS Concepts

### 1. Agents as VMs

Each agent is an isolated execution environment:

```swift
/// An agent VM - isolated compute with its own:
/// - Worktree (filesystem sandbox)
/// - Context window (memory)
/// - Tool access (syscalls)
/// - Event subscriptions (interrupts)
actor AgentVM {
    let id: AgentID
    let worktree: Worktree          // Isolated filesystem
    let context: ContextWindow      // Agent's "memory"
    let capabilities: [Capability]  // What syscalls it can make
    let subscriptions: [EventFilter] // What wakes it up

    // VM lifecycle
    func spawn() async -> AgentVM   // Fork a child agent
    func exec(task: Task) async     // Run a task
    func suspend() async            // Pause execution
    func resume() async             // Continue execution
    func terminate() async          // Kill the VM
}
```

**Isolation guarantees:**
- File changes scoped to worktree branch
- No direct memory sharing between agents
- Communication only through defined channels
- Resource limits (tokens, iterations, time)

### 2. Git as Filesystem + IPC

Git serves dual purposes:

**As Filesystem:**
- Each Space is a git repo
- Documents, configs, artifacts versioned automatically
- Agents work on branches, never directly on main
- History = audit log

**As IPC (Pull Requests = Messages):**
```swift
/// A Decision Card is like a PR - a proposed change from one agent to another
struct DecisionCard: Codable {
    let id: DecisionID
    let source: AgentID             // Who proposed
    let target: SpaceID             // Where it goes
    let branch: String              // The changes
    let title: String
    let description: String
    let status: DecisionStatus      // open, merged, rejected
    let reviews: [Review]           // Other agents' feedback
    let approvals: [Approval]       // Human approvals if needed
}

enum DecisionStatus {
    case draft                      // Agent still working
    case proposed                   // Ready for review
    case reviewing                  // Under review by other agents
    case approved                   // Ready to merge
    case merged                     // Changes applied
    case rejected                   // Changes rejected
    case conflicted                 // Needs resolution
}
```

**Content flow:**
```
Agent A works on branch → Creates DecisionCard →
Agent B reviews → Human approves → Merge to main
```

### 3. Events as Interrupts/Signals

Events wake agents, like interrupts wake processes:

```swift
/// System-wide event types (like signals)
enum SystemEvent {
    // Process lifecycle
    case agentSpawned(AgentID)
    case agentTerminated(AgentID, reason: TerminationReason)

    // IPC
    case decisionCardCreated(DecisionID)
    case decisionCardReviewed(DecisionID, by: AgentID)
    case decisionCardMerged(DecisionID)

    // Scheduling
    case scheduled(ScheduleID)
    case deadline(DeadlineID)

    // External
    case userInput(InputEvent)
    case externalWebhook(WebhookEvent)

    // Space changes
    case spaceUpdated(SpaceID, changes: [Change])
    case documentCreated(DocumentID, in: SpaceID)
}

/// Agent subscribes to events it cares about
struct AgentSubscription {
    let agent: AgentID
    let filter: EventFilter
    let priority: Priority
    let wakePolicy: WakePolicy      // immediate, batched, scheduled
}
```

### 4. Spaces as Contexts

A Space is a bounded context with:
- **Content**: Documents, threads, artifacts (git-versioned)
- **Agents**: Who can operate here
- **Rules**: Approval policies, automation triggers
- **Experience**: How it's presented to users

```swift
/// A Space is like a container/namespace
struct Space {
    let id: SpaceID
    let repo: GitRepository

    // Content
    var documents: [Document]
    var threads: [Thread]
    var artifacts: [Artifact]

    // Access control
    var owner: Owner                    // user, agent, or shared
    var contributors: [Contributor]     // who can read/write
    var agents: [AgentID]               // agents operating here

    // Rules
    var approvalPolicy: ApprovalPolicy
    var automations: [Automation]       // triggers for agent actions

    // Experience binding
    var experienceConfig: ExperienceConfig?
}
```

### 5. Experiences as UI Skins

The same underlying primitives can be presented differently:

```swift
/// An Experience transforms the underlying data into a themed presentation
protocol Experience {
    var id: ExperienceID { get }
    var name: String { get }

    // Transform primitives to experience-specific views
    func transform(task: AgentTask) -> ExperienceItem
    func transform(space: Space) -> ExperienceSpace
    func transform(event: SystemEvent) -> ExperienceEvent

    // Gamification hooks
    func onTaskCompleted(_ task: AgentTask) -> [Reward]?
    func calculateProgress(_ space: Space) -> Progress
}

/// Work Mode - Professional task management
struct WorkExperience: Experience {
    func transform(task: AgentTask) -> ExperienceItem {
        // Task → Work item with priority, deadline, assignee
    }
}

/// Quest RPG - Fantasy game overlay
struct QuestRPGExperience: Experience {
    func transform(task: AgentTask) -> ExperienceItem {
        // Task → Quest with XP reward, difficulty rating
        // "Fix authentication bug" → "Defeat the Auth Guardian (XP: 50)"
    }

    func onTaskCompleted(_ task: AgentTask) -> [Reward]? {
        // Award XP, unlock achievements, level up
    }
}

/// Space Explorer - Sci-fi theme
struct SpaceExplorerExperience: Experience {
    func transform(space: Space) -> ExperienceSpace {
        // Space → Planet or Space Station
        // Documents → Data logs
        // Tasks → Missions
    }
}
```

**Experience Configuration:**
```yaml
# .goldeneye/experience.yaml
experience: quest-rpg
theme:
  primary: "#8B5CF6"
  background: "fantasy-forest"

character:
  name: "Code Wizard"
  class: "Engineer"
  level: 12
  xp: 4250

mappings:
  task.bug:
    type: "monster"
    xp_base: 30
  task.feature:
    type: "quest"
    xp_base: 100
  task.refactor:
    type: "training"
    xp_base: 20

achievements:
  - id: "first_blood"
    name: "First Blood"
    description: "Fix your first bug"
    unlocked: true
  - id: "serial_killer"
    name: "Bug Slayer"
    description: "Fix 100 bugs"
    progress: 47/100
```

## Communication Patterns

### Pattern 1: PR-Based Content Flow

For substantial content changes (documents, code, artifacts):

```
┌─────────┐    creates    ┌──────────────┐    reviews    ┌─────────┐
│ Agent A │ ─────────────▶│ DecisionCard │◀──────────────│ Agent B │
└─────────┘               └──────────────┘               └─────────┘
                                 │
                                 ▼ (if approved)
                          ┌──────────────┐
                          │    Space     │
                          │   (merged)   │
                          └──────────────┘
```

### Pattern 2: Event-Based Orchestration

For coordination and state changes:

```
┌──────────┐   emit    ┌──────────┐   route   ┌──────────┐
│  Source  │ ─────────▶│ EventBus │──────────▶│  Agent   │
└──────────┘           └──────────┘           └──────────┘
                             │
                             ├───────────────▶ Agent B
                             │
                             └───────────────▶ Agent C
```

### Pattern 3: A2A Direct Messaging

For real-time agent-to-agent communication:

```
┌─────────┐   task/send   ┌─────────┐
│ Agent A │ ─────────────▶│ Agent B │
└─────────┘               └─────────┘
     ▲                         │
     │      response/stream    │
     └─────────────────────────┘
```

### Pattern 4: Human-in-the-Loop

For approvals and input:

```
┌─────────┐   approval_request   ┌───────────────┐
│  Agent  │ ────────────────────▶│ ApprovalQueue │
└─────────┘                      └───────────────┘
     ▲                                  │
     │                                  ▼
     │                           ┌───────────┐
     │         response          │   Human   │
     └───────────────────────────│   (UI)    │
                                 └───────────┘
```

## Scheduler (cron for agents)

```swift
/// Like cron, but for agent tasks
actor AgentScheduler {
    var schedules: [Schedule]

    struct Schedule {
        let id: ScheduleID
        let pattern: SchedulePattern    // cron-like or natural language
        let agent: AgentID
        let task: AgentTask
        let space: SpaceID?
        let enabled: Bool
    }

    enum SchedulePattern {
        case cron(String)               // "0 9 * * MON-FRI"
        case interval(Duration)         // Every 30 minutes
        case natural(String)            // "every morning at 9am"
        case event(EventFilter)         // When specific event occurs
    }
}
```

## Process Hierarchy

```swift
/// Agent spawning creates a process tree
actor Concierge {
    // The init process - always running
    // Routes tasks to appropriate agents
    // Spawns new agents as needed
}

actor Agent {
    weak var parent: Agent?
    var children: [Agent]

    func spawn(config: AgentConfiguration) async -> Agent {
        let child = Agent(config: config, parent: self)
        children.append(child)
        return child
    }
}

// Process tree example:
// Concierge (pid: 0)
// ├── ResearchAgent (pid: 1)
// │   ├── WebSearchAgent (pid: 3)
// │   └── SummaryAgent (pid: 4)
// ├── CodingAgent (pid: 2)
// │   ├── TestAgent (pid: 5)
// │   └── ReviewAgent (pid: 6)
// └── SchedulerAgent (pid: 7)
```

## Resource Limits (ulimits for agents)

```swift
struct AgentLimits {
    var maxTokensPerTask: Int = 128_000
    var maxIterationsPerTask: Int = 100
    var maxConcurrentTasks: Int = 5
    var maxChildAgents: Int = 10
    var maxWorktreeSize: ByteCount = .gigabytes(1)
    var timeout: Duration = .hours(1)
    var toolAllowlist: [ToolID]?
    var toolDenylist: [ToolID]?
}
```

## Implementation Phases

### Phase 1: Core VM Isolation
- [ ] Formalize AgentVM abstraction
- [ ] Strict worktree isolation
- [ ] Resource limit enforcement
- [ ] Process lifecycle (spawn, exec, suspend, terminate)

### Phase 2: Communication Channels
- [ ] DecisionCard (PR-like) implementation
- [ ] Event priority and batching
- [ ] A2A protocol completion
- [ ] Message routing rules

### Phase 3: Scheduler
- [ ] Cron-like scheduling
- [ ] Event-triggered scheduling
- [ ] Natural language schedule parsing
- [ ] Schedule management UI

### Phase 4: Experience Layer
- [ ] Experience protocol definition
- [ ] Work Mode (default professional UI)
- [ ] Quest RPG experience
- [ ] Experience switching
- [ ] Gamification system (XP, achievements, levels)

### Phase 5: Multi-User / Distributed
- [ ] Remote agent discovery
- [ ] Cross-machine communication
- [ ] Shared spaces with conflict resolution
- [ ] Agent marketplace

## Example: Work RPG Flow

```
User creates task: "Fix the login bug"
                    │
                    ▼
┌─────────────────────────────────────────┐
│           KERNEL LAYER                  │
│  • Creates AgentTask                    │
│  • Spawns CodingAgent VM                │
│  • Sets up worktree isolation           │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│          EXPERIENCE LAYER               │
│  Quest RPG transforms this to:          │
│                                         │
│  ⚔️  NEW QUEST: Bug Slayer              │
│  Defeat the Login Guardian              │
│  Difficulty: ⭐⭐⭐                      │
│  Reward: 50 XP                          │
│  [Accept Quest]                         │
└─────────────────────────────────────────┘
                    │
                    ▼
        Agent completes task
                    │
                    ▼
┌─────────────────────────────────────────┐
│          EXPERIENCE LAYER               │
│                                         │
│  🎉 QUEST COMPLETE!                     │
│  You defeated the Login Guardian!       │
│  +50 XP                                 │
│  Progress: ████████░░ 80% to Level 13   │
│                                         │
│  Achievement Unlocked: 🏆 Bug Slayer    │
└─────────────────────────────────────────┘
```

## Key Principles

1. **Agents are isolated by default** - No shared mutable state, communication through channels
2. **Git is the source of truth** - All content changes versioned, PRs for review
3. **Events for coordination** - Loose coupling, agents react to events
4. **Experiences are skins** - Same underlying system, different presentations
5. **Humans in the loop** - Critical decisions always have approval gates
6. **Everything is observable** - Events, history, audit logs for debugging

## Related Files

- `AgentKit/Sources/AgentKit/Agent/` - Core agent primitives
- `AgentKit/Sources/AgentKit/Space/` - Space and document management
- `AgentKit/Sources/AgentKit/Events/` - Event bus and routing
- `AgentKit/Sources/AgentKit/CLIRunner/` - Worktree isolation
- `AgentKit/Sources/AgentKit/A2A/` - Agent-to-agent protocol
