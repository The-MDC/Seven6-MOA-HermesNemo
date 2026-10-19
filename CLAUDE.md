# Seven6-Hermes-MOA — Claude Code context

## What this repo is

A multi-tier model orchestration for Hermes Agent, with the Codex CLI wired in as an
MCP tool server. Configuration, verification scripts, skills and a bring-up runbook.

**It carries no product content.** No company, no branding, no business figures. If
you are about to add any, you are in the wrong repo. `SCRUB` in
`scripts/port-skills-to-hermes.js` removes product references from ported skill
content, and the port fails if one survives into the output tree.

## The routing

```
parent      custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   THE primary model (2026-10-19)
subagents   custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   same model, same bucket
vision      custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   pinned, never `auto`
moa ref     custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b
aggregator  custom:local         Llama-3.3-Nemotron-Super-49B-v1.5, UD-Q8_K_XL (Ollama)  the one deliberate exception
fallback 1  custom:or-fallback   qwen/qwen3.5-122b-a10b              429 escape + 2 heavy aux (compression, web_extract)
fallback 2  custom:local         the 49B GGUF above                  offline, full strength
fallback 3  custom:local         Hermes-3-Llama-3.2-3B-abliterated:Q8_0 (Ollama)   last resort + 5 light aux slots
unrouted    custom:anthropic-direct  claude-sonnet-5                 configured, intact, reachable only via /model
```

**Nemotron 3.5 Super VL is the only model this build routes inference to**, on
request (2026-10-19: "the nemotron 3.5 Super VL should be the only gateway and
inference ... leave the other inference gateways intact"). OpenRouter, local Ollama
and Anthropic-direct stay configured; the first two are failover, the third is
unrouted. The aggregator is the one role that is deliberately another model: MoA
needs a different provider and model to check the reference against.

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
parent, because a 429 on NIM cannot be answered from NIM. The old fallback 1
(nano-omni on the same NIM key) was removed from the chain for that reason.

`nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` is still in the NIM picker and
routed nowhere. DeepSeek and `hf-router` stay removed (2026-09-28); `local-vl` and
hermes3:8b stay removed (2026-09-25). `nvidia/llama-3.3-nemotron-super-49b-v1.5` is
dead (HTTP 410, end-of-life 2026-08-26), which a "triangulated against three
resellers" check missed and `bash scripts/nim-preflight.sh --list | grep -i
nemotron` would have caught. Run that after any NVIDIA model swap.

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

Skills live in `.claude/skills/` by domain: marketing, sales, product, engineering,
data, operations, legal, finance, productivity, cowork, ecc.

Commands live in `.claude/commands/`:
`/orchestrate` `/quality-gate` `/harness-audit` `/learn` `/evolve` `/skill-create`
`/model-route` `/plan` `/security` `/checkpoint` `/doctor` `/market-brief`

## Hooks

Wired in `.claude/settings.json` — the only file Claude Code reads hooks from.
`scripts/repo-doctor.sh` fails if any of these points at a missing script.

- `before-submit-prompt.js` — `UserPromptSubmit` — secret scanning on the prompt
- `after-mcp-execution.js` — `PostToolUse` / `mcp__.*` — MCP result logging
- `post-edit-check.js` — `PostToolUse` / `Write|Edit` — console.log warning, Prettier, `tsc --noEmit`
- `pre-bash-guard.js` — `PreToolUse` / `Bash` — blocks `--no-verify` git hook bypass (the only blocking hook)
- `stop-audit.js` — `Stop` — console.log sweep across changed files

**Not active**: `session-start.js`, `session-end.js`, `pre-compact.js` and `stop.js`
are unwired forwarders to Cursor hooks that were never in this repo — they do
nothing. `.claude/hooks/hooks.json` was a Cursor config (Cursor event names,
`.cursor/` paths that never existed) and has been removed; Claude Code never read it.
See `.claude/hooks/README.md`.
