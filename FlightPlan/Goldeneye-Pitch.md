# Project Goldeneye - Pitch Deck Outline
## AgentKit + Agents

---

## Slide 1: Title

**Agents**
*Powered by AgentKit*

*The future of personal computing isn't apps you use—it's agents you train.*

(Codename: Goldeneye)

---

## Slide 2: The Problem

**Today's AI assistants are broken**

- **Stateless**: Every conversation starts from zero
- **Siloed**: Can't access your real data (calendar, email, files)
- **Untrusted**: Either full access or no access—no middle ground
- **Disconnected**: Don't learn, don't remember, don't grow

*Result: AI that feels helpful in demos but frustrating in practice*

---

## Slide 3: The Paradigm Shift

**Apps are capabilities. Agents act with those capabilities.**

| Then | Now |
|------|-----|
| Apps you install | Agents you train |
| Permissions you grant | Trust you build |
| Data stays in apps | Context flows across agents |
| UI is primary | UI is oversight |

*Apps become capability libraries. Agents orchestrate across them.*

---

## Slide 4: Introducing Agents

**A platform for persistent, trustworthy agents**

Three core principles:

1. **Memory**: Agents remember and learn from every interaction
2. **Integration**: Native access to Apple ecosystem (Calendar, Mail, Notes, etc.)
3. **Trust**: Agents earn autonomy like employees, not apps requesting permissions

---

## Slide 5: The Trust Model

**Agents earn autonomy over time**

```
Level 0: Observer      → Read-only, all outputs are suggestions
Level 1: Assistant     → Can create drafts, needs approval
Level 2: Contributor   → Can modify (staged), batch approval
Level 3: Trusted       → Direct write, HITL for high-risk only
Level 4: Autonomous    → Full autonomy within boundaries
```

*Like onboarding a new employee. Trust is earned, not granted.*

---

## Slide 6: Architecture Overview

```
┌─────────────────────────────────────────────┐
│              User Interface                  │
│         (Chat, Artifacts, Approvals)         │
└─────────────────────────────────────────────┘
                     │
┌─────────────────────────────────────────────┐
│             Agents Runtime                   │
│     (Agent execution, context assembly)      │
└─────────────────────────────────────────────┘
                     │
┌─────────────────────────────────────────────┐
│                AgentKit                      │
│    (LLM providers, tools, A2A protocol)     │
└─────────────────────────────────────────────┘
                     │
┌─────────────────────────────────────────────┐
│              MCP Servers                     │
│   Calendar │ Mail │ Notes │ Files │ Apps    │
└─────────────────────────────────────────────┘
```

---

## Slide 7: Native Integration

**Every Apple framework becomes an agent capability**

| Framework | Agent Can... |
|-----------|--------------|
| Calendar | Read events, check availability, create meetings |
| Reminders | Manage tasks, create lists, set due dates |
| Notes | Search notes, create documents, organize folders |
| Mail | Read inbox, draft replies, send (with approval) |
| Files | Access iCloud Drive, organize documents |
| Any App | Use any AppIntent-enabled capability |

*No APIs to configure. No OAuth. Just native Apple frameworks.*

---

## Slide 8: Workspaces & Context

**Context flows naturally**

```
~/iCloud/Spaces/
├── Personal/           ← Personal context
├── Work - Project X/   ← Project-specific agents & files
└── Family/             ← Shared family workspace
```

- Agents understand workspace context automatically
- Permissions are scoped to workspaces
- Full version history (git-backed) for all changes
- Non-destructive: changes stage before applying

---

## Slide 9: The Privacy Guarantee

**Your data can be used by agents, but never seen by anyone else.**

```
┌─────────────────────────────────────────────────────────────┐
│                     YOUR DEVICE                              │
│  MCP Servers access Calendar, Mail, Notes directly          │
│  Context assembled locally                                   │
└─────────────────────────────┬───────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
    ┌──────────┐       ┌──────────┐       ┌──────────┐
    │  Local   │       │   PCC    │       │ Private  │
    │  (MLX)   │       │ (Apple)  │       │  Cloud   │
    │          │       │          │       │          │
    │  100%    │       │  100%    │       │   E2E    │
    │ private  │       │ private  │       │encrypted │
    └──────────┘       └──────────┘       └──────────┘
```

**Privacy tiers**:
- **Maximum**: Local only - never leaves device
- **Private**: Local or PCC - Apple's hardware-backed guarantees
- **Extended**: Verified providers with E2E encryption

*Unlike ChatGPT/Claude where your data becomes training data, PCC ensures your context is USED but never SEEN.*

---

## Slide 10: The Agent Store

**The next App Store**

Today's apps → Tomorrow's agents

- Developers create agents with defined capabilities
- Users train agents to their preferences
- Trust is portable (your trained agent, your trust levels)
- Agents compose (specialist agents for specific domains)

*A new platform for AI-native applications*

---

## Slide 11: User Experience

**Artifact-driven chat**

- Conversations produce *artifacts* (documents, events, tasks)
- Artifacts can be edited, saved, or approved inline
- Approval flow is transparent and contextual
- Agent training is visible (learnings, trust metrics)

[Wireframe/mockup would go here]

---

## Slide 12: What We've Built

**AgentKit foundation is complete**

✅ LLM provider abstraction (local, cloud, CLI agents)
✅ Tool system with approval levels
✅ A2A protocol for agent communication
✅ Human-in-the-loop approval system
✅ Native MLX inference
✅ macOS Console app (prototype)

*Foundation is solid. Ready to build Agents on top.*

---

## Slide 13: Roadmap

**Phase 1** (6 weeks): Agent identity, memory, trust, workspaces

**Phase 2** (6 weeks): Native MCP servers (Calendar, Notes, Files)

**Phase 3** (8 weeks): Agents macOS app with full UX

**Phase 4** (6 weeks): Mail, Messages, compute routing, iOS

**Phase 5** (ongoing): Agent Store, distribution

---

## Slide 14: Why Now?

1. **Apple Intelligence** establishes agent patterns for users
2. **AppIntents** makes every app agent-accessible
3. **PCC** enables secure cloud compute
4. **LLM capabilities** have reached practical utility
5. **User expectations** are shifting toward AI assistance

*The platform pieces exist. Agents unifies them.*

---

## Slide 15: The Ask

**What we need**

- Engineering team (Swift/macOS expertise)
- Design resources (UX for trust, approvals, artifacts)
- PM to manage roadmap and stakeholder alignment
- Executive sponsorship for framework access

**What we deliver**

- The foundation for agent-native computing on Apple platforms
- A new category of applications
- User relationships built on trust, not permissions

---

## Slide 16: Vision

> "In five years, you won't install apps to do things.
> You'll tell your agent what you need, and it will
> orchestrate the capabilities to make it happen."

**Agents is how we get there.**

---

## Appendix Slides

### A: Technical Deep Dive
- Context encryption for remote compute
- Trust algorithm details
- MCP server architecture

### B: Competitive Landscape
- vs. ChatGPT (stateless, no native integration)
- vs. Apple Intelligence (limited to system features)
- vs. Notion AI, etc. (single-app, no ecosystem)

### C: Business Model Considerations
- Agent Store economics
- Enterprise licensing
- Developer program

---

*Pitch Version: 1.0*
*Prepared: January 2025*
