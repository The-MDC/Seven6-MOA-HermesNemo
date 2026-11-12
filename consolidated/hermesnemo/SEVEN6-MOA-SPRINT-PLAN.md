# Seven6-MoA Sprint Tactical Plan — DeepSeek-V2 236B MoE (8-bit Q8) Advisor + RAG Layer

**Profile:** `seven6moa`
**Config:** `C:\Users\nicholasjmcleod\AppData\Local\hermes\profiles\seven6moa\config.yaml`
**Repo:** `C:\Users\nicholasjmcleod\Projects\Seven6-Hermes-MOA`
**Branch:** `feature/deepseek-v2-moa`
**Decisions confirmed:** R7 (7th advisor), Q8 GGUF local, local `./rag-corpus/` RAG corpus

---

## Overall Structure

| Phase | Sprints | Focus |
|-------|---------|-------|
| Phase 1 | Sprint 0–4 | Foundation, DeepSeek-V2 advisor wiring, RAG layer, audit & verify |
| Phase 2 | Sprint 5–6 | Hardening, production benchmarks, rollout to `main` |

**Invariants maintained throughout:**
- 6 original advisors + DeepSeek-V2 as R7 = 7 advisors total
- Aggregator remains `nvidia/nemotron-3.5-super-vl-120b-a12b` (unchanged)
- All advisors run `reasoning_effort: max`
- Parent/acting model unchanged
- No existing advisor is removed or replaced

---

## Phase 1 — Build, Audit & Verify

### Sprint 0 — Foundation & Pre-Flight (Days 1–2)

**Goal:** Validate every dependency before writing code. No config changes yet.

**Tasks:**
1. Verify NVIDIA NIM supports `DeepseekV2ForCausalLM` architecture
   - `bash scripts/nim-preflight.sh --list | grep -i deepseek` (if script exists)
   - Cross-reference NIM supported architectures table
2. Verify Q8 GGUF source availability on Hugging Face for DeepSeek-V2 236B
   - Search HF for `deepseek-v2-236b` Q8 GGUF repos (TheBloke, bartowski, unsloth, etc.)
   - Record exact repo ID, file size, quantization format
3. Verify `reasoning_effort: max` is confirmed on all six existing advisors
   - `hermes -p seven6moa moa list` → all R1–R6 show `[reasoning=max]`
4. Create feature branch `feature/deepseek-v2-moa` in the Seven6-Hermes-MOA repo
5. Write `Sprint0_preflight.md` with go/no-go per dependency

**Exit criteria:** All dependencies verified; user confirms readiness for Sprint 1.

---

### Sprint 1 — DeepSeek-V2 Q8 Advisor Integration (Days 3–5)

**Goal:** Wire DeepSeek-V2 Q8 GGUF into the MoA panel as advisor R7.

**Tasks:**
1. Add local provider entry or NIM entry for DeepSeek-V2 Q8 GGUF in `config.yaml`
   - Provider: `custom:local` (Ollama/llama.cpp serving Q8 GGUF) or `custom:nvidia-nim`
   - Model id: confirmed Q8 GGUF repo/tag from Sprint 0
2. Add advisor entry under `moa.reference_models`:
   ```yaml
   - provider: <confirmed>
     model: <deepseek-v2-q8-id>
     enabled: true
     reasoning_effort: max
   ```
3. Mirror same entry into `moa.presets.default.reference_models`
4. Create `scripts/moa-advisor-probe.ps1` — calls advisor once, writes `--usage-file` output to `scratch/deepseek-v2-usage.json` (per user constraint: prove answering model with usage file)
5. Run probe; confirm no 401/404; confirm `--usage-file` JSON written

**Exit criteria:** `hermes -p seven6moa moa list` shows 7 advisors, all with `[reasoning=max]`; probe succeeds.

---

### Sprint 2 — RAG Retrieval Layer (Days 6–8)

**Goal:** Build dense retrieval block that injects context into DeepSeek-V2 advisor calls.

**Tasks:**
1. Create `./rag-corpus/` with sample documents (`.md`, `.txt`, `.pdf`)
2. Create `scripts/rag-ingest.py`:
   - Scan `rag-corpus/` for documents
   - Chunk at 512 tokens, 50-token overlap
   - Embed with BAAI/bge-m3 (dense)
   - Write FAISS index + metadata JSONL to `scratch/rag-index/`
3. Create `scripts/rag-retrieve.py`:
   - Input: user prompt
   - Output: top-k=5 passages concatenated as context block
   - Hook into MoA advisor call path for DeepSeek-V2 only (other advisors unchanged)
4. Test ingestion + retrieval on sample corpus

**Exit criteria:** Ingestion runs on sample corpus; retrieval returns relevant passages for a test query.

