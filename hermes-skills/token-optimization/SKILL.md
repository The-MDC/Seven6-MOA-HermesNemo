---
name: "Token Optimization"
description: "Address retokenization drift by returning token IDs via OpenAI Compatible API, from Agent Lightning's 'No More Retokenization Drift: Returning Token IDs via the OpenAI Compatible API Matters in Agent RL vLLM' blog post."
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: ['cloud', 'local', 'nim', 'hf']
tags: ['token-optimization', 'ret-tokenization-drift', 'agent-lightning']
---

hermes: {tags: ["token-optimization", "ret-tokenization-drift", "agent-lightning"], source: seven6-port, related_skills: ["prompt-optimization", "rl-optimization"]}
# Token Optimization Skill

## Overview
Solves retokenization drift by returning token IDs via OpenAI Compatible API.

## Features
- Token ID return via OpenAI Compatible API
- Retokenization drift elimination
- Compatible with vLLM and any LLM backend
- Integration with Agent Lightning

## Usage
```python
from hermes import TokenOptimizer
optimizer = TokenOptimizer()
token_ids = optimizer.optimize("prompt", model)
```