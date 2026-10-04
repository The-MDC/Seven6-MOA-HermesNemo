---
name: code-review
description: "code-review-graph **Local-first code intelligence graph for MCP and CLI**"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [code-review, tree-sitter, graph]
    category: general
    related_skills: []
    source: seven6-port
---

# code-review-graph
**Local-first code intelligence graph for MCP and CLI**

A Hermes skill that integrates with `code-review-graph` to build a persistent structural map of your codebase using Tree-sitter, enabling AI coding tools to read only the relevant slices during reviews.

**Characteristics:**
- Builds a persistent, structural graph of the codebase
- Provides incremental context reductions for reviews
- Generates MCP/CLI instructions so AI assistants read only what matters
- Supports platform-specific configuration (codex, cursor, claude-code, gemini-cli, etc.)

**Parameters:**
- `--platform <platform>` — configure only a specific platform (codex, cursor, claude-code, gemini-cli, antigravity, windsurf, zed, continue, opencode, qwen)
- `install` — auto-detects and configures all supported platforms
- `build` — parse your codebase

**Surfaces:** hermes

**Example Usage:**
```bash
code-review-graph install
code-review-graph build
code-review-graph install --platform claude-code
```

**Dependencies:**
- Node.js >= 22 (for autoskills integration)
- Tree-sitter parser for target languages
- MCP configuration for target AI assistant

**Tags:** code-review, graph, mcp, tree-sitter, incremental, context-reduction