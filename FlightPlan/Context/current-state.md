# Current Project State

**Last Updated**: 2026-01-17
**Phase**: Knowledge Backbone + Polish

## Status Summary

Core runtime architecture now has three layers:
1. **Knowledge Backbone** — World knowledge (vectors) + Built understanding (scoped folders)
2. **Envoy App** — Interactive UI for chat, approvals, and configuration
3. **Background Runners** — Autonomous agent execution

AgentKitConsole renamed to Envoy. UI requires polish based on user acceptance feedback.

**Blocking Issues**:
- Threads not persisting/swapping with spaces (#2, #29)
- Action items not wired up (#5)
- Filter options cut off (#27)

## Active Work

| Flight | Status | Description |
|--------|--------|-------------|
| **F001** | Complete | V1 Local Runtime (Mac Studio) |
| **F002** | Complete | Console UI Development |
| **F003** | **Active** | User Feedback & Polish (40 items) |
| **F008** | Complete | Knowledge Backbone |
| **F009** | Complete | Slack History Indexer |
| **F010** | Complete | Background Task Runner |
| F004 | Backlog | About Me Space (Concierge) |
| F005 | Backlog | Agent Providers (Claude Code, Codex) |
| F006 | Backlog | Docs & Landing Page |

## Knowledge Backbone (F008-F010)

Two complementary knowledge systems:

**World Knowledge** — What exists (indexed, searchable)

- **KnowledgeStore**: Central actor managing all operations
- **KnowledgeDatabase**: SQLite storage with WAL mode
- **EmbeddingEngine**: MLX-based vector embeddings
- **Chunker**: Multiple chunking strategies (fixed, sentence, paragraph, semantic, markdown)
- **SlackIndexer**: Full Slack workspace indexing with rate limiting
- **MCP Tools**: knowledge_search, knowledge_ingest, knowledge_stats, knowledge_entities

**Built Understanding** — What you know (evolving, scoped)

- **KnowledgeSpaceManager**: Multiple isolated knowledge spaces
- Scoped folders with invisible git backing
- Human-readable markdown context files
- Folder hierarchy defines context boundaries

**Background Execution**

- **BackgroundTaskRunner**: General task execution with progress tracking and cancellation
- **CLIRunner**: Shell command execution (existing)
- Pre-built tasks: Slack full indexing, incremental sync

## V1 Implementation Complete

**Hardware**: Mac Studio M3 Ultra (192GB)
**LLM**: MLX with configurable models via Ollama
**Server**: Hummingbird HTTP with A2A endpoints
**Storage**: Local files + Git-backed Spaces

## Recent Session (2026-01-14)

**Session 5 - Content Sync Integration:**
1. ✅ Implemented ContentSyncService for background syncing
2. ✅ Enhanced SharedWithYouIntegration with SWHighlightCenter API
3. ✅ Wired ContentSyncService into AppState with async initialization
4. ✅ Added getReadingListItems() and getSharedItems() to MemoryStore
5. ✅ Display synced Reading List and Shared with You items in OpenSpace timeline
6. ✅ Periodic background sync (every 5 minutes) with error tracking
7. ✅ All synced content indexed for RAG retrieval
8. ✅ Implemented vector search with embeddings (SimpleEmbeddingProvider using TF-IDF)

**Session 4 - Settings Polish:**
1. ✅ Added Extensions tab to ⌘, Settings preferences window
2. ✅ Fixed Settings variable naming (`extension` → `item` to avoid keyword conflict)
3. ✅ Added ScrollView to each Settings tab for proper overflow handling
4. ✅ Added "Back to Open Space" button in SettingsDetailView for navigation
5. ✅ Wired up "Show in Dock" toggle with actual NSApp.setActivationPolicy()
6. ✅ Added onChange handlers for General Settings toggles

**Session 3 - RAG & Agent Configuration:**
1. ✅ Memory module with VecturaKit integration (on-device vector DB)
2. ✅ Safari Reading List & Shared with You integration (initial)
3. ✅ AppIntents MCP wrapper for native macOS integrations
4. ✅ Extensions settings UI (discover & enable tools)
5. ✅ Custom GPT-style chat configurator for agents
6. ✅ ChatConfigAgent for conversational agent setup

**Session 2 - UI Polish:**
1. ✅ Settings → TabView for standard macOS ⌘, prefs pattern
2. ✅ Document editor → Block drag-drop reordering
3. ✅ Document editor → Enter key creates new block after current
4. ✅ Approval flow → Deny dialog with optional reason field
5. ✅ Audited buttons/sections for functionality

**Session 1 - Demo Ready:**
1. ✅ Wired up approval flow (approve/deny buttons → AppState)
2. ✅ Decisions flow already complete with full CRUD
3. ✅ Added "Getting Started" onboarding card
4. ✅ Agent activity visualization with animated status
5. ✅ Agent conversations view

## Console UI Features

### Implemented
- **Dashboard**: Status cards, active agents, conversations, getting started
- **OpenSpace**: Post-it style capture, EventKit meeting detection, capture modes
- **Documents**: Block-based editor with drag-drop reordering, slash commands, keyboard nav
- **Decisions**: Full workflow with filtering, comments, history
- **Approvals**: Real-time approval/deny with A2A backend
- **Agents**: Activity visualization, conversation display
- **Settings**: TabView prefs (General, LLM, Server, Extensions, Approvals, Advanced)
- **Extensions**: Tool discovery, enable/disable, system integrations status
- **Agent Configurator**: Custom GPT-style chat interface for agent creation

### Architecture
```
AgentKit/
├── Memory/                     # RAG system
│   ├── MemoryStore.swift       # Vector search with embeddings
│   ├── MemoryTypes.swift       # Items, sources, sync
│   ├── EmbeddingProvider.swift # Vector embeddings (TF-IDF placeholder)
│   ├── ContentChunker.swift    # Document chunking
│   ├── MemorySyncManager.swift # Master server sync
│   ├── ContentSyncService.swift # Background sync coordinator
│   └── SafariIntegration.swift # Reading List + Shared with You
├── Extensions/                 # Tool discovery
│   ├── ExtensionRegistry.swift # Central tool registry
│   └── AppIntentsTool.swift    # Shortcuts/AppIntents wrapper
├── Agent/
│   └── ChatConfigAgent.swift   # Conversational config

AgentKitConsole/
├── AgentKitConsoleApp.swift    # App entry with Window + MenuBarExtra
├── Models/
│   ├── AppState.swift          # Global state, A2A client, managers
│   └── AgentTemplates.swift    # 18 agent templates
├── Services/
│   ├── ServerManager.swift     # Local server lifecycle
│   └── CalendarService.swift   # EventKit integration
└── Views/
    ├── ContentView.swift       # Navigation, sidebar, detail router
    ├── DashboardView.swift     # Status, agents, conversations
    ├── SettingsView.swift      # Now includes Extensions tab
    ├── AgentConfiguratorView.swift # NEW: Chat-based config UI
    └── ... (15+ view files)
```

## Key Decisions Made

| Decision | Choice |
|----------|--------|
| LLM Framework | MLX (fastest, native Swift) |
| HTTP Server | Hummingbird (minimal, SwiftNIO) |
| Storage | Git-backed Spaces (version control) |
| Protocol | A2A (agent-to-agent interop) |
| Context Pattern | ACE (incremental compaction) |
| UI Framework | SwiftUI with AppKit integration |
| Vector Search | Custom implementation with TF-IDF embeddings (upgradeable to MLX) |
| Agent Config | Chat-based (Custom GPT pattern) |

## Repository State

```
/Users/tim/dev/agents/repos/goldeneye/
├── README.md
├── FlightPlan/           # Planning & documentation
│   ├── Context/
│   │   └── current-state.md    # This file
│   ├── Flight/
│   │   └── Active/
│   │       ├── F001-v1-local-runtime.md
│   │       └── F002-console-ui-development.md
│   └── Charts/           # Technical specs
└── AgentKit/             # Swift Package
    ├── Package.swift
    └── Sources/
        ├── AgentKit/           # Core library
        ├── AgentKitConsole/    # macOS app
        ├── AgentKitCLI/        # Command line
        └── AgentKitServer/     # A2A server
```

## Next Steps

1. **Testing**: Run full demo flow with live agents
2. **Integration Testing**:
   - Test memory indexing with real documents
   - Test Safari Reading List import flow
   - Test vector search with sample queries
   - Test Extensions discovery with Shortcuts
   - Test Agent Configurator chat flow
3. **Embedding Model Upgrade** (optional future enhancement):
   - Replace SimpleEmbeddingProvider with MLX-based embeddings for better semantic search
   - Options: sentence-transformers via MLX, Ollama embeddings API, or custom trained model
4. **Feature Ideas** (future):
   - Agent wrapper for Claude Code/Codex/Gemini as orchestration tools
   - Memory sync with master server (P2P/mesh)
   - More AppIntents integrations (Notes, Mail compose)
5. **F004**: Consider Claude SDK port for enhanced capabilities

## Notes for Future Sessions

When picking up this project:
1. Run `swift build` in AgentKit/ to verify everything compiles
2. Run `swift run AgentKitConsole` to launch the app
3. Check this file for recent progress
4. Look at `Flight/Active/` for current priorities
