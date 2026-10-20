# Seven6-MOA [Nemo-Hermes] — Claude Code context

## What this repo is

A multi-tier model orchestration for Hermes Agent, with the Codex CLI wired in as an
MCP tool server. Configuration, verification scripts, skills and a bring-up runbook.

**It carries no product content.** No company, no branding, no business figures. If
you are about to add any, you are in the wrong repo. `SCRUB` in
`scripts/port-skills-to-hermes.js` removes product references from ported skill
content, and the port fails if one survives into the output tree.

## Two context files, on purpose

This file is for Claude Code. **Hermes loads `.hermes.md` instead of this file** when it runs
from this checkout (its priority is `.hermes.md` > `AGENTS.md` > `CLAUDE.md`, and only one
loads). `.hermes.md` is short because Super VL has 12B active parameters, a 131k window and
a ~40 RPM bucket; CI caps its size. Change routing facts in both.

## The routing

```
parent      custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   THE primary model (2026-10-19)
subagents   custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   same model, same bucket
vision      custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   pinned, never `auto`
moa ref     custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b
aggregator  custom:nvidia-nim    nvidia/nemotron-3-ultra-550b-a55b        the one deliberate exception (2026-10-19), text-only
fallback 1  custom:or-fallback   qwen/qwen3.5-122b-a10b              429 escape + 2 heavy aux (compression, web_extract)
fallback 2  custom:local         Llama-3.3-Nemotron-Super-49B-v1.5, UD-Q8_K_XL (Ollama)  offline, full strength
fallback 3  custom:local         Hermes-3-Llama-3.2-3B-abliterated:Q8_0 (Ollama)   last resort + 5 light aux slots
unrouted    custom:anthropic-direct  claude-sonnet-5                 configured, intact, reachable only via /model
```

