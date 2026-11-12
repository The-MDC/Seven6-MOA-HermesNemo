# hermes-tokentrim

Cuts the fixed prompt Hermes sends on every request, and caps how fast a long session's context grows.
Applied to the `default` profile on 2026-10-15. Nothing was deleted: skills stay on disk, tool schemas stay available.

## Measured result (`hermes prompt-size`, offline, exact)

| default profile            | before   | after    |
|----------------------------|----------|----------|
| system prompt              | 27,894   | 15,574   |
| &nbsp;&nbsp;skills index   | 15,148   | 4,124    |
| tool schemas (tools)       | 46,763 (27) | 27,449 (16) |
| **total chars / ~tokens**  | **74,657 / ~18.7k** | **43,023 / ~10.8k  (-42.4%)** |

## What changed

1. **Skill suites** (`build_superskills.py`): one router skill per category (`video-production-suite`, `productivity-suite`, ...).
   The index lists the suite, the suite lists its guides, the model opens the guide with `read_file`. Original skills are only
   added to `skills.disabled`; their files are untouched. Skills you actually use (from `skills/.usage.json`) plus pdf/docx/xlsx/
   powerpoint/github/claude-code/deep-research stay individually indexed (`--keep`).
2. **Tool deferral** (`tools-block.yaml`): browser (6 tools), text_to_speech, skill_manage, delegate_task load on demand via `tool_search`.
3. **Memory provider off**: the external holographic provider had 0 facts; built-in MEMORY.md / USER.md are unchanged.
4. **Context controls**: `compression.proactive_prune_tokens=48000`, `compression.threshold_tokens=90000`, `file_read_max_chars=124000` (was 1,000,000).
5. **Delegation / compression pinned** (subagents were pointed at provider "Hugging Face" / model "Mistral", which cannot work): subagents on `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning`
   (reasoning `medium`, 3 parallel children, NVIDIA's thinking-mode sampling 0.6 / 0.95), summaries on `nvidia/nemotron-3-super-120b-a12b` with thinking off.
   (First pick was Nemotron 3.5 Lightning; replaced 2026-10-16, see the last section.)

## Re-run / undo

```powershell
# after `hermes update` adds skills, or to refresh the most-used list
python .\build_superskills.py --home "$env:LOCALAPPDATA\hermes" --keep pdf,docx,xlsx,powerpoint,github,claude-code,deep-research --apply
# undo only the suites (re-enables every folded skill)
python .\build_superskills.py --home "$env:LOCALAPPDATA\hermes" --revert
# undo everything from today
Copy-Item "$env:LOCALAPPDATA\hermes\config.yaml.bak-pre-tokentrim-20261015-193954" "$env:LOCALAPPDATA\hermes\config.yaml" -Force
# same bundle for another profile (pick that profile's NIM provider id)
.\apply-tokentrim.ps1 -ProfileName seven6moa -NimProvider custom:nvidia-nim
```

Start a NEW chat in Hermes Desktop afterwards: an open chat keeps the prompt it started with.

## Claude as the everyday model

`use-claude.ps1` validates a real Anthropic API key (pay-per-token, console.anthropic.com), saves it, switches the profile to
`claude-sonnet-5-5`, keeps NVIDIA Nemotron as fallback, and sets `auth.adopt_external_logins=false` so Hermes never borrows Claude Code's login.
The `ANTHROPIC_API_KEY` currently in default's `.env` is not an Anthropic key (wrong format, 45 chars), so Claude is not active yet.

## 2026-10-16 additions

- `apply-tokentrim.ps1 -Preset everyday|orchestrator|local`. Applied: `default` = everyday, `seven6moa` = orchestrator (every selected model untouched,
  `delegate_task` stays eager, MCP/compression/delegation/aux left alone), `mylocal` = local (only `file_read_max_chars=8000`; its 3.4k-token prompt is already
  at the floor, and pruning/compression would force a full re-prefill at ~10 tokens/s).
- Native MoA (`/moa` in the `default` profile): references moved from OpenRouter `:free` to NVIDIA-hosted, same models (`moa-default-nim.yaml`); aggregator unchanged.
- **Ultra stall.** Nemotron 3 Ultra on NVIDIA's hosted endpoint did not answer a trivial prompt within 110-151 s on three routes (default profile, seven6moa, seven6moa with
  reasoning off), while Super 120B through the same Seven6MOA provider answered in 45 s. Hermes floors Ultra's stale-stream wait at 600 s (`agent/reasoning_timeouts.py`), so a
  stalled call blocked ~10 minutes before falling back. A 180 s stale-timeout workaround was tried and then removed (see the next note). Backups: `config.yaml.bak-pre-trim-20261016-011427` (Seven6MOA before the trim), `config.yaml.bak-timeout-20261016-014925` (before the workaround).
- Helpers: `timedrun.ps1` (one-shot with a hard time cap), `realtest.ps1`, `sessflow.py`. Research notes: `RESEARCH-2026-10-16.md`.
- **Ultra removed (2026-10-16, your decision).** `nvidia/nemotron-3-ultra-550b-a55b` was replaced by `nvidia/nemotron-3.5-super-vl-120b-a12b` everywhere it was selected:
  model, provider default, and MoA aggregator (top level and preset) in all 8 NVIDIA profiles (`swap-model.ps1`, backups `config.yaml.bak-swap-20261016-020501`).
  `mylocal` has no Ultra. The Ultra stall workaround (`stale_timeout_seconds`, `api_max_retries`) was removed again. Why it stalled is not fully isolated: three routes never
  answered while Super VL and Super 120B did; during a stall the Hermes process held no network connection, and one-shot runs write no log lines.
  Reuse the script for any future swap: `.\swap-model.ps1 -Old <id> -New <id> [-Profiles a,b] [-WhatIf]`.