---

### Sprint 3 — Audit & Verification (Days 9–10)

**Goal:** Prove code correctness before benchmarking.

**Tasks:**
1. Create `scripts/audit-config.py`:
   - Parse `config.yaml`; assert exactly 7 `moa.reference_models` entries
   - Assert every advisor has `reasoning_effort: max`
   - Assert aggregator is `nvidia/nemotron-3.5-super-vl-120b-a12b`
   - Assert DeepSeek-V2 provider entry exists with valid `key_env`
2. Run MoA listing audit: `hermes -p seven6moa moa list` — all 7 show `[reasoning=max]`
3. Run token-usage probe for each advisor; confirm `--usage-file` JSON written and non-empty
4. Run RAG audit: ingestion + retrieval; assert top-k passages contain expected keywords
5. Syntax/lint: Python files pass `py_compile`; YAML passes `yaml.safe_load`
6. Write `Sprint3_audit_report.md` with pass/fail per check

**Exit criteria:** 100% of audit checks pass; no 401/404 on any advisor probe.

---

### Sprint 4 — Benchmark Baseline & Efficiency Tuning (Days 11–13)

**Goal:** Measure before/after and tune for latency/accuracy trade-off.

**Tasks:**
1. Baseline benchmark (6 advisors, no DeepSeek-V2, no RAG):
   - MMLU 5-shot (subset: stem, humanities, social_sciences)
   - GSM8K (50 examples)
   - Record: avg latency per turn, VRAM peak, cost estimate
2. Enhanced benchmark (7 advisors + RAG on DeepSeek-V2):
   - Same MMLU/GSM8K subset
   - Record same metrics
3. Tune efficiency knobs one at a time:
   - RAG top-k: 3 → 5 → 8 (accuracy vs. latency)
   - DeepSeek-V2 temperature: 0.6 (thinking mode default)
   - Context truncation for retrieved passages
4. Write `Sprint4_benchmark_report.md` with tables

**Exit criteria:** Enhanced config shows equal-or-better accuracy vs. baseline; latency increase < 40%.

---

## Phase 2 — Production Rollout & Completion

### Sprint 5 — Hardening & Monitoring (Days 14–16)

**Tasks:**
1. Error handling: retry/backoff for DeepSeek-V2 NIM 503/429
2. Fallback chain: if DeepSeek-V2 fails, route to Cosmos-Reason2-8B (R2) automatically
3. Observability: log advisor token counts, RAG hits/misses, latency per advisor to `logs/moa-deepseek-v2.jsonl`
4. Config freeze: merge `feature/deepseek-v2-moa` to `main` after user sign-off
5. Write `Sprint5_hardening.md`

### Sprint 6 — Final Benchmark & Handoff (Days 17–18)

**Tasks:**
1. Full benchmark suite: MMLU (full 5-shot), GSM8K (full), HumanEval (code)
2. Efficiency report: VRAM, cost per turn, latency percentiles (p50/p95/p99)
3. User handoff: walk through `hermes -p seven6moa moa list`, audit report, benchmark results
4. Update FAQ section in repo with final config
5. Write `Sprint6_final_report.md`

---

## Risk Register

| Risk | Mitigation |
|------|------------|
| NVIDIA_API_KEY invalid (HTTP 401) | Sprint 0 pre-flight gate; do not proceed until key validated |
| DeepSeek-V2 236B Q8 too large for VRAM | Use NIM hosted endpoint or expert offload; record VRAM in Sprint 0 |
| RAG retrieval dilutes advisor reasoning | RAG applies only to DeepSeek-V2 advisor; tune top-k in Sprint 4 |
| `reasoning_effort: max` rejected by NIM for a model | Fall back to `xhigh` per model; log rejection |

---

## Files to Create / Modify

**Modify:**
- `config.yaml` — add DeepSeek-V2 advisor entry + RAG hook (Sprint 1–2)
- `faq-answers.md` — add final config section (Sprint 6)

**Create:**
- `scripts/moa-advisor-probe.ps1` (Sprint 1)
- `scripts/rag-ingest.py` (Sprint 2)
- `scripts/rag-retrieve.py` (Sprint 2)
- `scripts/audit-config.py` (Sprint 3)
- `Sprint0_preflight.md` … `Sprint6_final_report.md` (one per sprint)
- `rag-corpus/` sample documents (Sprint 2)
- `logs/moa-deepseek-v2.jsonl` (runtime, Sprint 5)

---

## Next Immediate Step

Starting Sprint 0 now: run NIM pre-flight for DeepSeek-V2 architecture support, search Hugging Face for Q8 GGUF sources, and confirm all six advisors show `[reasoning=max]`.
