# F003: User Feedback & Polish

**Status**: Active
**Priority**: P0 - Critical (Demo Blocking)
**Depends On**: F002-console-ui-development
**Started**: 2026-01-15
**Source**: User acceptance testing feedback

---

## Goal

Address all user feedback from acceptance testing to achieve demo-ready quality. This flight captures 40 feedback items across critical bugs, UX issues, design philosophy changes, UI polish, and new feature requests.

---

## Acceptance Criteria

- [ ] All critical bugs (P0) resolved
- [ ] Core UX issues (P1) fixed
- [ ] Design philosophy changes scoped and planned
- [ ] UI polish items addressed
- [ ] New feature backlog created for future flights

---

## Critical Bugs (P0) - Must Fix

These bugs block demo readiness.

| # | Issue | Status | Notes |
|---|-------|--------|-------|
| 2 | Threads not persisting/swapping when changing spaces | ⬜ TODO | Threads show same content regardless of space selection |
| 5 | Action items not wired up | ⬜ TODO | Suggested actions on home page non-functional |
| 13 | "Show in Finder" button does nothing | ⬜ TODO | Storage settings button non-functional |
| 27 | Filter options cut off and unusable | ⬜ TODO | DM filters after "Starred" are clipped |
| 29 | Threads not filtered by space | ⬜ TODO | Same as #2 - space isolation broken |

---

## Core UX Issues (P1) - High Priority

| # | Issue | Status | Notes |
|---|-------|--------|-------|
| 6 | Can't edit space settings via `...` button | ⬜ TODO | Should change color, configs |
| 7 | Can't view/add members to a channel | ⬜ TODO | Membership management missing |
| 11 | "More models" opens wrong settings page | ⬜ TODO | Should open Models page, not General |
| 28 | Selecting agent in DMs should show thread list | ⬜ TODO | Currently no thread filtering by agent |
| 35 | Expand/collapse on sidebar spaces does nothing | ⬜ TODO | Non-functional UI element |

---

## UI Polish (P2) - Should Fix

| # | Issue | Status | Notes |
|---|-------|--------|-------|
| 4 | Thread hover actions change text wrapping | ⬜ TODO | Should pre-wrap or overlay |
| 12 | Ollama `...` button before toggle for alignment | ⬜ TODO | Model providers page |
| 18 | Still showing EXEC icon instead of robot afro | ⬜ TODO | Default agent icon not updated |
| 24 | Thread list contrast poor | ⬜ TODO | Need LLM titles, left-align like Slack |
| 30 | Collapse button positioning issues | ⬜ TODO | Should align with red/orange/yellow buttons |
| 31 | Envoy logo needs more stylization | ⬜ TODO | |

---

## Design Philosophy Changes (P1) - Requires Discussion

These represent significant UX direction changes.

### Agent-Centric Design
| # | Issue | Direction |
|---|-------|-----------|
| 10 | Remove model selector focus | Agents should be the interaction point, not models |
| 25 | DMs shouldn't show model filter | Focus on agents, they manage their own models |

### Navigation & Naming
| # | Issue | Direction |
|---|-------|-----------|
| 29 | Rename "Open Spaces" → "Headspace" | Root/cross-space view, activity across all spaces |
| 36 | Default agent auto-organizes threads | Plus moderation: move messages, branch threads |

### Recruiting Flow Rework (#32-33)
Current: Generic agent templates
Proposed:
1. **Types as Job Descriptions** - What the role should do
2. **Candidate Names** - Human names presented (no last names)
3. **Interview Flow** - Creates candidate agent, not hired until "accepted"
4. **Differentiation** - Same base, specific variations (coders, EPMs, exec types)

---

## Major New Features (Backlog → Future Flights)

### F004: About Me Space (#1)
**Concept**: Concierge agent that:
- Indexes iCloud files, Mail, Messages, Reminders
- Learns about user over time
- Suggests Space setup based on work patterns
- Powers the recruiting flow with context

### F005: Agent Providers (#15)
**Concept**: First-class support for external agent frameworks:
- AgentKit (our native agents)
- Claude Code
- Open Code
- Codex
- Folder-scoped agent management

### F006: Apple Foundation Models (#17b)
**Concept**: Native `FoundationModels` framework wrapper
- Reference: https://developer.apple.com/documentation/FoundationModels

### F007: Enhanced Model Library (#17)
- GPT-OSS 20b/120b
- GLM
- MiniMax
- Nemotron Orchestrator 8b MLX

### F008: Shortcuts Deep Integration (#21-22, #39-40)
- Support descriptions/metadata from API
- Agents create their own Shortcuts
- Expose Shortcuts for every agent
- AppIntents for Siri integration

### F009: Quick Notes & Widgets (#37-38)
- CMD-N quick notes (post-it style, multiple open)
- Widgets: Today view, open tasks, quick capture

### F010: Agent Invitation Flow (#8)
- Agent invitation starts DM
- Ask about retroactive thread processing
- Test messaging and decision cards

---

## Quick Fixes (Can Do Now)

| # | Issue | Effort |
|---|-------|--------|
| 11 | More models → correct settings page | 5 min |
| 12 | Ollama button alignment | 5 min |
| 13 | Show in Finder button | 10 min |
| 18 | Update default agent icon | 5 min |

