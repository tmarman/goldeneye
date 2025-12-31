# F006: Documentation Site & Landing Page

**Status**: Backlog
**Mission**: M001 Foundation (Developer Relations)
**Priority**: P1

## Overview

Create a markdown-driven documentation site that serves as both marketing landing page and technical docs. Should communicate what AgentKit is, why it matters, and how to use it.

## Goals

1. **Explain the vision** — What is AgentKit and why build on it?
2. **Showcase capabilities** — What can developers build?
3. **Guide adoption** — Getting started, tutorials, API reference
4. **Build credibility** — Architecture docs, research foundations

## Site Structure

```
/                           # Landing page (hero, value prop, CTA)
├── /docs/
│   ├── getting-started/    # Quick start guide
│   ├── concepts/           # Core concepts (agents, tools, context)
│   ├── guides/             # How-to guides
│   ├── api/                # API reference
│   └── architecture/       # Deep dives
├── /examples/              # Code examples gallery
├── /blog/                  # Updates, tutorials, case studies
└── /community/             # Discord, GitHub, contributing
```

## Landing Page Sections

### Hero
- Tagline: "Agent infrastructure for the Apple ecosystem"
- One-liner value prop
- Primary CTA: Get Started / View on GitHub

### Why AgentKit
- Model-agnostic (local + cloud)
- Agent-agnostic (A2A interoperability)
- Apple-native (SwiftUI, iCloud, AppIntents)
- Privacy-first (on-device + PCC)

### What You Can Build
- Research assistants
- Trip planners
- Code agents
- Custom workflows

### How It Works
- Visual architecture diagram
- Code snippet showing simplicity
- Link to concepts docs

### Get Started
- Installation
- First agent in 5 minutes
- Links to tutorials

## Tech Stack Options

| Option | Pros | Cons |
|--------|------|------|
| **Docusaurus** | Full-featured, React-based, good search | JS ecosystem |
| **VitePress** | Fast, Vue-based, clean | Less extensible |
| **Astro** | Static, fast, flexible | Newer |
| **Swift-DocC** | Native Swift docs | Limited for marketing |
| **Publish (Swift)** | Swift ecosystem, John Sundell | Less features |

**Recommendation**: Docusaurus or Astro — need good landing page + docs combo.

## Content Sources

Migrate from FlightPlan:
- `Charts/Technical/architecture-overview.md` → Architecture docs
- `Charts/Technical/swift-patterns.md` → API patterns guide
- `Charts/Setup/getting-started.md` → Getting started

Generate:
- API reference from Swift DocC comments
- Example code from `/Examples` projects

## Deliverables

- [ ] Choose static site generator
- [ ] Design landing page layout
- [ ] Write landing page copy
- [ ] Migrate FlightPlan docs
- [ ] Set up build/deploy pipeline
- [ ] Custom domain setup

## Open Questions

1. Host where? (GitHub Pages? Vercel? Netlify?)
2. Custom domain? (agentkit.dev? agentkit.apple-community?)
3. Do we want a blog from day one?

## Dependencies

- Some core concepts finalized (F001, F003) for accurate docs
