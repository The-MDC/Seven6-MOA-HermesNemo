# Handoff — current state of the Hermes/Codex build

**Update this file in place. Do not add another dated handoff.** Audits keep finding
documents that describe an earlier topology as current, because each was written as a
point-in-time snapshot and then left. A living state file with one authoritative
version does not rot the same way. "What is true now" belongs here, and only here.
Anything that must survive a deletion is migrated into this file or into
`configs/hermes/config.yaml`'s inline comments first (see the removal log below).

Last updated: 2026-10-20 · Branch: `claude/seven6-moa-consolidate` (stacked on
`claude/nemotron-3.5-super-vl-primary`, PR #27) · Super VL is the primary; the
consolidation and its compensations for Super VL's weak spots are described under
"Super VL: known weak spots and what compensates".

---

## Orientation: read these, in this order

1. **This file** — state, open items, and what needs a human.
2. `VSCODE-QUICKSTART.md` — fast path: Ollama, the local floor model, and the cloud tiers.
3. `TAKEOVER.md` — the full six-phase bring-up, one success line per step.
4. `configs/hermes/config.yaml` — the config itself carries the reasoning inline.

Request-economics and rate-limit-bucket reasoning lives in
`configs/hermes/config.yaml`'s inline comments on the current topology.

---

## The architecture as committed

```
parent      custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   THE primary, 2026-10-19, on request
                                  ("the nemotron 3.5 Super VL should be the only gateway and inference")
subagents   custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   same model, same bucket
vision      custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   pinned, never `auto`; it is a VL model
aggregator  custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   (2026-10-20, on request) ACTS on a MoA turn;
                                  Nemotron 3 Ultra held this slot on 2026-10-19
moa ref 1   custom:or-fallback   z-ai/glm-5.3-flash                       advisor; also fallback 1
moa ref 2   custom:nvidia-nim    nvidia/ising-calibration-1.5-31b          vision, quantum, reviewer
moa ref 3   custom:or-fallback   mistralai/mixtral-8x22b-instruct          support, review (NIM lists only the base model)
moa ref 4   custom:nvidia-nim    nvidia/nemotron-3-nano-omni-30b-a3b-reasoning   advisor, review
moa ref 5   custom:nvidia-nim    nvidia/nemotron-3-ultra-550b-a55b         reference, research, advisor, reviewer
fallback 1  custom:or-fallback   z-ai/glm-5.3-flash                        429 escape, different bucket
fallback 2  custom:hf-fallback   nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4   HF router (Baseten), the primary's NVFP4 build; third bucket (2026-10-21)
fallback 3  custom:llamacpp-supervl-q8 nemotron-3.5-super-vl-120b-a12b-q8   Super VL Q8_0 via SSH tunnel 127.0.0.1:8082 (2026-10-21)
fallback 4  custom:llamacpp-qwen qwen3.8-27b-q8                            Qwen3.8-27B Q8_0 via SSH tunnel 127.0.0.1:8081 (2026-10-21)
fallback 5  custom:nvidia-nim    nvidia/nemotron-3.5-lightning-30b-a3b     model-level failover; same bucket as the parent (no 429 escape)
fallback 6  custom:local         hf.co/mradermacher/Hermes-3-Llama-3.2-3B-abliterated-GGUF:Q8_0
                                  last resort + the 5 light aux slots
unrouted    custom:anthropic-direct  claude-sonnet-5, Anthropic's OpenAI-compat endpoint: in providers:
                                  wired into NOTHING; /model custom:anthropic-direct:claude-sonnet-5

auxiliary   5 slots -> Hermes-3-Llama-3.2-3B-abliterated:Q8_0   routing, classification,
                                                                  titles, approval, curator
            2 slots -> qwen/qwen3.8-27b            compression, web_extract (hosted)
            1 slot  -> nvidia-nim                  vision (nemotron-3.5-super-vl-120b-a12b)
mcp         8 servers, 2 hosted (cloudflare, submcp) on an explicit CI allowlist;
            all 8 set prompts:false + resources:false (CI-enforced)
```

What changed on 2026-10-20, on request: the MoA roster. Super VL is now the aggregator
(it keeps vision and tool calling, and each loop iteration is a 12B-active call). Ultra
moved to a reference alongside GLM-5.3 Flash, Mixtral 8x22B instruct, Ising-Calibration
1.5 31B and Nano Omni. GLM-5.3 Flash is also fallback 1. Cost: three NIM requests per
user turn on a MoA turn, plus OpenRouter spend for Mixtral ($2 / $6 per MTok). Measured
2026-10-20 on the PC with the Hermes key: `nvidia/ising-calibration-1.5-31b` answers on
NIM, HTTP 200, for text and for an image (read "NIM TEST" from a generated PNG; first
image call was slow). It ignores brevity instructions and describes itself as a qubit
calibration-plot reader built on Gemma 4, so treat it as a specialist adviser. Not
measured: whether this key may call the Omni id, the OpenRouter ids on this account
(GLM-5.3 Flash, Mixtral), and Mixtral's 65,536 window against the provider-wide
`context_length`.
The earlier open question below (swap the aggregator and reference roles) is resolved.

What changed on 2026-10-19, and what it cost:

- **One bucket.** Parent, subagents, aggregator, vision and (from 2026-10-20) three MoA references share one ~40 RPM NIM key.
  `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` stays in the NIM picker and routes
  nowhere. The old fallback 1 (that nano on the same key) left the chain, because a 429
  on the parent hit it too.
- **No offline parent, and no local 49B.** The 49B GGUF was the parent from 2026-09-28 and
  the MoA aggregator until 2026-10-19, then fallback 2. It was removed the same day: the
  target machine has 8 GB of RAM, and no hosted endpoint serves it (NIM, OpenRouter and
  DeepInfra catalogs and Hugging Face inference providers checked 2026-10-19). The NIM fallback
  (now fallback 5) is `nvidia/nemotron-3.5-lightning-30b-a3b` on NIM, on request. It shares the parent's bucket, so it answers
  a failure of the parent MODEL, not a 429; fallbacks 1 and 2 (OpenRouter, then Hugging Face) are the 429 escape.
  Offline work now degrades to the 3B floor, and MoA needs NIM.
- **Context length is unmeasured.** `providers.nvidia-nim.context_length` stays 131072.
  The model card says up to 1M; raise it only to what `scripts/nim-preflight.sh` reports.
- **Unverified claim to settle.** A forum report says the hosted endpoint once answered
  under a different model id than requested. `nim-preflight.sh` now warns when the reply
  names another model.
Three structural rules hold this together. Breaking any one fails **silently**:

1. **Provider references must dodge `excluded_providers`.** `deepseek`, `openrouter`
   and `ollama` are all excluded, and exclusion matches every key a provider surfaces
   under. That is why the remaining entries are named `or-fallback` and `local`.
   Naming an excluded provider directly resolves to nothing and falls back to the
   main model — a bill and a latency change, no error.
2. **One model per bucket.** A slot may share the parent's provider only on the
   parent's exact model; only `vision` among the auxiliaries may; every
   `fallback_providers` link must be on a different endpoint from the parent.
3. **No auxiliary slot may sit on `auto`.** `auto` means "use the main model", which
   puts side jobs on the parent's bucket, and it silently breaks `vision` the day the
   parent changes to a model with no vision encoder.

---

## Done and verified

| Thing | How it was verified |
|---|---|
| Config topology | CI assertion block run against it; 3 negative tests reproducing each silent-failure shape all rejected |
| CI catches dangling provider refs | Negative-tested: excluded-provider ref, renamed provider, deleted provider |
| PowerShell scripts parse | `Parser::ParseFile` locally **and** in CI (`shell: pwsh` on ubuntu-latest) |
| `hermes-apply.ps1` is safe | Executed against a throwaway root: idempotent on identical content; on drift it backs up first and the drifted line survives in the backup |
| No credential leakage | Ran with dummy keys in `.env`; zero occurrences in output |
| `hermes-council` | **Fixed on the box.** Wrapper starts clean, no ModuleNotFoundError |
| GitHub Actions | Green on all 7 commits, 6–12s each |
| Port checks are now portable | **Resolved 2026-09-22.** `Test-NetConnection` is Windows-only and was listed here as a path that had never executed. Off Windows it did not fail cleanly — it threw `term not recognized` straight to stderr while the surrounding logic carried on. Replaced with a `TcpClient` helper that behaves identically everywhere, then exercised in a container against all three states: server up with the right alias (ok), server up with the wrong id (FAIL naming `--alias` as the fix), server down (FAIL) |
| Cloudflare Workers disconnected | **Resolved 2026-09-22.** The integration was deleted by the repo owner. Verified rather than assumed: PR #13's head carried two check runs (`Workers Builds` failing in 0s, `harness checks`), PR #14's head carries **one** — `harness checks`, green, 12s. The `Workers Builds` run is absent, not merely passing. The red X frozen in #13's history does not clear: completed check runs are immutable |

## Assumed, NOT verified

Be explicit about these. Each is the dangling-reference class that CI structurally
cannot see.

- **Whether `hf.co/mradermacher/Hermes-3-Llama-3.2-3B-abliterated-GGUF:Q8_0` is
  pulled on the box.** `ollama pull` for it is documented (see the table above);
  the disk is the open question.
- **`cloudflare` and `submcp` MCP URLs and tool lists** — taken from the handoff,
  never reachable from the build container. A wrong URL fails loudly; a wrong
  `tools.include` fails silently by filtering everything out.
- **The Codex shim has never run against a real `codex` binary.** Its error paths
  were exercised against a stub; the happy path is simulated. It matters more now:
  `codex_exec` is the routing answer for terminal-heavy coding, which is a Super VL
  weak spot.
- **No script here has executed against a real Hermes install on Windows.** CI proves
  the files parse and agree with each other. It cannot prove behaviour.
- **Super VL reasoning knobs.** The model card documents `enable_thinking` and
  `medium_effort` through `chat_template_kwargs`. Whether NIM's hosted endpoint
  honours them, and how Hermes' `reasoning_effort` maps onto them, is untested: no
  NVIDIA key was available in the build container. `scripts/nim-preflight.sh`
  carries the probe.
- **Model swaps on NIM.** A retired id answers HTTP 410, not a config error. Run
  `bash scripts/nim-preflight.sh --list | grep -i nemotron` after every swap; do not
  triangulate against resellers.
- **`anthropic-direct` under a real key.** Verified live with garbage credentials
  only (two probes distinguishing this endpoint's OpenAI-shaped vs. Anthropic-shaped
  errors, and that `/models` needs `x-api-key` not `Bearer`) — never confirmed that
  a real `ANTHROPIC_API_KEY` actually returns `claude-sonnet-5` content. Unwired
  into any role; `hermes-verify.ps1 -Deep` closes the gap if `ANTHROPIC_API_KEY` is set.

`pwsh -File scripts/hermes-verify.ps1 -Stage full -Deep` now reads each provider's
endpoint and model id **out of the installed config** rather than restating them, so
the probe can no longer drift from what Hermes actually sends — which is how the
OpenRouter id stayed wrong through a merge. It checks each provider's **catalog
before the completion**, because a failed completion alone cannot distinguish a wrong
model id from an exhausted quota, and those need opposite fixes.

---

## Needs a human — cannot be done from a session

### 1. Rotate the Render bearer token

An earlier deployed `config.yaml` carried it **inline**. The MCP entry is now
disabled and absent from the committed config — but **disabling is not rotating**,
and the two are unrelated. Disabling stops Hermes *using* the server. The credential
is still readable in:

- shell history on the box
- the `config.yaml.bak-*` files on the box (the deployment kept at least four)
- any Hermes gateway log that captured the config at startup

A Render bearer token is account-level API access — services, deploys, environment
variables. Rotation in the Render dashboard is the only thing that closes it.

> If the token was never live, or the box is single-user and the `.bak-*` files and
> history have been cleared, then this is done — **say so and remove this item.**
> Three files currently assert it needs rotating. If that stops being true, leaving
> the assertion in place is exactly the staleness the 2026-09-22 audit cleaned up.

**Answer it with `scripts/hermes-report.ps1`**, which exists because no session can
see this machine:

```powershell
pwsh -File scripts/hermes-report.ps1
```

It inventories `$HERMES_HOME`, finds every `config.yaml.bak-*`, and reports **how
many key-shaped strings each one contains and of what family** — never the value.
That is the whole question: a backup with zero hits means nothing is exposed there,
and one with a `rnd_` hit means rotate before deleting, because deleting a file does
not un-expose what was in it. Its output is safe to paste back: values are never
read into a variable, and every line is scrubbed of key shapes on the way out.

### 2. Run the quickstart on the Windows box

Everything in this repo is config and scripts; none of it is exercised until someone
runs it. `docs/models/VSCODE-QUICKSTART.md`, then
`pwsh -File scripts/hermes-verify.ps1 -Stage full -Deep`.

### 3. Decide the open calls

- **`skills.external_dirs`** — commented in `config.yaml`. Turning it on points Hermes
  at the repo checkout so `git pull` is live, instead of copying skills into
  `~/.hermes/skills/` where nothing reports drift. It also means a moved or deleted
  checkout silently removes every skill. Deliberate either way.
- **`operations/hermes-orchestration`** — upstream ships
  `autonomous-ai-agents/hermes-agent`, which covers Hermes in general better than
  ours does. Ours stays narrow: these tiers, these gateway ids, these scripts. If it
  starts restating the general case, cut that part.
- **`scripts/inventory-local-models.ps1`** — a read-only utility that lists what
  Ollama holds against what the config expects. Nothing links to it; run it before
  trusting a "model is pulled" claim.
- **MoA is a spend multiplier.** It makes at least six inference calls per turn
  (five references advise once per user turn, then the aggregator acts), three of them
  on one ~40 RPM NIM bucket and two on OpenRouter. Defensible for hard problems, a bad default. Keep it behind the
  explicit preset, not on the default path.

### Deliberately not started

MemoryCore (ports 8420/8125 closed, `.env` values still placeholders, storage engine
undecided) and the WhatsApp platform (`WHATSAPP_ENABLED=false`; an old
`gateway_state.json` can carry stale fatal state). Neither gets wired in before its
prerequisites are real. A configured-but-never-paired platform is also the textbook
way to get gateway exit 78 (below).

### Gateway exit 78

**Diagnosed on the user's box, 2026-10-19.** `hermes gateway run -vv` printed
"Profile 'seven6moa' does not get a gateway of its own": the sticky active profile
was `seven6moa`, so every gateway launch (Hermes Desktop included) was refused and the
process exited 78. This is `EX_CONFIG`, a fatal configuration error; it is not a crash.
The source also returns 78 when every failing platform failed non-retryably (token
collision, never-paired WhatsApp), but that is not what happened here.

Fix: make `default` the sticky profile and start the one host gateway from it.

```powershell
hermes profile use default
hermes gateway install        # or, to watch it: hermes gateway run -vv
```

Select the swarm profile per command with `hermes -p seven6moa ...`. Alternatives Hermes
itself offers: `hermes gateway migrate --multiplex` to fold an existing per-profile
fleet onto the host gateway, or `gateway.standalone: true` in the profile's own
`config.yaml`, which Hermes labels a temporary shim that will be removed.

**Make this build the gateway's default (2026-10-19, on request).** The gateway always
runs from the `default` profile, so the build has to be what `default` loads, not a named
profile. `hermes-apply.ps1` already installs into `$HERMES_HOME` (default
`%LOCALAPPDATA%\hermes`, which is the `default` profile), with backups:

```powershell
pwsh -File scripts/hermes-apply.ps1 -WhatIf    # preview
pwsh -File scripts/hermes-apply.ps1            # config.yaml, codex config, skills -> default profile
hermes profile use default                     # removes the sticky active_profile file
hermes gateway install
hermes config check
```

`.env` is not touched; keys the named profile held in its own `.env` must exist in the
default one (`%LOCALAPPDATA%\hermes\.env`). Do not run `hermes profile use seven6moa`:
that is the command that reproduces exit 78.

**Desktop plugin "failed to load: Unexpected token '.'" (diagnosed 2026-10-19).** The
catalog pins `hermes-project-stewardship` at commit `f10e713` (v0.5.2), where
`desktop/plugin.js` is a git symlink (mode 120000). Git on Windows writes a symlink as a
43-byte text file holding the target, `../hermes_dockyard_plugin/desktop/plugin.js`, and
Desktop evaluates that text as JavaScript. The plugin's later commit `687bb03` ships a
real 1.6 MB file that passes `node --check`. Fix: `hermes plugins remove
hermes-project-stewardship`, then reinstall from the repository URL (check
`hermes plugins install --help` for the argument form), or `hermes plugins disable
hermes-project-stewardship`. `node scripts/gateway-doctor.js` reports this stub, and a
sticky `active_profile`, on the box; CI proves both detectors can fail.

**Keep only `default` and `seven6moa` (2026-10-19, on request).** Hermes cannot delete
`default`; every other profile and MoA preset can go. List first, then delete by name.
Profile deletion removes the profile directory and its gateway service and cannot be
undone, so export anything worth keeping first:

```powershell
hermes profile list
hermes profile export <name>          # optional backup, one per profile you might want back
hermes profile delete <name>          # asks you to type the name; repeat per extra profile
hermes moa list
hermes moa delete <preset>            # repeat per extra preset; keep the one this repo writes
```

This repo writes exactly one MoA preset, `default` (`moa.presets.default`), and CI
fails if `moa.default_preset` names a preset that is not there. Nothing in this repo
defines any other profile or preset, so the cleanup is on the machine, not in the files.

Not verified: how `seven6moa` became sticky. The retired swarm plan created the profile
but never ran `profile use`; Desktop may have switched to it. `hermes gateway run` is
already the foreground mode; there is no `--foreground` flag, and the sticky-profile file
is a plain-text `active_profile` (absent means `default`), not JSON.

---

## Super VL: known weak spots and what compensates

`nvidia/nemotron-3.5-super-vl-120b-a12b` is the primary. Its model card shows gaps on
terminal and repo-scale agentic coding (Terminal-Bench 2.1, DeepSWE, SWE-bench Pro),
instruction following and long-context retrieval against larger or more specialised
models. Against Ultra specifically, NVIDIA's tables put Super VL ahead on
BrowseComp, Terminal-Bench 2.1 and GPQA and behind on tau2-bench, IFBench and
SWE-bench Verified. Compensations shipped in this repo, each with its limit:

| Weak spot | Compensation | Limit |
|---|---|---|
| Per-request prompt weight (12B active, 131k window, ~40 RPM) | `.hermes.md` shadows `CLAUDE.md` for Hermes sessions run from the checkout: ~1.5 KB instead of ~9 KB. CI caps its size and bans Claude-Code-only tool names. | Only applies when the gateway or CLI starts inside the checkout. Hermes loads one project context file. |
| MCP tool definitions in every request | `tools.tool_search` is pinned `on`. Hermes already defers every `mcp-*` tool and a curated cold list by default, so this pins the behaviour rather than creating it. All 8 servers set `prompts: false` and `resources: false`, which removes 4 utility tools per server from the catalog. | Listing budget numbers are Hermes defaults, not tuned: nothing here measured them. Verified against upstream main on 2026-10-19; the installed Hermes version is unconfirmed (`hermes config check` shows whether it knows the key). |
| Terminal-heavy, repo-scale coding | Route it to `codex_exec` (the Codex MCP shim). See `codex-handoff.md`. | A policy hypothesis from the model card's gaps. The shim has never run against a real `codex` binary. |
| Instruction following on the acting turn | Ultra (IFBench 82.9 vs 70.86 for Super VL) advises as one of five references; it no longer acts. | An adviser's text is input to Super VL, not a guarantee. |
| Long-context degradation | Compaction threshold 0.70 for Super VL (Ultra's key stays for /model use), and `context_length` held at 131072 until measured. | The model card's 1M figure is not an endpoint measurement. |

Resolved 2026-10-20, on request: Super VL aggregates and Ultra advises, as one of five references.

### Candidates, unverified

Carried over from the retired swarm plan. None is wired, and none was checked against
a real Hermes install.

- **NemoClaw** — NVIDIA's open-source sandbox for always-on agents (kernel isolation,
  network policy, privacy routing). Worth a spike before an agent touches secrets.
- **NIM model-free mode** — one generic container that builds an engine for a model you
  point it at. Needs a GPU host and an NGC login; unconfirmed that it takes GGUF-only repos.
- **TensorRT-LLM** — could replace llama.cpp for local serving; a serving-stack change,
  not a model swap.
- **RAG blueprint** — grounded retrieval over this repo's own docs for review agents.

---

## Removal log

2026-10-19 consolidation. Each file was read before deletion and its unique content
moved:

| Removed | Unique content went to |
|---|---|
| Earlier ordered handoffs (two) | The "why some steps can never be delegated" table → `HERMES-SELF-SETUP.md`; Codex-shim and `external_dirs` items → this file; MemoryCore/WhatsApp status and the MoA-as-spend-multiplier note → "Needs a human" §3 |
| Four unwired hook forwarders | Nothing to keep; `.claude/hooks/README.md` updated |
| Local-swarm design docs (two copies) | Four NVIDIA candidates, one line each, under "Candidates, unverified" below |
| An instincts file about a different repository | Nothing portable |

One hypothesis, not a fact: a
Hermes-4-14B quant at IQ4_XS was suggested as a stronger tool-caller than the 3B floor
for similar resident memory. Nobody verified that the model exists at that size or how
it calls tools. Check `ollama` and the Hugging Face repo before acting on it.

---

## Repo conventions

- Develop on a `claude/` branch and open follow-up work as a NEW PR; a merged PR cannot
  track new work, and stacking on merged commits re-proposes them. The repo's default
  branch is named `The-MDC`.
- Counts of skills, categories and MCP servers are derived from disk by
  `scripts/check-capabilities.py`. Do not hand-write them into prose.
- CI is `harness checks`, and as of 2026-09-22 it is the **only** check. The
  Cloudflare `Workers Builds` check that used to fail in 0s on every commit was
  disconnected; if it ever reappears, the integration has been re-attached and the
  fix is again on the Cloudflare or GitHub-App side, never in this repo.
- Product content has been removed from this repo entirely. It is the Hermes +
  Codex orchestration build and carries no company, branding or business figures.
- No key-shaped string may enter `config.yaml`; CI and the preflight both reject it.
- Verify before claiming. Several statements in this repo's history were plausible,
  confidently written, and wrong.
