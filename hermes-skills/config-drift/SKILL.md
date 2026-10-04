---
name: config-drift
description: "config-drift-checker **Configuration drift detection for Hermes-MOA and codebases**"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [config, drift, audit]
    category: general
    related_skills: []
    source: seven6-port
---

# config-drift-checker
**Configuration drift detection for Hermes-MOA and codebases**

A Hermes skill that detects configuration drift in Hermes-MOA builds, code repositories, and infrastructure. Identifies mismatched versions, flagged configurations, and suggests remediation to maintain consistency across the build environment.

**Core Capabilities:**
- **Detect drift** — Compare current configuration against expected/baseline state
- **Flag mismatches** — Highlight version mismatches, missing configurations, and security settings deviations
- **Remediation guidance** — Suggest specific fixes for detected drift
- **Multi-repo support** — Check drift across multiple repositories simultaneously
- **Hermes-MOA specific** — Verify config.yaml, capabilities.yaml, routing configurations consistency

**Supported Checks:**
- Hermes-MOA config.yaml drift against baseline
- capabilities.yaml skill declaration consistency
- MCP server configuration drift
- Skill manifest hash verification
- Environment variable consistency
- Provider routing configuration drift

**Output Format:**
- Drift reports with severity levels
- Before/after configuration snapshots
- Automated fix suggestions
- Priority-ordered remediation roadmap

**Dependencies:**
- Access to Hermes-MOA config files
- Git repository access for baseline comparison
- JSON/YAML parsing capabilities

**Surfaces:** hermes

**Tags:** drift-detection, configuration, validation, compliance, remediation