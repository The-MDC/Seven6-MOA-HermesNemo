---
name: jevify-q6k-gguf-second-support
description: """"
version: 1.0.0
author: "unknown"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [automatically-portled]
    category: general
    related_skills: []
---

# jevify-Q6_K_GGUF (Second Support Expert) Skill

## Description
6-bit quantized model (~16 GB VRAM) serving as the second support expert in MOA1 tier1 mixture-of-experts architecture, providing parallel multimodal/coding lane expert. Designed to operate in parallel with the first support expert, creating a dual-expert support system for concurrent multimodal and coding tasks.

## Why This Skill is Valuable
- Provides dual-expert support system parallelism in MOA1 architecture
- Second 6-bit quantized expert (~16 GB VRAM) for concurrent processing
- Creates parallel multimodal/coding lane expert alongside first support expert
- Enables true two-expert support parallelism for MOA1 architecture
- Complements the first jevify-Q6_K_GGUF expert for balanced multimodal/coding workload distribution

## Key Features
- 6-bit Q6_K quantization (identical to first support expert)
- ~16 GB VRAM requirement (matches first expert)
- Second support expert in tier1 MoE architecture
- Parallel multimodal/coding lane expert
- Workload distribution across dual support experts
- MOA1 tier1 mixture-of-experts architecture compatible

## Usage
This skill provides access to the second jevify-Q6_K_GGUF expert's capabilities that can be used to:
- Operate in parallel with the first support expert (jevify-q6k-gguf-multimodal-coding)
- Handle additional multimodal/coding workloads concurrently
- Distribute tasks across dual support experts for balanced processing
- Provide redundant support capability if one expert is busy
- Enable true two-expert parallelism for MOA1 architecture workloads

## Integration
Activates automatically via Hermes' pre_llm_call hook when additional multimodal/coding support is needed beyond the first expert. Can also be invoked directly via `hermes jevify-q6k-second-support <prompt>`.

## Configuration
Add to ~/.hermes/config.yaml:
```yaml
plugins:
  jevify-q6k-gguf-second-support: true
```metadata:
  hermes:
    source: seven6-port
        tags: [automatically-portled]
    category: general
    related_skills: []
---

# jevify-Q6_K_GGUF (Second Support Expert) Skill

## Description
6-bit quantized model (~16 GB VRAM) serving as the second support expert in MOA1 tier1 mixture-of-experts architecture, providing parallel multimodal/coding lane expert. Designed to operate in parallel with the first support expert, creating a dual-expert support system for concurrent multimodal and coding tasks.

## Why This Skill is Valuable
- Provides dual-expert support system parallelism in MOA1 architecture
- Second 6-bit quantized expert (~16 GB VRAM) for concurrent processing
- Creates parallel multimodal/coding lane expert alongside first support expert
- Enables true two-expert support parallelism for MOA1 architecture
- Complements the first jevify-Q6_K_GGUF expert for balanced multimodal/coding workload distribution

## Key Features
- 6-bit Q6_K quantization (identical to first support expert)
- ~16 GB VRAM requirement (matches first expert)
- Second support expert in tier1 MoE architecture
- Parallel multimodal/coding lane expert
- Workload distribution across dual support experts
- MOA1 tier1 mixture-of-experts architecture compatible

## Usage
This skill provides access to the second jevify-Q6_K_GGUF expert's capabilities that can be used to:
- Operate in parallel with the first support expert (jevify-q6k-gguf-multimodal-coding)
- Handle additional multimodal/coding workloads concurrently
- Distribute tasks across dual support experts for balanced processing
- Provide redundant support capability if one expert is busy
- Enable true two-expert parallelism for MOA1 architecture workloads

## Integration
Activates automatically via Hermes' pre_llm_call hook when additional multimodal/coding support is needed beyond the first expert. Can also be invoked directly via `hermes jevify-q6k-second-support <prompt>`.

## Configuration
Add to ~/.hermes/config.yaml:
```yaml
plugins:
  jevify-q6k-gguf-second-support: true
```## Long Chain-of-Thought Operation
When enabled, the model is prompted to emit a step-by-step reasoning chain before the final answer. This chain is:

- **Explicitly logged** in the session transcript under `thought_chain:` 
- **Validated** against the six-perspective framework above
- **Feeded back** to the memory pipeline (`enhanced-mem9` + `memory-pipeline`) as a structured reasoning trace
- **Used for audit** in TrueForge approval-gated flows (the chain becomes part of the backup evidence)

**Invocation**: Add `pre_llm_call: true` to the skill's config, or prefix the user prompt with `Let's reason step by step:` to trigger the chain. The chain length is bounded by `max_tool_calls: 50` to prevent runaway loops.

The chain output format is:
```
thought_chain:
  - Step 1: <description>
  - Step 2: <description>
  - ...
Final answer: <the synthesized response>
```

## High-Value Memory Integration
Integration with the `enhanced-mem9` and `memory-pipeline` skills ensures that:

- Each reasoning step and its outcome are stored persistently across sessions
- Memory keys are auto-derived from the skill name + step index: `moa:<skill>:<step>`
- Retrieval uses cosine-similarity on the stored reasoning embeddings (via the `knowledge_retrieval` skill)
- Cross-session context: if the same MOA1 task is resumed on a different machine, the memory pipeline rehydrates the prior chain, allowing the aggregator to reference prior reasoning or flag drift

**Auto-tags** for memory-tagged outputs: `moa-reasoning, six-perspective, trueforge-approved`.
## TrueForge Approval-Gated Patterns
**Dry-run first**: `hermes skill invoke --dry-run <skill>` — generates a preview of what the tool will do, including a backup hash of the target state.

**Backup**: Before any irreversible action, a snapshot is auto-generated under `~/.hermes/backups/` keyed by timestamp + skill + task-id. This snapshot can be restored with `hermes backup restore <hash>`.

**Approval-gated**: The harness intercepts the execution call and surfaces a confirmation prompt containing:
- Action summary + risk score
- Backup hash reference
- Exact command that will run
- `Confirm / Abort` buttons (UI or CLI `--confirm` flag)

**Apply**: If confirmed, the tool runs under the harness; on completion the audit log records: output hash, duration, any warnings, and the backup hash is moved to `confirmed/` folder.

**Rollback**: If the audit flags anomalies, `hermes harness rollback --hash <hash>` restores the pre-action backup. The operator may also manually `hermes backup restore <hash>` at any time.

All TrueForge-gated tools must declare `metadata.herbes.approval_gate: true` to be intercepted.
## Six-Perspectives Stress-Test Integration
The six-perspective framework (CodeLlama, Qwythos, Darwin-180B, Nemotron-3.5-8B, Nemotron-3.5-Content-Safety, jevify-q6k) applies the following lenses to MOA1 outputs:

1. **Darwin-180B-RSI** — Mathematical rigor, AIME/HMMT/GPQA/MMLU-Pro/MMMU-Pro correctness, vision-language consistency
2. **Nemotron-Lightning-A3B** — Coding competence, Mamba-2/MoE hybrid reasoning, mathematical proof verification
3. **Nemotron-3.5-Base-8B-Instruct** — General instruction fidelity, agent orchestration sanity checks
4. **Nemotron-3.5-Content-Safety** — 12-language policy compliance, prompt/response classification, guardrail adherence
5. **Review-Vision-Quantum-Model** — Multimodal/coding review, quantum-inspired reasoning check, output refinement
6. **jevify-q6k-gguf** (both experts) — 6-bit quantized lane integrity, parallel multimodal/coding coherence, dual-expert MoE consistency

If any perspective flags a deviation, the aggregator logs the dissent and proceeds only with a supermajority consensus (5/6).

