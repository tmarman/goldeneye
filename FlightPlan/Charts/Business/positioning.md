# AgentKit Positioning

## One-Liner

> Agent infrastructure for the Apple ecosystem

## Elevator Pitch

AgentKit lets developers build AI agents that run natively on Apple devices. It's model-agnostic (use any LLM), agent-agnostic (interoperate via A2A), and deeply integrated with Apple's platform — iCloud, AppIntents, SwiftUI, and Private Cloud Compute.

## Target Audiences

### Primary: Apple Platform Developers
- Building apps that need AI capabilities
- Want native Swift experience, not web wrappers
- Care about privacy and Apple ecosystem integration

### Secondary: AI/Agent Developers
- Have agent expertise, want Apple distribution
- Building cross-platform agents, want Apple-native layer
- Interested in A2A interoperability

### Tertiary: Apple (Acquisition Target)
- Demonstrates platform vision
- Fills gap in Apple's agent story
- Ready-to-integrate architecture

## Competitive Landscape

| Solution | Strengths | Gaps |
|----------|-----------|------|
| **LangChain** | Rich ecosystem, many integrations | Python, not Apple-native |
| **Claude SDK** | Clean design, production-tested | TypeScript, not Apple-native |
| **AutoGPT/CrewAI** | Autonomous agents | Complex, not mobile-friendly |
| **Apple Intelligence** | Native, private | Not extensible, no agent framework |

**AgentKit's Position**: The missing native agent layer for Apple developers.

## Key Differentiators

1. **Swift-Native**: Not a wrapper — built from ground up in Swift
2. **iCloud-First**: File-based storage that syncs automatically
3. **Interoperable**: A2A protocol for working with any agent
4. **Privacy-Respecting**: On-device + PCC, no data leaving Apple ecosystem
5. **Developer-Friendly**: Macros, SwiftUI components, AppIntents integration
6. **Shortcuts Integration**: Expose agents as Shortcuts actions — users can chain agents into workflows, trigger via Siri, or automate with automations

## Messaging Framework

### For Developers
"Build AI agents with the tools you already know — Swift, SwiftUI, and Xcode."

### For Users (of apps built with AgentKit)
"AI that works across all your Apple devices, respects your privacy, and gets things done."

### For Apple
"The agent layer Apple needs — native, private, interoperable, and ready for acquisition."

## Proof Points (To Build)

- [ ] Demo app: Research Agent
- [ ] Demo app: Trip Planner
- [ ] Performance benchmarks vs. web-based agents
- [ ] Privacy architecture documentation
- [ ] A2A interop demo with Claude/Codex
