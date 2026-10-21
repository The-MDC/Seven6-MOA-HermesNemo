# Seven6-MOA [Nemo-Hermes]

A multi-tier model orchestration for [Hermes Agent](https://github.com/hermes-agent),
with the Codex CLI wired in as an MCP tool server, a declared capability registry,
and the runbook to bring the whole thing up on a Windows machine.

This repo is the **build**, not a product. It carries configuration, verification
scripts, skills and documentation — nothing that ships to an end user.

## The routing

One primary model serves every role that routes inference: **NVIDIA Nemotron 3.5
Super VL** on NVIDIA NIM (2026-10-19, on request: "the nemotron 3.5 Super VL should
be the only gateway and inference"). OpenRouter and local Ollama are failover.
Anthropic-direct stays configured and unrouted. All three were left intact on
request.

| Role | Provider | Model | Notes |
|---|---|---|---|
| parent | `custom:nvidia-nim` | `nvidia/nemotron-3.5-super-vl-120b-a12b` | the primary. 120B total / ~12B active, vision-language, live-verified in the NIM catalog 2026-10-19 |
| subagents | `custom:nvidia-nim` | `nvidia/nemotron-3.5-super-vl-120b-a12b` | same model, same bucket |
| vision | `custom:nvidia-nim` | `nvidia/nemotron-3.5-super-vl-120b-a12b` | pinned, never `auto`; the primary can see |
| MoA aggregator | `custom:nvidia-nim` | `nvidia/nemotron-3.5-super-vl-120b-a12b` | the acting model on a MoA turn and the primary generator (2026-10-20, on request). Ultra held this slot on 2026-10-19 |
| MoA reference 1 | `custom:or-fallback` | `z-ai/glm-5.3-flash` | advisor; also fallback 1. 1M context, $0.047 / $0.16 per MTok |
| MoA reference 2 | `custom:nvidia-nim` | `nvidia/ising-calibration-1.5-31b` | vision, quantum, reviewer. A quantum-calibration VLM: a specialist adviser, not the general vision model |
| MoA reference 3 | `custom:or-fallback` | `mistralai/mixtral-8x22b-instruct` | support, review. 65,536 context, $2 / $6 per MTok. NIM lists only the base model |
| MoA reference 4 | `custom:nvidia-nim` | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` | advisor, review |
| MoA reference 5 | `custom:nvidia-nim` | `nvidia/nemotron-3-ultra-550b-a55b` | reference, research, advisor, reviewer. 550B total / 55B active, text-only |
| fallback 1 | `custom:or-fallback` | `z-ai/glm-5.3-flash` | 429 escape, different bucket (same id as MoA reference 1) |
| fallback 2 | `custom:hf-fallback` | `nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4` | the primary's NVFP4 build through Hugging Face's router (Baseten): a third bucket, vision kept, no tunnel needed. `HF_TOKEN` needs the Inference Providers permission. Added 2026-10-21, on request, after OpenRouter |
| fallback 3 | `custom:llamacpp-supervl-q8` | `nemotron-3.5-super-vl-120b-a12b-q8` | the primary's own weights at Q8_0 (133.7 GB) served by llama.cpp on a big machine, over an SSH tunnel on `127.0.0.1:8082`; answers a 429 on NIM, OpenRouter and Hugging Face alike, keeps vision, and is skipped when the tunnel is down. Added 2026-10-21, on request. Setup: `scripts/q8-local-fetch.sh supervl`, `scripts/q8-local-serve.sh supervl`, skill `q8-local` |
| fallback 4 | `custom:llamacpp-qwen` | `qwen3.8-27b-q8` | Qwen3.8-27B Q8_0 served by llama.cpp on a big machine, reached over an SSH tunnel on `127.0.0.1:8081`; answers a GLM failure and a 429 on either gateway, and is skipped when the tunnel is down. Setup: `scripts/qwen-local-fetch.sh`, `scripts/qwen-local-serve.sh`, skill `qwen-local` |
| fallback 5 | `custom:nvidia-nim` | `nvidia/nemotron-3.5-lightning-30b-a3b` | answers a failure of the parent MODEL, not a 429: it shares the parent's bucket. Replaced the local 49B on 2026-10-19 (8 GB machine; no hosted endpoint serves the 49B) |
| fallback 6 / floor | `custom:local` | `hf.co/mradermacher/Hermes-3-Llama-3.2-3B-abliterated-GGUF:Q8_0` (Ollama) | last resort, plus 5 light auxiliary slots (title, approval, mcp, skills_hub, curator) |
| opt-in MoA reference | `custom:llamacpp-ultra-q8` | `nemotron-3-ultra-550b-a55b-q8` | Ultra at UD-Q8_K_XL (594.5 GB, text only) over a tunnel on `127.0.0.1:8083`. Used only by `moa.presets.local-q8`; takes Ultra's request off the NIM bucket (2 extra NIM requests per MoA turn instead of 3) |
| opt-in MoA reference | `custom:llamacpp-glm-q8` | `glm-5.3-flash-q8` | GLM-5.3-Flash at Q8_0 (342.1 GB) over a tunnel on `127.0.0.1:8084`. Used only by `moa.presets.local-q8`; needs a llama.cpp build with the GLM-5.3-Flash architecture |
| opt-in model switch | `custom:llamacpp-glm-abl-q5` | `glm-5.3-flash-abliterated-q5` | huihui-ai's abliterated GLM-5.3-Flash at UD-Q5_K_XL (241.5 GB, 6 shards + BF16 projector) over a tunnel on `127.0.0.1:8085`. In no preset, fallback or tier: reachable only with `/model custom:llamacpp-glm-abl-q5:glm-5.3-flash-abliterated-q5`. Abliteration removes refusals and no quality measurement exists for this build; fetch it by name (`q8-local-fetch.sh glmabl`), `all` skips it |
| heavy aux | `custom:or-fallback` | `qwen/qwen3.8-27b` | compression, web_extract (the hosted copy of the same model; 1M context, $0.04 / $1.35 per MTok) |
| unrouted | `custom:anthropic-direct` | `claude-sonnet-5` | reachable only via `/model` |

**What this costs, stated plainly.** Parent, subagents, the aggregator, vision and three MoA references (Ising, Omni, Ultra)
draw one ~40 RPM NIM bucket; a MoA turn adds 3 NIM requests per user turn. The CI block requires any slot sharing the parent's provider to use the
parent's exact model, and only `vision` among the auxiliary slots may share it. The
parent no longer runs offline: offline work degrades through `fallback_providers`
(OpenRouter GLM-5.3 Flash, Hugging Face's NVFP4 Super VL, the local Q8_0 Super VL and the local Qwen3.8-27B over their tunnels, Nemotron 3.5 Lightning on NIM, then the local 3B). The five light auxiliary slots
and the two heavy ones stay off the NIM bucket on purpose, because each is a request
taken from the parent's RPM. To move them onto the primary too, change their
`provider`/`model` in `config.yaml`; the CI block will refuse it until the rule is
relaxed for that slot, deliberately.

**The model id is this gateway's.** `nvidia/nemotron-3.5-super-vl-120b-a12b` is the
NIM catalog id (checked against `GET https://integrate.api.nvidia.com/v1/models`,
HTTP 200, 81 models). The same weights carry other ids elsewhere: Vercel AI Gateway
`nvidia/nemotron-3.5-super-vl`, Hugging Face and Baseten
`nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B`, a local served alias
`nemotron-3.5-super-vl`. Context length stays 131072 until `nim-preflight.sh`
measures the real window; the model card says up to 1M, which a card is not.

**Check ids against the gateway.** A retired NIM id answers HTTP 410, and
`nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` is listed in the NIM picker but routed
nowhere. Run `bash scripts/nim-preflight.sh --list | grep -i nemotron` after any
NVIDIA model swap.

**A model id belongs to the gateway, not to the model.** The same weights carry
different ids per gateway (see above), and an id copied between providers is wrong by
default. `discover_models: false` means Hermes never probes `/models`, so a bad id
does not error: it silently resolves to the main model.

**There is no local vision.** The floor model is text-only, and a VL GGUF ships as a
language model plus a separate `mmproj` projector that Ollama cannot attach: `ollama
create` succeeds and silently drops vision. Vision routes to the cloud primary.

## Codex

Codex 0.154.0 removed the `codex mcp-server` entry point, so `codex mcp list`
reports `Unsupported` and always will. `scripts/codex-mcp/server.js` rebuilds the
interface locally: a dependency-free stdio MCP server exposing `codex_exec` and
`codex_status`, putting typed arguments in front of the same subprocess the bundled
skill already drives.

It is **not** an inference provider — `openai-codex` stays in `excluded_providers`,
because Hermes' own provider and the Codex CLI read different token files against the
same ChatGPT window.

## Capabilities

`capabilities.yaml` declares every skill and MCP server once, with the surfaces that
carry it and a required reason for any asymmetry.
`scripts/check-capabilities.py` fails the build when the tree stops matching it.

```
skills        26 declared    21 Claude Code    13 Hermes     8 both
mcp servers   10 declared     4 Claude Code     8 Hermes     2 both
```

These numbers are a snapshot (2026-10-20). `python3 scripts/check-capabilities.py` is
the source of truth. The registry was cut from 94 skills and 16 MCP servers to what
the current build uses; the removed set is in git history at `3f1bc56`.

**This is not a parity demand.** Hosted MCP servers are kept out of Hermes on
purpose: every discovered tool is injected into the system prompt on *every* request,
which on a ~40 RPM tier is a permanent tax. Asymmetry is legitimate; unexplained
asymmetry is indistinguishable from an accident, and that is what the gate catches.

Skills resolve differently on each surface, which is why they are compared by name
and never by path:

| | path | resolved by |
|---|---|---|
| Hermes | `hermes-skills/<category>/<name>/SKILL.md` | the **directory** name |
| Claude Code | `.claude/skills/<category>/<name>.md` | the frontmatter **`name`** |

## Layout

| Path | What |
|---|---|
| `configs/hermes/config.yaml` | the routing core — providers, auxiliary slots, MCP servers |
| `configs/codex/config.toml` | Codex CLI config |
| `capabilities.yaml` | the single declaration of what exists |
| `hermes-skills/` | skills in Hermes format, plus `.port-lock.json` |
| `.claude/skills/` | skills in Claude Code format (counts: `scripts/check-capabilities.py`) |
| `scripts/` | apply, verify, report, doctor, capability gate, skill port, Codex shim |
| `docs/models/` | `TAKEOVER.md` (full bring-up), `VSCODE-QUICKSTART.md` (fast path) |

## Scripts

```bash
pwsh -File scripts/hermes-apply.ps1 -WhatIf   # show what installing would change
pwsh -File scripts/hermes-apply.ps1           # install configs, with backups
pwsh -File scripts/hermes-verify.ps1          # the acceptance gate (includes config drift)
pwsh -File scripts/hermes-apply.ps1 -Profiles NAME   # opt-in: also install into a named profile
pwsh -File scripts/hermes-update-safe.ps1     # stop, back up, hermes update, drift check, restart
pwsh -File scripts/hermes-dashboard-autostart.ps1    # pinned dashboard token + login task (Status by default)
python3 scripts/check-config-drift.py --help  # compare an installed config to the repo copy
pwsh -File scripts/hermes-report.ps1          # paste-safe install inventory
bash   scripts/repo-doctor.sh                 # toolchain, hooks, egress
python3 scripts/check-capabilities.py         # registry vs disk
node   scripts/port-skills-to-hermes.js       # re-port skills to both surfaces
node   scripts/port-skills-to-hermes.js --check   # what has drifted upstream
bash   scripts/q8-local-fetch.sh supervl      # on the big box: Super VL Q8_0 (3 files, 133.7 GB); also ultra, glm, all
bash   scripts/q8-local-serve.sh supervl      # on the big box: llama-server, loopback only, port 8082 (8083 ultra, 8084 glm)
bash   scripts/qwen-local-fetch.sh            # on the big box: the 4 Qwen3.8-27B Q8_0 files, verified
bash   scripts/qwen-local-serve.sh            # on the big box: llama-server (vision + MTP), loopback only
```

### Local Q8+ models (fallback 3 and two opt-in MoA references)

Three models, one fetch script and one serve script (`q8-local-fetch.sh` / `q8-local-serve.sh`),
each taking `supervl`, `ultra` or `glm`. The aggregator is unchanged: hosted NIM, full-size
Super VL.

| Key | Quant | Size | Port | Used as |
|---|---|---|---|---|
| `supervl` | Q8_0 (no Q8_K_XL exists for this model), from `ggml-org` | 133.7 GB, 3 files | 8082 | fallback 3 |
| `ultra` | UD-Q8_K_XL, from `unsloth` (plain Q8_0 is 584.3 GB) | 594.5 GB, 14 shards | 8083 | reference in `moa.presets.local-q8` |
| `glm` | Q8_0 + F16 projector, from `unsloth` | 342.1 GB, 8 shards + 1 | 8084 | reference in `moa.presets.local-q8` |
| `glmabl` | abliterated UD-Q5_K_XL + BF16 projector, from `huihui-ai` (fetched by name only) | 241.5 GB, 6 shards + 1 | 8085 | `/model` switch only |

All three together are about 1,070 GB of files, so they need a rented multi-GPU server, not a
laptop. Sizes and sha256 come from the Hugging Face tree API (2026-10-21), each repo pinned to one
commit; the fetch script checks free disk first, then size, GGUF magic and sha256. One tunnel per
model, local and remote port equal:

```bash
ssh -N -L 8082:127.0.0.1:8082 -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 <user>@<big-box>
```

What is **not** verified: none of this has run against a real `llama-server`. `glm` needs a
llama.cpp build with its architecture, which Unsloth's page shows only on their branch
`glm5next/upstream`. Ultra's GGUFs have no MTP support (Unsloth); `supervl --spec mtp` is
untested. What Hermes does when a MoA reference refuses the connection is undocumented, which is
why the local preset is opt-in. The Hermes-side steps are in the `q8-local` skill.

### Local Qwen3.8-27B (fallback 4)

Qwen3.8-27B at Q8_0 is 28.6 GB, so it runs on a bigger machine, not the 8 GB laptop.
On that machine: `bash scripts/qwen-local-fetch.sh` (four files from `ggml-org/Qwen3.8-27B-GGUF`,
pinned to one commit, checked by size and sha256), then `bash scripts/qwen-local-serve.sh`
(`--spec mtp|dflash|none`). On the laptop that runs Hermes, keep a tunnel open:

```bash
ssh -N -L 8081:127.0.0.1:8080 -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 <user>@<big-box>
```

Hermes reaches it as `custom:llamacpp-qwen` / `qwen3.8-27b-q8`. A closed tunnel only means
the link is skipped. `pwsh -File scripts/hermes-verify.ps1 -Deep` reports which. Hermes
itself can run the steps through the `qwen-local` skill, which refuses to download on a
machine with under 64 GB of memory. Not yet run against a real `llama-server` or a real
Hermes build: the flags follow llama.cpp's documentation and the serve script checks
them against the binary before it starts.

## Commands

`/orchestrate` `/quality-gate` `/learn` `/skill-create` `/plan` `/security`
`/checkpoint` `/doctor`

## Bring it up

Start at `docs/models/TAKEOVER.md`. `docs/models/VSCODE-QUICKSTART.md` is the subset
that gets the local tier and the cloud tiers working and nothing else.

Nothing in this repo has executed against a real Hermes install on Windows. CI proves
the files parse and agree with each other; it cannot prove behaviour.

## Sources

- Anthropic knowledge-work plugins — github.com/anthropics/knowledge-work-plugins
- Everything Claude Code — github.com/affaan-m/everything-claude-code
- Cloudflare security-audit skill (MIT) — github.com/cloudflare/security-audit-skill
- Codex CLI — github.com/openai/codex


