---
name: nvidia-enhanced
description: "nvidia-enhanced **Extended NVIDIA environment diagnostics with advanced optimization recommendations**"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [nvidia, gpu, optimization]
    category: general
    related_skills: []
    source: seven6-port
---

# nvidia-enhanced
**Extended NVIDIA environment diagnostics with advanced optimization recommendations**

A Hermes skill that builds upon the core NVIDIA Agent Doctor functionality with advanced GPU optimization, driver management, and performance tuning recommendations for Hermes-MOA AI workflows.

**Extended Capabilities:**
- **Advanced GPU optimization** — Recommended GPU topology, memory allocation, and multi-GPU configuration
- **Driver version management** — compatibility matrices, automatic updates, and rollback recommendations
- **Performance tuning** — CUDA optimization flags, kernel parameters, and runtime configuration
- **Resource forecasting** — Predictive analytics for GPU memory, compute requirements based on workload
- **Hermes-MOA specific profiling** — Workload characterization for LLM inference, training, and inference scaling

**Supported Checks:**
- GPU health with advanced metrics (temperature, power draw, ECC errors)
- CUDA version compatibility and optimization opportunities
- Multi-GPU scaling efficiency
- Memory bandwidth utilization
- Inference/training workload profiling
- Recommended configuration for specific Hermes-MOA use cases

**Output Format:**
- Detailed GPU topology and status reports
- Optimization recommendation lists with priority scoring
- Performance baseline comparisons
- Hermes-MOA workload-specific tuning guides

**Dependencies:**
- NVIDIA SMI or DCGM for GPU monitoring
- CUDA toolkit for version and capability checks
- Hermes-MOA workload profile data

**Surfaces:** hermes

**Tags:** nvidia-optimization, gpu, performance-tuning, hardware-profiling, hw-monitoring