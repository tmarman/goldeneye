# F005: Developer SDK & Building Blocks

**Status**: Backlog
**Mission**: M002 Apple Integration
**Priority**: P2

## Overview

Create layered building blocks for developers to build agentic applications on Apple platforms. This is the "platform" play.

## Vision

```
┌─────────────────────────────────────────────┐
│         Consumer Apps (Trip Planner)        │
├─────────────────────────────────────────────┤
│           AgentKit High-Level API           │
├─────────────────────────────────────────────┤
│    Tools    │   Protocols   │   Storage     │
├─────────────────────────────────────────────┤
│              Core Runtime (F001)            │
└─────────────────────────────────────────────┘
```

## SDK Layers

### Layer 1: Core (Internal)
- Agent runtime
- Tool execution
- State management
- *Not directly exposed — foundation for higher layers*

### Layer 2: Primitives
- `@Tool` macro for tool definition
- `AgentTask` for task submission
- `AgentContext` for context management
- `AgentStorage` for persistence

### Layer 3: Patterns
- Pre-built agent types (Research, Planning, Coding)
- Workflow templates
- Integration helpers (AppIntents, Shortcuts)

### Layer 4: Components
- SwiftUI views for agent UIs
- Chat interfaces
- Progress indicators
- Result renderers

## Developer Experience Goals

```swift
// Simple case: one-shot task
let result = try await Agent.run("Summarize this document",
    with: document)

// Custom agent with tools
@Agent struct ResearchAgent {
    @Tool func webSearch(query: String) async -> [SearchResult]
    @Tool func readDocument(url: URL) async -> Document

    func research(topic: String) async -> ResearchReport {
        // orchestration logic
    }
}

// AppIntents integration
struct StartResearchIntent: AppIntent {
    @Parameter var topic: String

    func perform() async throws -> some IntentResult {
        let agent = ResearchAgent()
        let report = try await agent.research(topic: topic)
        return .result(value: report)
    }
}
```

## Deliverables

- [ ] SDK architecture design
- [ ] `@Tool` macro implementation
- [ ] Core primitives API
- [ ] Documentation and examples
- [ ] Sample app demonstrating SDK

## Dependencies

- F001: Core Runtime
- F002: A2A Protocol (for multi-agent)
