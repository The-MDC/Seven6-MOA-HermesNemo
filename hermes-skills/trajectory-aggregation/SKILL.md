---
name: "Trajectory Aggregation"
description: "Trajectory level aggregation for faster agent training, from Agent Lightning's 'Adopting the Trajectory Level Aggregation for Faster Training' blog post."
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: ['cloud', 'local', 'nim']
tags: ['trajectory-aggregation', 'rl-training', 'agent-lightning']
---

hermes: {tags: ["trajectory-aggregation", "rl-training", "agent-lightning"], source: seven6-port, related_skills: ["rl-optimization", "prompt-optimization"]}
# Trajectory Aggregation Skill

## Overview
Trajectory level aggregation for faster agent training.

## Features
- Trajectory level aggregation algorithm
- Faster training convergence
- Compatible with any RL framework
- Integration with Agent Lightning

## Usage
```python
from hermes import TrajectoryAggregator
aggregator = TrajectoryAggregator()
trained_agent = aggregator.aggregate(trajectories)
```