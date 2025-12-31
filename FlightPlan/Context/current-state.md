# Current Project State

**Last Updated**: 2025-12-31
**Phase**: Planning → Implementation

## Status Summary

Research complete. Ready to build V1 on Mac Studio M3 Ultra.

Key research completed:
- ACE context management patterns
- A2A protocol specification (full schema)
- Swift server ecosystem (Hummingbird)
- MLX local inference (~230 tok/s on M2 Ultra)

## Active Work

| Flight | Status | Description |
|--------|--------|-------------|
| **F001** | **Active** | V1 Local Runtime (Mac Studio) |
| F002 | Backlog | A2A Protocol (integrated into F001) |
| F003 | Complete | ACE Research |
| F004 | Backlog | Claude SDK Port |
| F005 | Backlog | Developer SDK |
| F006 | Backlog | Docs & Landing Page |

## V1 Target

**Hardware**: Mac Studio M3 Ultra (192GB)
**LLM**: MLX with 70B model (Qwen/Llama)
**Server**: Hummingbird HTTP with A2A endpoints
**Storage**: Local files (`~/AgentKit/`)

## Current Focus

Building core runtime:
1. Swift Package structure
2. Agent protocol + loop
3. MLX integration
4. Basic tools (Read, Write, Bash)
5. A2A HTTP endpoints

## Key Decisions Made

| Decision | Choice |
|----------|--------|
| LLM Framework | MLX (fastest, native Swift) |
| HTTP Server | Hummingbird (minimal, SwiftNIO) |
| Storage | Local files (simple for v1) |
| Protocol | A2A (future interop) |
| Context Pattern | ACE (incremental, not aggressive compaction) |

## Repository State

```
/Users/tim/dev/agents/
├── input.md                    # Original vision notes
└── FlightPlan/
    ├── Manifest/
    │   └── business.json       # Project identity
    ├── Mission/
    │   ├── Active/
    │   │   └── M001-foundation.md
    │   └── Exploring/
    │       └── M002-apple-integration.md
    ├── Flight/
    │   └── Backlog/
    │       ├── F001-core-runtime.md
    │       ├── F002-a2a-protocol.md
    │       ├── F003-ace-research.md
    │       ├── F004-claude-sdk-port.md
    │       ├── F005-developer-sdk.md
    │       └── F006-docs-landing.md
    ├── Charts/
    │   ├── Business/
    │   │   └── positioning.md
    │   ├── Technical/
    │   │   ├── architecture-overview.md
    │   │   └── swift-patterns.md
    │   └── Setup/
    │       └── getting-started.md
    ├── Crew/
    │   └── Learnings/
    │       ├── Corrections/
    │       └── Patterns/
    └── Context/
        └── current-state.md    # This file
```

## Notes for Future Sessions

When picking up this project:
1. Read `Manifest/business.json` for strategic context
2. Check `Context/current-state.md` (this file) for where we left off
3. Look at `Mission/Active/` for current priorities
4. Pick a Flight from `Flight/Backlog/` and move to `Flight/Active/`
