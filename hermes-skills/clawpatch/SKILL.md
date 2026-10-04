---
name: clawpatch
description: "clawpatch **Comprehensive code-review skill for Claude Code**"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [code-review, react, typescript]
    category: general
    related_skills: []
    source: seven6-port
---

# clawpatch
**Comprehensive code-review skill for Claude Code**

A Hermes skill implementing the openclaw/clawpatch code-review functionality, covering React 19, Vue 3, Rust, TypeScript, TanStack Query v5, and more. Provides comprehensive code analysis, issue detection, and remediation suggestions.

**Language Support:**
- React 19 — JSX analysis, hooks validation, component patterns
- Vue 3 — Composition API, reactivity system, component patterns
- Rust — Ownership checking, borrow checker analysis, idiomatic patterns
- TypeScript — Type safety, generic inference, pattern validation
- TanStack Query v5 — Data fetching, caching, mutation patterns

**Core Features:**
- **Multi-language analysis** — Simultaneous support for multiple language ecosystems
- **Issue detection** — Identify bugs, anti-patterns, and style violations
- **Best practice validation** — Framework-specific best practices and patterns
- **Code improvement suggestions** — Targeted refactoring and optimization recommendations

**Integration:**
- Designed for Claude Code environment
- Works alongside existing code-review-graph integration
- Provides structured review outputs compatible with Hermes skill format

**Dependencies:**
- Language-specific parsers/analyzers
- Claude Code environment
- Project codebase access

**Surfaces:** hermes

**Tags:** code-review, claude-code, multi-language, linting, quality-assurance