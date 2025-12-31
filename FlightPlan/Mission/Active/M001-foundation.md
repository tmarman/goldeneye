# M001: Foundation Phase

**Status**: Active
**Priority**: P0 - Critical Path
**Timeframe**: Current focus

## Objective

Establish the foundational architecture and validate core concepts before scaling to full feature set.

## Success Criteria

- [ ] Core agent runtime executing tasks in Swift
- [ ] File-based storage working with iCloud
- [ ] ACE context management principles implemented
- [ ] Basic A2A protocol support for agent interoperability
- [ ] Proof-of-concept port of Claude Agent SDK patterns

## Strategic Rationale

Building all four pillars in parallel ensures:
1. **Runtime** gives us something tangible to test
2. **Protocols** ensure we're not building in isolation
3. **ACE research** grounds our context management in proven theory
4. **SDK port** leverages existing agent patterns rather than reinventing

## Key Decisions Needed

- [ ] Swift concurrency model for agent execution (actors? structured concurrency?)
- [ ] File format for agent state (JSON? Protocol Buffers? Custom?)
- [ ] A2A vs ACP priority (or both simultaneously?)
- [ ] Local vs PCC execution split for v1

## Related Flights

- F001: Core Agent Runtime
- F002: A2A Protocol Implementation
- F003: ACE Research Spike
- F004: Claude SDK Pattern Port
