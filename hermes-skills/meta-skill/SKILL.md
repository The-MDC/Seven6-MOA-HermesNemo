---
name: meta-skill
description: "task-observer-meta-skill **The meta-skill that builds and improves all your skills, including itself**"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [meta, skill-learning, observation]
    category: general
    related_skills: []
    source: seven6-port
---

# task-observer-meta-skill
**The meta-skill that builds and improves all your skills, including itself**

A Hermes skill implementing the Augmented Expertise methodology from rebelytics/one-skill-to-rule-them-all. This meta-skill watches work sessions (autonomous or human-led), captures patterns, corrections and judgement calls, and turns them into skill improvements and new skill candidates for review.

**Core Functions:**

1. **Identifies new skills for you** — spots repeating patterns in your work and flags them as skill candidates, then helps you build them

2. **Improves your existing skills** — notices corrections you make, preferences you express, and gaps in your current skills, then suggests specific updates

3. **Self-improving** — runs during every session and observes all active skills, including itself, capturing improvements to its own methodology

**Observation Capabilities:**
- Logs patterns across skill usage
- Captures corrections and preference expressions
- Identifies gaps in current skill coverage
- Generates skill improvement candidates
- Tracks decision rationale and context
- Supports skill versioning and evolution

**Session Integration:**
- Runs alongside normal work without disruption
- Observes all active skills in the Hermes environment
- Logs to persistent mem9 memory for cross-session recall
- Generates review-ready improvement suggestions
- Supports user-directed skill refinement

**Dependencies:**
- mem9 for persistent observation storage
- Hermes skill management API
- Self-reflection capability

**Surfaces:** hermes

**Tags:** meta-skill, skill-improvement, augmented-expertise, observation, skill-evolution