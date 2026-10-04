---
name: nemotron-lightning-a3b
description: "NVIDIA Nemotron 3.5 Lightning A3B — 30B Mixture-of-Experts (3B active) with hybrid Mamba-2/MoE architecture, NIM-deployed base_generator for the Seven6-Hermes-MOA tier1 panel"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [moa, base-generator, coding, math-reasoning, instruct, long-chain-of-thought, nim-deployed]
    category: moa-tier1
    related_skills: [nemotron-3-5-base-8b-instruct, review-vision-quantum-model, jevify-q6k-gguf-multimodal-coding, codex-hermes-bridge, mcp-builder, six-perspectives, enhanced-mem9]
    source: seven6-port
---

# Nemotron-Lightning-A3B — MOA1 Base Generator

## Description
Nemotron-Lightning-A3B is a **30-billion-parameter Mixture-of-Experts (MoE) model with only 3 billion active parameters per forward pass**, built on a hybrid **Mamba-2 + MoE** architecture. It is the designated **base_generator** in the Seven6-Hermes-MOA tier1 panel, deployed via NVIDIA NIM (`build.nvidia.com`).

It succeeds the retired Darwin-35B-A3B-Mythos with improved agentic capabilities, stronger instruction-following, and tighter integration with the Nemotron-3.5 family.

## Role in MOA1
- **Designation**: `base_generator`
- **Position in panel**: 2 of 7 (after Darwin-180B-RSI primary_moe)
- **Quantization**: Q4_K_M
- **Deployment**: NVIDIA NIM (`https://integrate.api.nvidia.com/v1`)

## Key Strengths
- **Coding** — production-grade code generation, refactoring, debugging across major languages
- **Mathematical reasoning** — competition-level and applied math, proof verification
- **Scientific analysis** — hypothesis formation, experimental design reasoning, literature synthesis
- **Hybrid architecture** — Mamba-2 state-space layers give long-context efficiency; MoE experts give per-domain depth
- **Agentic readiness** — native tool-calling and multi-step planning

## Long Chain-of-Thought Operation
When enabled, the model emits a step-by-step reasoning chain before the final answer. The chain is:
- Logged in the session transcript under `thought_chain:`
- Validated against the six-perspective framework
- Fed back to the memory pipeline (`enhanced-mem9` + `memory-pipeline`) as a structured reasoning trace
- Used as audit evidence in TrueForge approval-gated flows

Bounded by `max_tool_calls: 50` to prevent runaway loops.

## Six-Perspectives Review
Outputs from this model are reviewed through the six-perspective framework (Darwin-180B-RSI rigor, Nemotron-Lightning-A3B self-consistency, Nemotron-3.5-8B-Instruct fidelity, Nemotron-3.5-Content-Safety policy compliance, Review-Vision-Quantum-Model multimodal/quantum check, jevify-q6k dual-expert lane coherence). Supermajority (5/6) consensus required to proceed.

## TrueForge Patterns
All irreversible tool calls routed through this model are intercepted by the TrueForge (E.D.I.T.H.) harness:
**dry-run → backup → approval → apply → rollback**, with an audit log entry per invocation.

## Memory Pipeline Integration
Cross-session persistence via `enhanced-mem9` and `memory-pipeline`. Memory keys derive as `moa:nemotron-lightning-a3b:<step>` and are retrievable via cosine-similarity embedding lookup (`knowledge_retrieval` skill).

## Configuration
```yaml
# In ~/.hermes/.env (never committed):
NVIDIA_API_KEY=nvapi-...

# Provider routing:
# /model custom:nvidia-nim:nemotron-lightning-a3b
```

## Usage
- Primary text/code generator for the MOA1 panel when Darwin-180B-RSI is not required
- Default `base_generator` for tasks under moderate complexity
- Pairs with `jevify-q6k-gguf-multimodal-coding` (support_expert_1) for parallel multimodal/coding lanes
