---
name: "Prompt Optimization"
description: "Automatic prompt tuning and optimization using algorithms from Agent Lightning. Zero-code change prompt improvement for any agent framework."
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: ['cloud', 'local', 'nim', 'hf']
tags: ['prompt-optimization', 'auto-prompt-optimization', 'trajectory-aggregation']
---

hermes: {tags: ["prompt-optimization", "auto-prompt-optimization", "trajectory-aggregation"], source: seven6-port, related_skills: ["rl-optimization"]}
# Prompt Optimization Skill

## Overview
Automatic prompt tuning and optimization.

## Features
- Auto-prompt optimization (Part 2 from Agent Lightning blog)
- Trajectory level aggregation
- Zero-code change integration
- Multi-framework support

## Usage
```python
from hermes import PromptOptimizer
optimizer = PromptOptimizer()
optimized_prompt = optimizer.optimize("original prompt")
```