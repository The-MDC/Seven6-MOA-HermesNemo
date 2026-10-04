---
name: ai-gateway
description: "omniroute-ai-gateway **Free AI gateway with 350+ providers, 150+ free tiers, and 1.62B free tokens/month**"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [gateway, routing, providers]
    category: general
    related_skills: []
    source: seven6-port
---

# omniroute-ai-gateway
**Free AI gateway with 350+ providers, 150+ free tiers, and 1.62B free tokens/month**

A Hermes skill that integrates with the OmniRoute AI gateway, providing unified access to 350+ AI providers with 150+ free tiers and approximately 1.62B free tokens per month. Supports intelligent routing, token compression, and monitoring across multiple LLM providers.

**Key Features:**
- 358 AI providers · 150+ free tiers · ~1.62B free tokens/month
- 19 routing strategies for optimal model selection
- Circuit breakers, TLS stealth, MCP 110 tools support
- A2A, memory, guardrails, and 39,000+ static test declarations
- Works with Claude Code, Codex, Cursor, OpenCode, and other CLI tools

**Routing Strategies:**
- Session-dedup, CCR, Lite compression engines
- Aggressive/Ultra/RTK/Stacked compression pipelines
- Free tiers discovery and optimization
- Multi-model combo engine with 16-factor scoring

**Provider Integration:**
- Claude (Anthropic), GPT (OpenAI), Gemini (Google), Kimi, GLM, DeepSeek, MiniMax
- 150+ free tier entries with automatic fallback
- Token savings of 15–95% automatically

**Dependencies:**
- Node.js >= 22 (for autoskills)
- API keys for selected providers (optional — many work with free tiers)
- MCP configuration for Hermes integration

**Surfaces:** hermes

**Tags:** ai-gateway, omniroute, llm-providers, routing, token-optimization, mcp, a2a