# Research Summary: AgentKit Foundation

## Sources
- [ACE Paper](https://arxiv.org/abs/2510.04618) — Context management
- [A2A Protocol](https://a2a-protocol.org/latest/specification/) — Agent interoperability
- [Swift Server](https://www.swift.org/documentation/server/) — Server ecosystem
- [MLX](https://machinelearning.apple.com/research/exploring-llms-mlx-m5) — Local inference
- [Local LLM Study](https://arxiv.org/abs/2511.05502) — Performance benchmarks

---

## 1. ACE (Agentic Context Engineering)

### Problem
- **Brevity Bias**: LLMs drop domain insights for concise summaries
- **Context Collapse**: Iterative rewriting erodes details over time

### Solution: Generation → Reflection → Curation
- Don't over-compact — use incremental refinement
- Contexts are "evolving playbooks" that grow systematically
- Design for long-context models (128K+)

### AgentKit Implications
```swift
protocol ContextManager {
    func append(_ content: ContextContent) async
    func reflect() async -> ContextInsights   // Self-review before compaction
    func curate() async                       // Organize, don't compress
    var currentWindow: [ContextContent] { get }
}
```

---

## 2. A2A Protocol

### Architecture
```
Client → JSON-RPC 2.0 over HTTP(S) → Server
         ↓
    /.well-known/agent.json (Agent Card)
```

### Task States
| State | Terminal |
|-------|----------|
| SUBMITTED, WORKING, INPUT_REQUIRED, AUTH_REQUIRED | No |
| COMPLETED, FAILED, CANCELLED, REJECTED | Yes |

### Part Types
- **TextPart**: `{ kind: "text", text: "..." }`
- **FilePart**: `{ kind: "file", file: { uri | bytes }, mime_type }`
- **DataPart**: `{ kind: "data", data: {...} }`

### Key Methods
- `SendMessage` / `SendStreamingMessage`
- `GetTask` / `ListTasks` / `CancelTask`
- `SubscribeToTask` (SSE)

---

## 3. Swift Server Ecosystem

### Frameworks
| Framework | Philosophy | Use Case |
|-----------|------------|----------|
| **Hummingbird** | Minimal, SwiftNIO-native | Microservices ✓ |
| **Vapor** | Full-featured | Web apps |

### Deployment
- AWS Lambda: ~100ms cold start, competitive with Go
- SwiftCloud: New IaC-style deployment

---

## 4. On-Device LLM (Apple Silicon)

### Performance Rankings (M2 Ultra, 192GB)
| Framework | tok/s | Notes |
|-----------|-------|-------|
| **MLX** | ~230 | Fastest, native Swift API |
| MLC-LLM | ~190 | Lower TTFT |
| llama.cpp | ~150 | Lightweight |
| Ollama | 20-40 | Developer convenience |

### MLX Advantages
- Native Swift, Python, C++, C APIs
- Unified memory (zero-copy CPU↔GPU)
- Metal GPU acceleration
- M5 Neural Accelerators: 4× TTFT speedup

### Model Requirements
| Size | RAM | Performance |
|------|-----|-------------|
| 7-8B Q4 | 8GB | Good |
| 13B Q4 | 16GB | Good |
| 70B Q4 | 64-128GB | 30-45 tok/s |

---

## V1 Target: Mac Studio M3 Ultra

### Hardware Profile
- 192GB unified memory
- Can run 70B+ models comfortably
- ~200+ tok/s with MLX

### V1 Architecture
```
┌─────────────────────────────────────────────┐
│              Mac Studio M3 Ultra             │
│                                              │
│  ┌────────────┐  ┌────────────────────────┐ │
│  │  AgentKit  │  │       MLX Runtime      │ │
│  │   Server   │──│  (Llama 70B / Qwen 72B)│ │
│  │ (Hummingbird)│ └────────────────────────┘ │
│  └─────┬──────┘                              │
│        │ A2A                                 │
│        ▼                                     │
│  ┌────────────┐  ┌────────────────────────┐ │
│  │   Clients  │  │    Local File Store    │ │
│  │ (macOS/iOS)│  │   ~/AgentKit/data/     │ │
│  └────────────┘  └────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### V1 Scope
- Single Mac Studio as server
- MLX for local inference (no cloud dependency)
- Hummingbird HTTP server with A2A endpoints
- Local file storage (not iCloud yet)
- macOS client app for testing