## 2026-10-16 consolidation into Seven6MOA

The six tier profiles (`codex-moa`, `local-floor`, `moa-aggregator`, `nim-subagents`, `nim-vision`, `or-fallback`) were folded into `seven6moa`.
Per-slot detail, status and the key audit are in `SEVEN6-ROSTER.md`. Archives of the tiers are in `local-llm\profile-archive\`.

Scripts you run yourself (none of them prints a key character):

| Script | Does |
|---|---|
| `retire-tier-profiles.ps1` | dry run by default; `-Yes` deletes the six tier profiles (each only if its archive is readable) |
| `check-api-keys.ps1` | tests every key in the Hermes `.env` files and in `Desktop\List of API keys.txt` against its provider; `-ShowWords` names unrecognised entries |
| `install-api-keys.ps1` | installs Hugging Face, Supermemory, OpenAI and WhatsApp (Cloud API) keys from the list (or a hidden prompt, `-PromptFor <provider>`), validating each first and never writing a rejected key; hands OpenRouter to the next script; `-Inventory` lists what the file holds |
| `set-openrouter-key.ps1` | `-FromFile <list>` tries every `sk-or-` key, proves each through Hermes with a usage report, rolls back failures, then switches the qwen MoA voice on |

Findings worth remembering:

- Hermes' fallback chain hides failures. A one-shot with `--usage-file out.json` names the model that really answered; use it whenever a provider is under test.
- Forcing a failure with `--provider custom:nvidia-nim` removes that provider's chain entries (Hermes prunes on a deliberate switch). Use `--provider nvidia-nim -m nvidia/no-such-model` instead.
- NVIDIA's `/v1/models` is public, so it cannot validate a key. `check-api-keys.ps1` uses a one-token chat call.
- A PowerShell function called `H` is the `Get-History` alias; an error from it printed two Hugging Face tokens. Name helpers in full (`Get-Sha256Hex`).
- Hosted Nemotron Lightning was slow and flaky, Ultra stalled, and hosted nano-omni answers `503 ResourceExhausted (16/16)` at times.
### Second pass (same day): MCP, gateway, SOUL, plugins

- Eight dead MCP servers disabled (reasons on each line of `config.yaml`); only `open-websearch` works. Google Chat disabled (`platforms.google_chat.enabled: false`).
- `SOUL.md` got a short "Seven6 operating charter" (clarify before big generative work, verify before asserting, delegate, never print keys, no local repos). Undo with `SOUL.md.bak-20261016`.
- Full detail, the MCP table and plugin recommendations: `SEVEN6-ROSTER.md` section 10.
- `check-api-keys.ps1` was added to the audit tools and `install-api-keys.ps1` no longer offers WhatsApp by default (Hermes pairs with the phone through `hermes -p seven6moa whatsapp`).
### Third pass (same night): builds from the link scans, the Chrome page and the gpt-oss decision

| Script / folder | Does |
|---|---|
| `seven6-smoke.ps1` | regression check, every call hard-capped and proven: one-shot (usage report must name the model config.yaml names), forced-failure fallback, delegation (session database must show `delegate_task` and the child model), MoA turn on a throwaway clone (every enabled reference must answer). `-Quick` = first two. A busy provider is reported as ERROR, never as a regression. Results go to `smoke-results.jsonl` keyed by a hash of config.yaml + SOUL.md |
| `plugins\seven6-trim\` | Hermes plugin on the `transform_tool_result` hook. Observe mode by default: logs sizes per tool to `<profile>\seven6-trim.jsonl`, never content. `settings.mode trim` shortens big web/MCP results (JSON stays valid) |
| `install-seven6-trim.ps1`, `seven6-trim-report.ps1` | install and enable the plugin in observe mode (`-Remove` undoes); per-tool report of what a trim would save |
| `enable-gptoss-voice.ps1` | proves gpt-oss-120b (Hugging Face router, pinned to Cerebras) through Hermes, then switches MoA voice R6 on in both places in config.yaml; `-ProveOnly`, `-Disable` |
| `smoke_db.py`, `plugins\test_seven6_trim.py` | read-only session-database helper for the smoke test; 21 unit tests for the plugin |

Findings worth remembering:

- A one-shot (`-z`) prints only the answer and writes no log. To see why a provider failed, run `hermes -p <profile> chat -q "Reply PONG" -Q -v --provider <p> -m <model>` and read the 401 or 5xx.
- With two `HF_TOKEN` lines in one `.env`, Hermes used the rejected one (HTTP 401) even though a valid one followed. The audit counts both lines; `install-api-keys.ps1` leaves one.
- `hermes profile delete <name> --yes` leaves the session identity pending; finish with `hermes profile purge-identity <name>`.
- `hermes profile create <new> --clone-from seven6moa --no-alias` copies keys, so throwaway clones can run real calls.
- A model id with a host suffix (`openai/gpt-oss-120b:cerebras`) makes Hermes lose the context length (it guessed 256,000), so the `hf-gptoss` provider declares 131,072.
- Hermes's skills scanner blocks community skills with documentation code in them (Chrome's Modern Web Guidance: CAUTION, chrome-extensions: DANGEROUS and not installable even with `--force`). Nothing was forced.
- PowerShell cannot run a script from a path over 260 characters (the session scratch folder); keep scripts in short paths.
- Detail for all of this: `SEVEN6-ROSTER.md` section 11 and `RESEARCH-2026-10-16.md` sections 7.5, 7.6 and 8.