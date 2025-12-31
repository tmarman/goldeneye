# Current Project State

**Last Updated**: 2024-12-31
**Phase**: Ideation → Planning

## Status Summary

AgentKit is in early planning phase. FlightPlan structure has been initialized with:
- Business context and positioning captured
- Technical architecture outlined
- Work broken into 6 Flights (F001-F006)
- No code written yet

## Active Work

| Flight | Status | Description |
|--------|--------|-------------|
| F001 | Backlog | Core Agent Runtime |
| F002 | Backlog | A2A Protocol |
| F003 | Backlog | ACE Research Spike |
| F004 | Backlog | Claude SDK Port |
| F005 | Backlog | Developer SDK |
| F006 | Backlog | Docs & Landing Page |

## Recommended Next Steps

1. **Start F003 (ACE Research)** — Grounds our context design in research
2. **Start F001 (Core Runtime)** — Foundational, unblocks everything
3. **Parallel: F002 (A2A)** — Can be researched while runtime is built

## Key Decisions Pending

- [ ] Swift concurrency model (actors? structured concurrency?)
- [ ] File format for agent state
- [ ] A2A vs ACP protocol priority
- [ ] Documentation site platform

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
