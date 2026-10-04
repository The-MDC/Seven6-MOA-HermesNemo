---
name: nvidia-agent-doctor
description: "nvidia-agent-doctor **Diagnose, secure, and validate NVIDIA AI environments and agent configurations**"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [nvidia, diagnostics, security]
    category: general
    related_skills: []
    source: seven6-port
---

# nvidia-agent-doctor
**Diagnose, secure, and validate NVIDIA AI environments and agent configurations**

A Hermes skill that implements the NVIDIA Agent Doctor CLI functionality, providing comprehensive diagnostics of NVIDIA AI environments, reviewing agent/MCP/skill configuration risks, and benchmarking compatibility.

**Core Capabilities:**
- **Diagnose** — Check what the machine can actually run, identify misconfigurations, and flag what needs human security review
- **Secure** — Review agent, MCP, and skill configuration risk profiles
- **Validate** — Benchmark compatibility and performance of the AI environment
- **Hardware/Software checks** — GPU, CUDA, driver, Docker, container status
- **MCP and skill configuration inspection** — Review skill files, memory configs, routing setups
- **Risk assessment** — Identify security vulnerabilities and configuration drift

**Supported Checks:**
- Hardware: GPU status, CUDA version, driver compatibility
- Software: Python version, Node.js version, Docker availability
- MCP: Provider configurations, model routing, gateway setups
- Skills: Skill file validity, manifest consistency, hash verification
- Environment: API keys, authentication configurations, network accessibility

**Output Format:**
- Structured diagnostic reports
- Risk scores and recommendations
- Compatibility matrices
- Remediation guidance

**Dependencies:**
- Python 3.11+
- Access to NVIDIA hardware or simulation environment
- MCP server configurations
- Skill manifest files

**Surfaces:** hermes

**Tags:** diagnostics, security, validation, nvidia, mcp, skill-audit, compatibility