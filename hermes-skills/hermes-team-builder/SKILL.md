---
name: hermes-team-builder
description: "hermes-team-builder **Production-derived agent-consumable guide for building AI teams with Hermes**"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [team, agents, orchestration]
    category: general
    related_skills: []
    source: seven6-port
---

# hermes-team-builder
**Production-derived agent-consumable guide for building AI teams with Hermes**

A Hermes skill that implements the complete team-building framework from the smfworks/hermes-ai-team repository, enabling a single Hermes Agent install to be turned into a real team of AI colleagues.

**Key Capabilities:**
- **Named agents** (Bots/profiles) with individual SOUL, memory, skills, model, and lane
- **Second brain / vault** — research and knowledge accumulation that compounds over time
- **Nightly research** ("the dream function") — agents scanning their domains while you sleep
- **Self-improvement engine** — skills agents write from experience, curated automatically
- **Shared kanban board** for durable task coordination
- **Hermes Desktop Bots + group chats** — team pods coordinating in shared rooms
- **Chief of staff** agent running the coordination layer
- **Daily check-ins, weekly alignment loops, and one-on-ones**

**Phase Structure (as described in smfworks/hermes-ai-team):**
1. **Minimal Viable Team** — meaningful team of one in under 2 hours, with verification at every step
2. **Team growth phases** — progressive addition of agents, capabilities, and coordination
3. **Full team implementation** — all components including bots, rituals, and group chat pods

**Technical Components:**
- **SOUL-based agent identity** — each agent has its own SOUL for identity
- **Persistent memory via mem9 vault** — research and knowledge persist across sessions
- **Agent-consumable phase-by-phase guide** — written so Hermes profile can implement phases
- **Desktop Bot mode** — enables Desktop Bots + group chat pods
- **Rituals system** — daily check-ins, weekly alignments, one-on-ones

**Dependencies:**
- Hermes Agent with profile system
- Desktop Bot Mode (as of August 2026)
- mem9 for persistent memory
- mcp for tool integration
- SOUL framework for agent identity

**Surfaces:** hermes

**Tags:** ai-team, orchestration, soul, memory, vault, kanban, bot, chief-of-staff, rituals, group-chats