---

## Root Cause Analysis

### Critical Bug #2, #29: Threads Not Persisting/Filtering by Space

**ROOT CAUSE: NO PERSISTENCE AT ALL**

Conversations and threads exist **only in memory**. When the app restarts, all conversations are lost.

**What IS persisted:**
- Documents → Git-backed via `GitManager.commitDocument()` → `.md` files
- Spaces → Discovered from filesystem directories

**What is NOT persisted:**
- `WorkspaceState.conversations` → `@Published var conversations: [Conversation] = []` (in-memory only)
- `Thread` model → exists but never saved anywhere
- Agent DMs → ephemeral

**Root Cause Identified**: Threads/Conversations are stored globally in `AppState.workspace.conversations`, not scoped to spaces.

**Architecture Issue**:
```
Current:
- AppState.workspace.conversations → global list
- selectedSpaceId changes → nothing reloads
- SpaceDetailView shows same data regardless of space

Required:
- Space.threads → per-space thread storage
- selectedSpaceId changes → load threads for that space
- Thread model has channelId → needs spaceId linkage
```

**Files to Modify**:
1. `AppState.swift` - Add thread management methods per space
2. `SpaceDetailView.swift` - Load threads when space selected
3. `Thread.swift` - Ensure spaceId linkage (via channel → space)
4. `Space.swift` - Add threads() method

**Fix Approach - Two Parts:**

**Part 1: Add Persistence (P0 - Critical)**

```swift
// New: ConversationStore.swift
actor ConversationStore {
    let basePath: URL  // ~/.envoy/conversations/

    func save(_ conversation: Conversation) async throws {
        let data = try JSONEncoder().encode(conversation)
        let path = basePath.appendingPathComponent("\(conversation.id.rawValue).json")
        try data.write(to: path)
    }

    func loadAll() async throws -> [Conversation] {
        // Load all .json files from basePath
    }

    func load(for spaceId: SpaceID) async throws -> [Conversation] {
        // Filter by spaceId
    }
}

// In Conversation model - add spaceId
public struct Conversation {
    var spaceId: SpaceID?  // NEW: links conversation to a space
    // ... existing properties
}
```

**Part 2: Space-Scoped Loading**

```swift
// In AppState
@Published var currentSpaceThreads: [Thread] = []

func loadThreadsForSpace(_ spaceId: SpaceID) async {
    currentSpaceThreads = try await conversationStore.load(for: spaceId)
}

// In SpaceDetailView
.onChange(of: spaceId) { _, newId in
    Task { await appState.loadThreadsForSpace(newId) }
}
```

**Files to Create/Modify:**

1. **CREATE** `ConversationStore.swift` - JSON-based persistence
2. **MODIFY** `Conversation.swift` - Add `spaceId` property
3. **MODIFY** `AppState.swift` - Wire up store, save on changes
4. **MODIFY** `SpaceDetailView.swift` - Load on space change

### Investigation Required

| # | Issue | What to Check |
|---|-------|---------------|
| 3 | Suggested actions source | Verify if LLM-generated or heuristic |
| 14 | Agentic processing on capture | Check if ChatConfigAgent is actually processing |
| 23 | Git tracking & worktree | Review version control setup |

---

## Research References

| # | Item | Link |
|---|------|------|
| 16 | Claude Cowork | https://venturebeat.com/technology/anthropic-launches-cowork-a-claude-desktop-agent-that-works-in-your-files-no |

---

## Sprint Plan

### Sprint 1: Conversation Persistence (BLOCKING)

**No persistence = all conversations lost on restart. This is the #1 priority.**

1. [ ] Create `ConversationStore.swift` actor for JSON persistence
2. [ ] Add `spaceId` property to `Conversation` model
3. [ ] Wire `ConversationStore` into `AppState.init()`
4. [ ] Auto-save on conversation changes (debounced)
5. [ ] Load conversations on app launch
6. [ ] Filter conversations by space when `selectedSpaceId` changes

### Sprint 2: Critical Bug Fixes
1. [ ] Wire up action items (#5)
2. [ ] Fix "Show in Finder" (#13)
3. [ ] Fix filter clipping (#27)

### Sprint 2: UX Fixes
1. [ ] Space settings editing (#6)
2. [ ] Channel member management (#7)
3. [ ] Settings navigation fix (#11)
4. [ ] Agent DM thread filtering (#28)
5. [ ] Sidebar expand/collapse (#35)

### Sprint 3: Polish
1. [ ] Hover action layout (#4)
2. [ ] Model provider alignment (#12)
3. [ ] Icon update (#18)
4. [ ] Thread list styling (#24)
5. [ ] Button positioning (#30)
6. [ ] Logo stylization (#31)

### Sprint 4: Design Philosophy Implementation
1. [ ] Agent-centric model hiding (#10, #25)
2. [ ] Headspace rename (#29 naming)
3. [ ] Recruiting flow rework (#32-33)

---

## Related Documents

- [F002: Console UI Development](./F002-console-ui-development.md)
- [Current State](../../Context/current-state.md)
- [Architecture Overview](../../Charts/Technical/architecture-overview.md)
