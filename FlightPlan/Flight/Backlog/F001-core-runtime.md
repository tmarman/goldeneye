# F001: Core Agent Runtime

**Status**: Backlog → Ready for Sprint
**Mission**: M001 Foundation
**Priority**: P0

## Overview

Build the foundational agent execution runtime in Swift. This is the kernel that everything else depends on.

## Deliverables

### Agent Lifecycle
- [ ] Agent definition structure (what IS an agent?)
- [ ] Agent instantiation and initialization
- [ ] Task queue management
- [ ] Execution loop with cancellation support
- [ ] Graceful shutdown and state persistence

### Concurrency Model
- [ ] Decide: Swift actors vs structured concurrency vs hybrid
- [ ] Task isolation and boundaries
- [ ] Progress reporting mechanism
- [ ] Timeout and deadline handling

### File-Based Storage
- [ ] Agent state serialization format
- [ ] iCloud container setup
- [ ] Conflict resolution strategy
- [ ] Version history support

### Tool System
- [ ] Tool protocol definition
- [ ] Built-in tools (file read/write, web fetch, etc.)
- [ ] Tool result handling
- [ ] Error recovery patterns

## Technical Considerations

```swift
// Strawman agent protocol
protocol Agent {
    var id: AgentID { get }
    var state: AgentState { get }

    func execute(task: Task) async throws -> TaskResult
    func pause() async
    func resume() async
    func cancel() async
}
```

## Open Questions

1. How do we handle long-running tasks that span app launches?
2. Background execution limits on iOS — workarounds?
3. State format: JSON for debuggability vs binary for efficiency?

## Dependencies

- None (foundational)

## Estimated Scope

Medium-Large — core infrastructure work
