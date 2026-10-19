# Handoff — current state of the Hermes/Codex build

**Update this file in place. Do not add another dated handoff.** Audits keep finding
documents that describe a retired topology as current, because each was written as a
point-in-time snapshot and then left. A living state file with one authoritative
version does not rot the same way. "What is true now" belongs here, and only here.
Anything that must survive a deletion is migrated into this file or into
`configs/hermes/config.yaml`'s inline comments first (see the removal log below).

Last updated: 2026-10-19 · Branch: `claude/seven6-moa-consolidate` (stacked on
`claude/nemotron-3.5-super-vl-primary`, PR #27) · Super VL is the primary; the
consolidation and its compensations for Super VL's weak spots are described under
"Super VL: known weak spots and what compensates".

---

## Orientation: read these, in this order

1. **This file** — state, open items, and what needs a human.
2. `VSCODE-QUICKSTART.md` — fast path: Ollama, the local floor model, and the cloud tiers.
3. `TAKEOVER.md` — the full six-phase bring-up, one success line per step.
4. `configs/hermes/config.yaml` — the config itself carries the reasoning inline.

`running-the-stack.md`, `kimi-k3-quants.md`, and `local-floor.md` (the retired
Kimi-K3-topology docs) were deleted 2026-09-27 as part of consolidating this repo
down to one current doc set. Their request-economics and rate-limit-bucket
reasoning is superseded by `configs/hermes/config.yaml`'s own inline comments on
the current topology, which restate the same arguments fresh against what
actually runs now.

---

## The architecture as committed

```
parent      custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   THE primary, 2026-10-19, on request
                                  ("the nemotron 3.5 Super VL should be the only gateway and inference")
subagents   custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   same model, same bucket
vision      custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b   pinned, never `auto`; it is a VL model
moa ref     custom:nvidia-nim    nvidia/nemotron-3.5-super-vl-120b-a12b
aggregator  custom:nvidia-nim    nvidia/nemotron-3-ultra-550b-a55b   (2026-10-19, on request)
                                  The ONE role that is deliberately not Super VL: 550B total / 55B
                                  active, TEXT-ONLY, the ACTING model on a MoA turn. Same provider as
                                  the reference, so CI enforces a different MODEL instead of a
                                  different provider. Not part of docs/hermes-moa-build/BUILD.md's
                                  swarm roster.
fallback 1  custom:or-fallback   qwen/qwen3.5-122b-a10b            429 escape, different bucket
fallback 2  custom:local         hf.co/unsloth/Llama-3_3-Nemotron-Super-49B-v1_5-GGUF:UD-Q8_K_XL   offline, full strength (ADDED 2026-10-19)
fallback 3  custom:local         hf.co/mradermacher/Hermes-3-Llama-3.2-3B-abliterated-GGUF:Q8_0
                                  last resort + the 5 light aux slots (swapped from hermes3:8b 2026-09-25)
unrouted    custom:anthropic-direct  claude-sonnet-5, Anthropic's OpenAI-compat endpoint: in providers:
                                  since 2026-09-25, wired into NOTHING; /model custom:anthropic-direct:claude-sonnet-5

auxiliary   5 slots -> Hermes-3-Llama-3.2-3B-abliterated:Q8_0   routing, classification,
                                                                  titles, approval, curator
            2 slots -> qwen/qwen3.5-122b-a10b      compression, web_extract
            1 slot  -> nvidia-nim                  vision (nemotron-3.5-super-vl-120b-a12b, was
                                                   ising-calibration-1.5-31b until 2026-10-19)
mcp         8 servers, 2 hosted (cloudflare, submcp) on an explicit CI allowlist;
            all 8 set prompts:false + resources:false (CI-enforced)
```

What changed on 2026-10-19, and what it cost:

- **One bucket.** Parent, subagents, MoA reference and vision share one ~40 RPM NIM key.
  `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` stays in the NIM picker and routes
  nowhere. The old fallback 1 (that nano on the same key) left the chain, because a 429
  on the parent hit it too.
- **No offline parent.** The 49B GGUF was the parent from 2026-09-28 and the MoA
  aggregator until 2026-10-19; it is now fallback 2 only. Offline work degrades through
  the chain instead of continuing at full strength, and MoA needs NIM.
- **Context length is unmeasured.** `providers.nvidia-nim.context_length` stays 131072.
  The model card says up to 1M; raise it only to what `scripts/nim-preflight.sh` reports.
- **Unverified claim to settle.** A forum report says the hosted endpoint once answered
  under a different model id than requested. `nim-preflight.sh` now warns when the reply
  names another model.
- **Fixed in passing.** `hermes-verify.ps1`, `hermes-report.ps1` and `nim-preflight.sh`
  still demanded the `hf-router` provider and `HF_TOKEN` removed on 2026-09-28, so the
  verify gate failed against a correct install.

History kept for context: DeepSeek and `hf-router` removed 2026-09-28; `local-vl` and
hermes3:8b removed 2026-09-25 (the 3B floor is text-only, so vision never had a local
replacement); `nvidia/llama-3.3-nemotron-super-49b-v1.5` dead, HTTP 410, EOL 2026-08-26.

Three structural rules hold this together. Breaking any one fails **silently**:

1. **Provider references must dodge `excluded_providers`.** `deepseek`, `openrouter`
   and `ollama` are all excluded, and exclusion matches every key a provider surfaces
   under. That is why the remaining entries are named `or-fallback` and `local`.
   Naming an excluded provider directly resolves to nothing and falls back to the
   main model — a bill and a latency change, no error.
2. **One model per bucket.** A slot may share the parent's provider only on the
   parent's exact model; only `vision` among the auxiliaries may; every
   `fallback_providers` link must be on a different endpoint from the parent. (Until
   2026-10-19 this read "subagents must not share the parent's provider".)
3. **No auxiliary slot may sit on `auto`.** `auto` means "use the main model", which
   puts side jobs on the parent's bucket. This is how `vision` was silently broken:
   left on `auto` from when the parent was Kimi-K3, which had vision, while the
   current parent is text-only.

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
  the disk is the open question, same class of gap as hermes3:8b's ever was.
  (The old llama-server/VL-projector item that used to sit here no longer
  applies -- that tier is retired, not just unverified.)
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
- **`nvidia/llama-3.3-nemotron-super-49b-v1.5` was never actually live -- this is
  now resolved, not open.** Added 2026-09-25 as fallback_providers[0] and
  `nvidia-nim`'s own `default_model` (subagents/delegation, MoA aggregator),
  replacing nemotron-3-super-120b-a12b on request. This item used to say
  "neither use is live-verified... corroborated by three independent resellers,
  not first-party" — that corroboration was wrong. A real Hermes session on this
  NIM account hit the id live via `/moa` on 2026-09-27 and got back HTTP 410
  Gone, end-of-life 2026-08-26T09:00:00Z: it had been dead for a month.
  Replaced everywhere in `config.yaml` with `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning`,
  which answered live in the same fan-out. Lesson for the next model swap in this
  file: `nim-preflight.sh --list` is one command and would have caught this
  immediately -- run it, don't triangulate against resellers.
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
- **`docs/hermes-moa-build/BUILD.md`** — the local-swarm design doc (`seven6moa`
  profile, Kanban pattern, future candidates). Its banner says it is unwired design.
  Keep as a design record or delete; nothing in the live config depends on it.
- **`scripts/inventory-local-models.ps1`** — a read-only utility that lists what
  Ollama holds against what the config expects. Nothing links to it; run it before
  trusting a "model is pulled" claim.
- **MoA is a spend multiplier.** It makes at least two inference calls per turn
  (references advise once per user turn, then the aggregator acts), on one ~40 RPM
  NIM bucket. Defensible for hard problems, a bad default. Keep it behind the
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

Not verified: how `seven6moa` became sticky. `docs/hermes-moa-build/BUILD.md` creates the
profile but does not run `profile use`; Desktop may have switched to it. Also unverified
and probably wrong in that doc as first written: its `profile create` flags
(`--workspace_path`, `--initial_status`), which are not `profile create` flags in the
Hermes source. Corrected there. `hermes gateway run` is already the foreground mode;
there is no `--foreground` flag, and the sticky-profile file is a plain-text
`active_profile` (absent means `default`), not JSON.

---

## Super VL: known weak spots and what compensates

`nvidia/nemotron-3.5-super-vl-120b-a12b` is the primary. Its model card shows gaps on
terminal and repo-scale agentic coding (Terminal-Bench 2.1, DeepSWE, SWE-bench Pro),
instruction following and long-context retrieval against larger or more specialised
models. Against the Ultra aggregator specifically, NVIDIA's tables put Super VL ahead on
BrowseComp, Terminal-Bench 2.1 and GPQA and behind on tau2-bench, IFBench and
SWE-bench Verified. Compensations shipped in this repo, each with its limit:

| Weak spot | Compensation | Limit |
|---|---|---|
| Per-request prompt weight (12B active, 131k window, ~40 RPM) | `.hermes.md` shadows `CLAUDE.md` for Hermes sessions run from the checkout: ~1.5 KB instead of ~9 KB. CI caps its size and bans Claude-Code-only tool names. | Only applies when the gateway or CLI starts inside the checkout. Hermes loads one project context file. |
| MCP tool definitions in every request | `tools.tool_search` is pinned `on`. Hermes already defers every `mcp-*` tool and a curated cold list by default, so this pins the behaviour rather than creating it. All 8 servers set `prompts: false` and `resources: false`, which removes 4 utility tools per server from the catalog. | Listing budget numbers are Hermes defaults, not tuned: nothing here measured them. Verified against upstream main on 2026-10-19; the installed Hermes version is unconfirmed (`hermes config check` shows whether it knows the key). |
| Terminal-heavy, repo-scale coding | Route it to `codex_exec` (the Codex MCP shim). See `codex-handoff.md`. | A policy hypothesis from the model card's gaps. The shim has never run against a real `codex` binary. |
| Instruction following on the acting turn | The MoA aggregator is Ultra (IFBench 70.86 for Super VL, 82.9 for Ultra). | Ultra is text-only and on the same NIM bucket. |
| Long-context degradation | Compaction threshold 0.70 for Super VL and Ultra, and `context_length` held at 131072 until measured. | The model card's 1M figure is not an endpoint measurement. |

Open question owned by the user: swap the aggregator and reference roles
(Super VL aggregates, Ultra advises) or keep Ultra as the acting model.

---

## Removal log

2026-10-19 consolidation, each file read before deletion and its unique content moved:

| Removed | Why | Unique content went to |
|---|---|---|
| `HANDOFF.md` | Old ordered bring-up for a retired topology (told you to rename the repo the wrong way, referenced PR #16, steps B2/B3/D2 retired) | The "why some steps can never be delegated" table → `HERMES-SELF-SETUP.md`; Codex-shim and `external_dirs` items → this file |
| `handoff-2026-09-22.md` | Dated drift record for a topology that no longer exists | MemoryCore/WhatsApp status, MoA-as-spend-multiplier note → "Needs a human" §3 above; the hermes-council wrong-diagnosis record already lives in `config.yaml` |
| `.claude/hooks/session-start.js`, `session-end.js`, `pre-compact.js`, `stop.js` | Unwired forwarders to Cursor hooks that never existed here | Nothing to keep; `.claude/hooks/README.md` updated |
| `.claude/instincts/ecc-instincts.yaml` | Eight instincts about a different repository (`everything-claude-code`) | Nothing portable |

Earlier precedent: `running-the-stack.md`, `kimi-k3-quants.md` and `local-floor.md` were
deleted 2026-09-27 the same way.

One decision from the old local-floor note is kept as a hypothesis, not a fact: a
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
