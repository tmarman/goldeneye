# F002: A2A Protocol Implementation

**Status**: Backlog
**Mission**: M001 Foundation
**Priority**: P0

## Overview

Implement Google's Agent-to-Agent (A2A) protocol to enable interoperability with other agent systems. This is critical for the "agent-agnostic" principle.

## Background

A2A defines a standard for agents to:
- Discover each other's capabilities
- Exchange tasks and results
- Negotiate handoffs
- Share context appropriately

**Spec**: https://github.com/a2aproject/A2A

## Deliverables

### Protocol Core
- [ ] A2A message types in Swift (Codable structs)
- [ ] Agent Card implementation (capability advertisement)
- [ ] Task lifecycle messages (send, status, result)
- [ ] Streaming support for long-running tasks

### Transport Layer
- [ ] HTTP/JSON-RPC transport (required by spec)
- [ ] WebSocket support for streaming
- [ ] Local transport for on-device agent communication

### Agent Discovery
- [ ] Agent Card registry (local)
- [ ] Well-known endpoint resolution
- [ ] Capability matching for task routing

### Security
- [ ] Authentication mechanism
- [ ] Authorization scopes
- [ ] Message signing/verification

## Integration Points

```swift
// A2A client for calling other agents
protocol A2AClient {
    func discover(endpoint: URL) async throws -> AgentCard
    func sendTask(_ task: A2ATask, to agent: AgentCard) async throws -> TaskHandle
    func getStatus(_ handle: TaskHandle) async throws -> TaskStatus
    func cancel(_ handle: TaskHandle) async throws
}

// A2A server for receiving tasks
protocol A2AServer {
    func handleTask(_ task: A2ATask) async throws -> TaskResult
    var agentCard: AgentCard { get }
}
```

## Open Questions

1. How do we handle A2A over local network (Bonjour/mDNS)?
2. Rate limiting and quota management for remote agents?
3. Cost attribution when calling paid agent services?

## Research Required

- [ ] Deep-read A2A spec
- [ ] Survey existing A2A implementations
- [ ] Understand ACP overlap/merger implications

## Dependencies

- F001: Core Runtime (agent lifecycle)
