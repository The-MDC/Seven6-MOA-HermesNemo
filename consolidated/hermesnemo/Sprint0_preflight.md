# Sprint 0 Pre-Flight Report — DeepSeek-V2 236B Q8 GGUF Advisor

**Profile:** seven6moa  
**Config:** C:\Users\nicholasjmcleod\AppData\Local\hermes\profiles\seven6moa\config.yaml  
**Date:** 2026-10-18  
**Status:** GO for Sprint 1

---

## Dependencies Verified

### 1. MoA Section Located
`config.yaml` lines 179–213:
- 6 reference_models entries, all `enabled: true`, all `reasoning_effort: max`
- Aggregator: `nvidia-nim:nvidia/nemotron-3.5-super-vl-120b-a12b` (unchanged)
- Preset `default` mirrors reference_models (lines 216–228)

### 2. All Six Existing Advisors at Max Thinking
`hermes -p seven6moa moa list` output:
1. NVIDIA-Nemotron-3.5-Super-VL-120B-A12B.dspark [reasoning=max]
2. nvidia/cosmos-reason2-8b [reasoning=max]
3. nvidia/ising-calibration-1.5-31b [reasoning=max]
4. ibm/granite-34b-code-instruct [reasoning=max]
5. mistralai/mixtral-8x22b-v0.1 [reasoning=max]
6. bigcode/starcoder2-15b [reasoning=max]

### 3. Q8 GGUF Source Confirmed
**Ollama library:** `deepseek-v2:236b-chat-q8_0`  
URL: https://ollama.com/library/deepseek-v2:236b-chat-q8_0  
- Requires Ollama 0.1.40+
- 236B total, 21B active per token (MoE)
- Bilingual English/Chinese
- Servable via the existing `local` (Ollama) provider in config.yaml

### 4. NVIDIA NIM Support Matrix
DeepSeek-V2 236B is **NOT** listed in NIM supported architectures (only deepseek-v4-pro, deepseek-v4.1-flash appear).  
→ **Decision confirmed:** Local Q8 GGUF via Ollama `local` provider, NOT NIM.

### 5. Local Provider Already Exists
`config.yaml` lines 115–120:
```yaml
local:
  name: Ollama (this machine)
  api: http://127.0.0.1:11434/v1
  api_key: no-key-required
  transport: chat_completions
  default_model: hf.co/mradermacher/Hermes-3-Llama-3.2-3B-abliterated-GGUF:Q8_0
```

---

## Decisions Locked (from user)

| Gate | Decision |
|------|----------|
| Model slot | R7 — 7th advisor (keeps all 6 existing) |
| Quantization | Q8 GGUF local via Ollama |
| RAG corpus | Local `./rag-corpus/` directory |

---

## Remaining Pre-Flight Check (Sprint 1 gate)

Before writing config, verify Ollama is running and can serve `deepseek-v2:236b-chat-q8_0`:
- `curl http://127.0.0.1:11434/v1/models` — confirm endpoint responds
- Check if model is already pulled or needs `ollama pull deepseek-v2:236b-chat-q8_0`