**Nemotron 3.5 Super VL is the primary model**, on request (2026-10-19: "the
nemotron 3.5 Super VL should be the only gateway and inference ... leave the other
inference gateways intact"). OpenRouter, local Ollama and Anthropic-direct stay
configured; the first two are failover, the third is unrouted. The one other model
this build routes to is the **MoA aggregator**, `nvidia/nemotron-3-ultra-550b-a55b`
(2026-10-19, on request): on a MoA turn the aggregator is the ACTING model (it writes
the reply and runs every tool-loop iteration; the references only advise, once per
user turn), so it is text-only here, slower per call than Super VL, and on the same
NIM bucket. CI requires it to differ from every reference, to be listed under its
provider's `models:`, to carry a raised compaction threshold, and to match between the
flat `moa.aggregator` key and `moa.presets.<default>.aggregator` -- the two shapes of
the MoA schema, both written because the installed Hermes version is unconfirmed.
Capability is mixed, not one-sided: NVIDIA's own tables put Ultra ahead on tau2-bench,
IFBench and SWE-bench Verified and Super VL ahead on BrowseComp, Terminal-Bench 2.1 and
GPQA, and Artificial Analysis's index scores Super VL 26 to Ultra's 23.

The id `nvidia/nemotron-3.5-super-vl-120b-a12b` was checked against NVIDIA's own
catalog (`GET https://integrate.api.nvidia.com/v1/models`, HTTP 200, 81 models,
exact match) on 2026-10-19. It is this gateway's id: the same weights are
`nvidia/nemotron-3.5-super-vl` on Vercel AI Gateway,
`nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B` on Hugging Face and Baseten, and
`nemotron-3.5-super-vl` as a local alias. `context_length` stays 131072 until
`scripts/nim-preflight.sh` measures it; the model card's "up to 1M" is not an
endpoint measurement. The preflight also checks that the reply names the model you
asked for, because a forum report says the hosted endpoint once did not.

**One bucket now.** Parent, subagents, MoA reference and vision share one ~40 RPM
NIM key. The CI block enforces the replacement rule: a slot may share the parent's
provider only on the parent's exact model, only `vision` among the auxiliaries may,
and every `fallback_providers` link must sit on a different endpoint from the
parent, because a 429 on NIM cannot be answered from NIM.

`nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` is in the NIM picker and routed
nowhere. A retired NIM id answers HTTP 410, not a config error, so run
`bash scripts/nim-preflight.sh --list | grep -i nemotron` after any NVIDIA model swap.

Three rules that have each cost a session here:

1. **A model id belongs to the GATEWAY, not the model.** The same weights carry
   different ids per gateway. `discover_models: false` means Hermes never probes
   `/models`, so a wrong id does not error — it silently resolves to the main model.
2. **`auto` in an auxiliary slot means "use the main model".** That is how vision
   broke silently when the parent changed to a model with no vision encoder.
3. **A provider named after its own exclusion hides itself.** `excluded_providers`
   matches case-insensitively against every key a provider surfaces under, which is
   why the OpenRouter entry is called `or-fallback`.

## Capabilities

`capabilities.yaml` declares every skill and MCP server once, with its surfaces and a
required `asymmetry_reason` when it is on one surface only.
`scripts/check-capabilities.py` makes that binding — it fails the build when disk
stops matching the declaration.

Name resolution differs by surface, which matters when adding anything:

- **Hermes** resolves a skill by its **directory** name — `hermes-skills/<category>/<name>/SKILL.md`
- **Claude Code** resolves it by the frontmatter **`name`** — `.claude/skills/<category>/<name>.md`

A skill with a malformed `metadata.hermes` block loads without complaint and simply
never triggers. The gate checks frontmatter for exactly that reason.

Hosted MCP servers are kept out of Hermes on purpose: every discovered tool is
injected into the system prompt on *every* request, which on a ~40 RPM tier is a
permanent tax. Asymmetry is legitimate; unexplained asymmetry is not.

## Verification

Run these before trusting a change. Each exists because something passed silently
that should not have:

```bash
python3 scripts/check-capabilities.py             # registry vs disk
node   scripts/port-skills-to-hermes.js           # re-port; prints `scrub: clean`
node   scripts/port-skills-to-hermes.js --check   # upstream drift, writes nothing
bash   scripts/repo-doctor.sh                     # toolchain, hooks, egress
node   scripts/gateway-doctor.js                 # sticky profile (exit 78), plugin symlink stubs
pwsh -File scripts/hermes-verify.ps1              # the acceptance gate, on the box
```

**A check that cannot fail is not a check, and one that cannot pass is worse.** This
repo has shipped both: an assertion that hardcoded a retired model and kept passing,
and a gate that failed on a permanent upstream condition so no install could ever go
green. When you add an assertion, prove it fails against a deliberately broken input
before trusting it.

## Changing the config safely

1. Edit the **repo** copy, never the installed one.
2. Run the CI assertion block from `.github/workflows/checks.yml` locally.
   `hermes config: OK` is the pass line.
3. If you touched a model id, check it against **that gateway's** catalog.
4. `hermes-apply.ps1 -WhatIf`, then for real.
5. `hermes-verify.ps1 -Stage full -Deep`.

## Behaviour rules

1. Read context files before generating — never assume.
2. One deliverable per prompt; don't batch unrelated tasks.
3. Use AskUserQuestion when a task needs clarification before execution.
4. Apply the `security-review` skill before any production-bound change.
5. Apply the `verification-loop` skill before opening a PR.

## Skills and commands

Skills live in `.claude/skills/` by domain: engineering, operations, ecc. The current
counts come from `python3 scripts/check-capabilities.py`, never from prose.

Commands live in `.claude/commands/`:
`/orchestrate` `/quality-gate` `/learn` `/skill-create` `/plan` `/security`
`/checkpoint` `/doctor`

## Hooks

Wired in `.claude/settings.json` — the only file Claude Code reads hooks from.
`scripts/repo-doctor.sh` fails if any of these points at a missing script.

- `before-submit-prompt.js` — `UserPromptSubmit` — secret scanning on the prompt
- `after-mcp-execution.js` — `PostToolUse` / `mcp__.*` — MCP result logging
- `post-edit-check.js` — `PostToolUse` / `Write|Edit` — console.log warning, Prettier, `tsc --noEmit`
- `pre-bash-guard.js` — `PreToolUse` / `Bash` — blocks `--no-verify` git hook bypass (the only blocking hook)
- `stop-audit.js` — `Stop` — console.log sweep across changed files

Nothing else is wired. Claude Code reads hooks only from `.claude/settings.json`. See
`.claude/hooks/README.md`.
