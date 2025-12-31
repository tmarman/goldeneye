# F001: V1 Local Runtime (Mac Studio M3 Ultra)

**Status**: Active
**Priority**: P0 — Critical Path
**Target**: Single Mac Studio deployment

---

## Goal

Build a fully functional agent system running locally on a Mac Studio M3 Ultra. No cloud dependencies. Validate core architecture before distributing.

---

## Target Hardware

| Spec | Value |
|------|-------|
| Machine | Mac Studio M3 Ultra |
| Memory | 192GB unified |
| Model | 70B+ quantized (Llama, Qwen, etc.) |
| Expected Speed | ~200+ tok/s with MLX |

---

## V1 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Mac Studio M3 Ultra                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                   AgentKit Server                     │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │  │
│  │  │  A2A     │  │  Agent   │  │  Tool    │           │  │
│  │  │ Endpoints│  │  Runtime │  │  System  │           │  │
│  │  └────┬─────┘  └────┬─────┘  └────┬─────┘           │  │
│  │       │             │             │                  │  │
│  │  ┌────┴─────────────┴─────────────┴────┐            │  │
│  │  │         Hummingbird HTTP            │            │  │
│  │  └─────────────────────────────────────┘            │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                  │
│  ┌───────────────────────┴───────────────────────────┐     │
│  │                   MLX Runtime                      │     │
│  │  ┌─────────────┐  ┌─────────────┐                 │     │
│  │  │ Model Loader│  │  Inference  │                 │     │
│  │  │ (Qwen-72B)  │  │   Engine    │                 │     │
│  │  └─────────────┘  └─────────────┘                 │     │
│  └───────────────────────────────────────────────────┘     │
│                          │                                  │
│  ┌───────────────────────┴───────────────────────────┐     │
│  │                 Local Storage                      │     │
│  │  ~/AgentKit/                                       │     │
│  │  ├── sessions/     # Session state (JSON)          │     │
│  │  ├── artifacts/    # Generated outputs             │     │
│  │  ├── models/       # MLX model cache               │     │
│  │  └── config/       # Agent configs                 │     │
│  └───────────────────────────────────────────────────┘     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
          ▲
          │ HTTP :8080 (A2A + Web UI)
          │
    ┌─────┴─────┐
    │  Clients  │
    │  (local)  │
    └───────────┘
```

---

## Deliverables

### Phase 1: Core Runtime
- [ ] Swift Package structure (`AgentKit`)
- [ ] `Agent` protocol and basic implementation
- [ ] `AgentLoop` execution engine
- [ ] `AgentEvent` stream types
- [ ] Basic session management (in-memory → file)

### Phase 2: MLX Integration
- [ ] `LLMProvider` protocol
- [ ] `MLXProvider` implementation
- [ ] Model loading and caching
- [ ] Streaming token generation
- [ ] Context window management

### Phase 3: Tool System
- [ ] `Tool` protocol
- [ ] `@Tool` macro (or builder pattern for v1)
- [ ] Built-in tools:
  - [ ] `Read` — read files
  - [ ] `Write` — write files
  - [ ] `Bash` — run commands
  - [ ] `Glob` — find files
  - [ ] `Grep` — search content

### Phase 4: HTTP Server
- [ ] Hummingbird setup
- [ ] A2A endpoints:
  - [ ] `POST /a2a/message` (SendMessage)
  - [ ] `POST /a2a/message/stream` (SendStreamingMessage)
  - [ ] `GET /a2a/task/{id}` (GetTask)
  - [ ] `GET /a2a/tasks` (ListTasks)
  - [ ] `POST /a2a/task/{id}/cancel` (CancelTask)
- [ ] `GET /.well-known/agent.json` (Agent Card)
- [ ] Basic web UI for testing

### Phase 5: Testing & Validation
- [ ] Unit tests for core types
- [ ] Integration tests with real MLX inference
- [ ] End-to-end test: submit task → get result
- [ ] Performance benchmarks

---

## Package Structure

```
AgentKit/
├── Package.swift
├── Sources/
│   ├── AgentKit/              # Core library
│   │   ├── Agent/
│   │   │   ├── Agent.swift
│   │   │   ├── AgentLoop.swift
│   │   │   ├── AgentEvent.swift
│   │   │   └── AgentConfiguration.swift
│   │   ├── Tools/
│   │   │   ├── Tool.swift
│   │   │   ├── ToolRegistry.swift
│   │   │   └── BuiltIn/
│   │   ├── Session/
│   │   │   ├── Session.swift
│   │   │   └── SessionStore.swift
│   │   ├── LLM/
│   │   │   ├── LLMProvider.swift
│   │   │   └── MLXProvider.swift
│   │   └── A2A/
│   │       ├── A2ATypes.swift
│   │       └── A2AServer.swift
│   ├── AgentKitServer/        # HTTP server executable
│   │   └── main.swift
│   └── AgentKitCLI/           # CLI tool for testing
│       └── main.swift
└── Tests/
    └── AgentKitTests/
```

---

## Dependencies

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.10.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
]
```

---

## Key Decisions for V1

| Decision | Choice | Rationale |
|----------|--------|-----------|
| LLM Framework | MLX | Fastest on Apple Silicon, native Swift |
| HTTP Server | Hummingbird | Minimal, SwiftNIO-native |
| Storage | Local files | Simple, no dependencies |
| Protocol | A2A | Future interop, well-specified |
| Auth | None (local) | V1 is local-only |

---

## Open Questions

1. **Model choice**: Qwen-72B? Llama-70B? Both?
2. **Tool permissions**: Sandbox bash? Allow all for v1?
3. **Concurrent tasks**: Queue or parallel execution?
4. **Web UI**: Minimal HTML or SwiftUI app?

---

## Success Criteria

- [ ] Can submit a task via HTTP and get streaming response
- [ ] Agent can use tools (read/write files, run commands)
- [ ] Session state persists across restarts
- [ ] Achieves >100 tok/s on 70B model
- [ ] Clean shutdown with task state preservation
