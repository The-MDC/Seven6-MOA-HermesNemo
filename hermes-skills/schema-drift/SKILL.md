---
name: "Schema Drift Detection"
description: "Detects and reports configuration and schema drift in AI agent workflows, inspired by suavir600/schema-drift-checker and jameskomo/config-drift-checker repos."
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: ['cloud', 'local']
tags: ['schema-drift', 'config-drift', 'infrastructure-drift']
---

hermes: {tags: ["schema-drift", "config-drift", "infrastructure-drift"], source: seven6-port, related_skills: ["config-drift"]}
# Schema Drift Detection Skill

## Overview
Detects configuration and schema drift in AI agent workflows.

## Features
- Config drift detection (from config-drift-checker)
- Schema validation and drift reporting
- IaC drift (terraform, python3, terragrunt)
- Integration with Seven6 config management

## Usage
```python
from hermes import SchemaDriftDetector
detector = SchemaDriftDetector()
report = detector.detect_drift(current_config, baseline_config)
```