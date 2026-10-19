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
| MoA reference | `custom:nvidia-nim` | `nvidia/nemotron-3.5-super-vl-120b-a12b` | |
| MoA aggregator | `custom:nvidia-nim` | `nvidia/nemotron-3-ultra-550b-a55b` (550B total / 55B active, text-only) | the one role that is deliberately another model. It is the acting model on a MoA turn, so it runs the tool loop; CI requires it to differ from every reference |
| fallback 1 | `custom:or-fallback` | `qwen/qwen3.5-122b-a10b` | 429 escape, different bucket |
| fallback 2 | `custom:local` | `hf.co/unsloth/Llama-3_3-Nemotron-Super-49B-v1_5-GGUF:UD-Q8_K_XL` (Ollama) | offline, full strength |
| fallback 3 / floor | `custom:local` | `hf.co/mradermacher/Hermes-3-Llama-3.2-3B-abliterated-GGUF:Q8_0` (Ollama) | last resort, plus 5 light auxiliary slots (title, approval, mcp, skills_hub, curator) |
| heavy aux | `custom:or-fallback` | `qwen/qwen3.5-122b-a10b` | compression, web_extract |
| unrouted | `custom:anthropic-direct` | `claude-sonnet-5` | reachable only via `/model` |

**What this costs, stated plainly.** Parent, subagents, MoA reference and vision
draw one ~40 RPM NIM bucket. The CI block requires any slot sharing the parent's provider to use the
parent's exact model, and only `vision` among the auxiliary slots may share it. The
parent no longer runs offline: offline work degrades through `fallback_providers`
(OpenRouter, then the local 49B, then the local 3B). The five light auxiliary slots
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
skills        95 declared    77 Claude Code    29 Hermes    11 both
mcp servers   16 declared    10 Claude Code     8 Hermes     2 both
```

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
pwsh -File scripts/hermes-verify.ps1          # the acceptance gate
pwsh -File scripts/hermes-report.ps1          # paste-safe install inventory
bash   scripts/repo-doctor.sh                 # toolchain, hooks, egress
python3 scripts/check-capabilities.py         # registry vs disk
node   scripts/port-skills-to-hermes.js       # re-port skills to both surfaces
node   scripts/port-skills-to-hermes.js --check   # what has drifted upstream
```

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


