---
name: memory-pipeline
description: "mem9-persistent-memory **Persistent memory for AI agents across sessions and machines**"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [memory, persistence, sessions]
    category: general
    related_skills: []
    source: seven6-port
---

# mem9-persistent-memory
**Persistent memory for AI agents across sessions and machines**

A Hermes skill that implements the mem9 persistent memory layer, providing:
- Persistent memory across sessions and machines — context survives restarts, laptop switches, and long-running projects
- Shared memory across agents and workflow platforms — OpenClaw, Hermes Agent, Claude Code, OpenCode, Codex, DeepSeek Harness, and Dify apps can recall the same facts
- Stateless integrations — runtime plugins stay thin because storage, search, ingest, and policy live in the server
- Hybrid recall and visual dashboard — semantic search, keyword search, and inspection workflows in one system

**Core Flow:**
1. **Store** — Persist memories against the mem9 server API
2. **Search** — Semantic or keyword search across stored memories
3. **Get** — Retrieve relevant memories for current context
4. **Update** — Modify existing memories with new information
5. **Delete** — Soft-delete memories when no longer needed

**Supported Platforms:**
- OpenClaw — memory plugin for server-backed shared memory
- Hermes Agent — memory provider plugin with setup and activation flow
- Claude Code — marketplace plugin with hooks and skills
- OpenCode — plugin SDK integration from opencode.json
- Codex — marketplace plugin with managed hooks and project overrides
- DeepSeek Harness — native DSH/Cordis bundle with recall tools
- Dify — tool plugin for Agent apps and Workflow apps

**API Endpoints (v1alpha2):**
- `POST /v1alpha2/mem9s/memories` — Unified write endpoint
- `GET /v1alpha2/mem9s/memories` — Preferred search endpoint
- `GET /v1alpha2/space-chains/{chainID}` — Space chain details
- `POST /v1alpha2/mem9s/memories/batch-delete` — Bulk soft-delete

**Dependencies:**
- mem9 server (self-hosted or TiDB Cloud)
- API key for mem9 service
- GraphClient or similar for search integration

**Surfaces:** hermes

**Tags:** memory, persistence, shared-memory, recall, mem9, agent-memory