# Seven6MOA roster (2026-10-16)

One profile, `seven6moa`, now holds every LLM slot the six tier profiles used to hold. The tiers
(`codex-moa`, `local-floor`, `moa-aggregator`, `nim-subagents`, `nim-vision`, `or-fallback`) were
near-identical copies that differed by a handful of keys; those keys now live here, one slot each.
The tiers are archived in `local-llm\profile-archive\` and `retire-tier-profiles.ps1` deletes them.

Status words: **LIVE** = answered a real Hermes call today. **STAGED** = configured but switched off.
**WAITING** = configured, but needs a key that does not work yet. **INERT** = needs software that is not on this machine.

Launch: `hermes -p seven6moa` (it is also the sticky profile). MoA is off until you type `/moa <prompt>`
or run with `--provider moa -m default`.

## 1. Core roles

| Slot | Model | Provider | Settings | Came from | Status |
|---|---|---|---|---|---|
| Parent / acting model | `nvidia/nemotron-3.5-super-vl-120b-a12b` | NVIDIA NIM (`nvidia-nim`) | temp 1.0, top_p 0.95 (NVIDIA's setting for this model), `agent.reasoning_effort: max`, compaction at 0.65 of the window, stale tool results pruned at 48k tokens, file reads capped at 124000 chars | seven6moa (replaced Nemotron 3 Ultra) | LIVE |
| MoA aggregator | same model | `custom:nvidia-nim` | `aggregator_temperature` 1.0 | moa-aggregator | LIVE |
| Subagents (`delegate_task`) | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` | `custom:nvidia-nim` | temp 0.6, top_p 0.95 (NVIDIA's thinking-mode setting), 3 children at once; child fallback = Super 120B on NIM | nim-subagents | LIVE (hosted Omni sometimes answers 503 busy, hence the child fallback) |
| Vision (`vision_analyze`) | `nvidia/ising-calibration-1.5-31b` | `custom:nvidia-nim` | pinned, never `auto` | nim-vision | LIVE (read "CODE 4821" and the red rectangle from a test image) |

## 2. MoA panel (`/moa`)

All enabled references run once per user turn (`fanout: user_turn`) at `reference_temperature` 0.6 with a 120 s
timeout, then the aggregator answers. A reference that fails is reported (`degraded_reference_policy: loud`).

| # | Model | Provider | Came from | Status |
|---|---|---|---|---|
| R1 | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` | `custom:nvidia-nim` | nim-subagents | LIVE, intermittent (NVIDIA answers `503 ResourceExhausted (16/16)` at times) |
| R2 | `nvidia/nemotron-3-super-120b-a12b` | `custom:nvidia-nim` | moa-aggregator, or-fallback | LIVE |
| R3 | `qwen/qwen3.5-122b-a10b` | `custom:or-fallback` (OpenRouter) | every tier | STAGED OFF until OpenRouter has a working key. The same model is also listed live on Hugging Face's router (`Qwen/Qwen3.5-122B-A10B`, Novita and DeepInfra), which is the alternative once the HF token works |
| R4 | `qwen/qwen3.8-flash` | `custom:or-fallback` (OpenRouter) | or-fallback | STAGED OFF, same reason |
| R5 | `z-ai/glm-5.3` | `custom:nvidia-nim` | new, tested today | STAGED OFF. Answered in 29 s on its own, but a MoA turn with it on took 213 s against 49-59 s without it |
| R6 | `openai/gpt-oss-120b:cerebras` | `custom:hf-gptoss` (Hugging Face router, pinned to Cerebras) | new, requested 2026-10-16 ("go with gpt-oss-120B, best BF16") | WAITING. `reasoning_effort: high`. The first call returned HTTP 401: seven6moa's `.env` holds two HF_TOKEN lines and Hermes reads the rejected one first. Fix with `install-api-keys.ps1 -Only huggingface`, then `enable-gptoss-voice.ps1` (section 11) |

Also answering on your NVIDIA key: `google/gemma-4-31b-it` (23 s) and `openai/gpt-oss-20b` (24 s). Not served to your account
(HTTP 404): `moonshotai/kimi-k2.6`, `mistralai/mistral-large-2-instruct`, `qwen/qwen3.5-122b-a10b`.

## 3. Auxiliary slots

| Task | Model | Provider | Settings | Came from |
|---|---|---|---|---|
| compression (summaries) | `nvidia/nemotron-3-super-120b-a12b` | `custom:nvidia-nim` | thinking off (`chat_template_kwargs.enable_thinking: false`) | moa-aggregator |
| web_extract | `nvidia/nemotron-3-super-120b-a12b` | `custom:nvidia-nim` | thinking off | was or-fallback (OpenRouter qwen3.5), moved because that route returns 401 |
| triage_specifier (one-liner to spec) | `nvidia/nemotron-3-super-120b-a12b` | `custom:nvidia-nim` | thinking off | moa-aggregator |
| kanban_decomposer (task graph JSON) | `nvidia/nemotron-3-super-120b-a12b` | `custom:nvidia-nim` | thinking on | moa-aggregator (was Kimi-K2 on the removed HF router) |
| profile_describer | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` | `custom:nvidia-nim` | thinking off (tested: `hermes profile describe --auto` worked) | moa-aggregator |
| review (`/review` subagent) | `nvidia/nemotron-3-super-120b-a12b` | `custom:nvidia-nim` | | moa-aggregator |
| approval, curator, mcp, skills_hub, title_generation | `auto` (follows the parent) | | | the tiers pointed these at a 3B model on Ollama (not installed) or at the removed HF router, so `auto` is the working equivalent |

## 4. Fallback chain (parent failed or rate-limited)

The parent stays Super VL. When its call fails, Hermes tries these in order:

| Order | Model | Provider | Status |
|---|---|---|---|
| 1 | `nvidia/nemotron-3-super-120b-a12b` | `nvidia` (NIM) | LIVE. Your latest preference ("the super 120B is preferable"); a forced failure was answered by it. Shares the parent's NVIDIA bucket |
| 2 | `nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4` (the parent's own model, NVFP4 build) | `huggingface` (Baseten) | WAITING: needs a valid `HF_TOKEN` (see section 6). Different company's infrastructure, so it covers an NVIDIA outage or key problem |
| 3 | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` | `custom:nvidia-nim` | LIVE. Your earlier "make Omni the backup": a forced failure was answered by it as first backup. Hosted Omni is sometimes busy, which is why it moved down |
| 4 | `nvidia/nemotron-3-super-120b-a12b:free` | `custom:or-fallback` (OpenRouter) | WAITING: needs a working OpenRouter key; fails instantly with 401 until then |
| 5 | `spark` (Spark-X2.5 4B) | `custom:mylocal-router` (llama.cpp on 127.0.0.1:8080) | Offline floor, replaces local-floor. Needs `local-llm\run-mylocal.ps1` running; minutes per turn on this CPU |

Test note: forcing a failure with `--provider custom:nvidia-nim` skips entries on that provider (Hermes prunes the chain on a deliberate
provider switch), so use the real provider name `nvidia-nim` with a bogus model id, plus `--usage-file`, to see who answers.

## 5. Where each retired profile went

| Retired profile | What it was | Now |
|---|---|---|
| `codex-moa` | MOA-B local swarm (CodeLlama-13B, MiniCPM-3B, Mixtral-6x7B, Gemma-4 26B, local Ising) | INERT. Needs Ollama and 14 to 128 GB of pulls. The role table stays as comments in the `delegation:` block of `config.yaml` |
| `local-floor` | Offline floor on a 3B model via Ollama | Fallback 5, now on the llama.cpp router you can actually run |
| `moa-aggregator` | Aggregator plus kanban, review and profile helpers | Aggregator, MoA panel, and the helper slots in section 3 |
| `nim-subagents` | nano-omni children on their own bucket | `delegation:` block |
| `nim-vision` | Ising vision and swarm coordinator | `auxiliary.vision` |
| `or-fallback` | OpenRouter 429 escape and heavy aux | Fallback 4, R3, R4 (waiting on the OpenRouter key) |

## 6. Key audit (run `check-api-keys.ps1`; it prints no key characters)

| Provider | Hermes `.env` | Your key list | What to do |
|---|---|---|---|
| NVIDIA | valid (default, seven6moa) | valid (line 77, same key) | nothing |
| xAI | valid (default) | same key (line 26) | nothing |
| OpenRouter | REJECTED (HTTP 401) in default and seven6moa; this is why every OpenRouter slot failed | line 45 is that same dead key; **line 46 is valid** | `set-openrouter-key.ps1 -FromFile` (or `install-api-keys.ps1`) |
| Hugging Face | default: REJECTED. seven6moa: two `HF_TOKEN` lines, the first valid and the second (rejected) wins | line 39 valid (fine-grained, inference permission); line 40 rejected | `install-api-keys.ps1` installs line 39 and removes the duplicate line. (A script error printed both list tokens into one Claude session; you chose to keep using line 39. `-PromptFor huggingface` pastes a different token instead.) |
| Supermemory | not installed | **valid** (line 117) | `install-api-keys.ps1`, then the plugin steps it prints |
| OpenAI | not installed | the only OpenAI-format key (line 67) is REJECTED | needs a new key |
| WhatsApp | no key needed: seven6moa is set up for Hermes' phone-linked bridge (`WHATSAPP_ENABLED=true`, an allow-list is set, not yet paired) | line 121 came from the phone, not from Meta's Cloud API (rejected by Meta's Graph API, no phone number ID listed), so Hermes does not use it | run `hermes -p seven6moa whatsapp`, scan the QR code from the phone (Settings, Linked devices), then `hermes -p seven6moa gateway run`. `install-api-keys.ps1 -Only whatsapp` is only for the official Cloud API |
| Anthropic | REJECTED (default) | the same dead key (line 35) | needs a real `sk-ant-api...` key for `use-claude.ps1` |
| GitHub | not installed | valid fine-grained token (line 10) | optional `GITHUB_TOKEN` |
| Groq | not installed | valid (line 27) | not used by any profile |
| 32 other tokens | | Cloudflare, Render, OpenCode, AWS-style, SSH and client secrets | not Hermes keys, not checked |

## 7. Other caveats

- **Fallbacks hide failures.** To see which model really answered, add `--usage-file out.json` to a one-shot and read `model` and `provider`.
  Earlier today I reported OpenRouter as working because the chain had answered from NVIDIA; the usage report is how I caught it.
- **Lightning (Nemotron 3.5 Lightning 30B-A3B)** took 93 s for a one-line summary, timed out at 101 s on another call and returned
  empty once. Removed from `default`; not used here. **Ultra** stalled on the hosted endpoint and was removed earlier.
- **Times** in the README include roughly 25 to 45 s of Hermes start-up on this laptop.
- The private `The-MDC/Seven6-Hermes-MOA` repo is not readable from here, so its personas and `BUILD.md` were not checked. Four Seven6 MCP
  servers (`hermes-skills`, `hermes-council`, `codex-mcp`, `atomicmemory`) fail to start in every session because their launcher
  variables are unset or the package is missing.

## 8. Parked: Darwin-180B

`FINAL-Bench/Darwin-180B-RSI-R3` is a Qwen-3.8-derived mixture-of-experts (180B total, about 3B active, 262k context). The quant you mean
is `FINAL-Bench/POCKET-Darwin-180B-GGUF`: 4-bit, 111 GB in 4 files, for llama.cpp (a recent build; the maker used b11048). It is not
listed by NVIDIA NIM, by Hugging Face's inference router, or by OpenRouter (checked their public model lists), so no hosted API can
serve it. The maker's own claims: about 4 tokens/s on a laptop with an 8 GB GPU and 32 GB RAM, 18 to 21 tokens/s on a 16-thread server
CPU. This laptop (7.9 GB RAM, no GPU) cannot run it usefully. To use it you would need a machine with roughly 32 GB RAM and a fast
111 GB SSD, or rented hardware. Nothing was installed or downloaded.

## 9. Changing a slot

```powershell
hermes -p seven6moa config set delegation.model <model-id>          # subagents
hermes -p seven6moa config set auxiliary.compression.model <id>     # any auxiliary task: auxiliary.<task>.model / .provider
hermes -p seven6moa moa configure                                   # MoA slots (interactive)
hermes -p seven6moa fallback list                                   # show the chain
.\swap-model.ps1 -Old <id> -New <id> -Profiles seven6moa -WhatIf   # replace a model everywhere it appears
```

Turn the GLM voice on: change `enabled: false` to `true` on the `z-ai/glm-5.3` entry in both the flat `reference_models` list and the
`default` preset of `moa:` in `%LOCALAPPDATA%\hermes\profiles\seven6moa\config.yaml`, then check with `hermes -p seven6moa moa list`.

## 10. Second pass: MCP, gateway, tools, plugins (2026-10-16)

**MCP servers.** `hermes doctor --live` found 8 of 9 unable to connect. Each is now `enabled: false` in `config.yaml` with the reason on its line; flip it to `true` once the condition is met.

| Server | Result | Why | To re-enable |
|---|---|---|---|
| open-websearch | works: 6 tools, about 30 s for the first connect | | already enabled (3 tools exposed) |
| voicebox | timeout | Voicebox app not running (nothing on :17493 or :17600) | start Voicebox |
| crawl4ai | timeout | nothing on :11235; Docker is not installed | run Crawl4AI |
| atomicmemory | timeout | the npm package never connects | use Supermemory instead |
| hermes-skills, hermes-council, codex-mcp | WinError 2 or timeout | their launchers ship in the Seven6-Hermes-MOA repo, which is not stored on this machine, and the `HERMES_*` variables are unset | run them from a copy of the repo elsewhere, or use a catalog plugin (below) |
| cloudflare | HTTP 401 on both transports | needs OAuth | `hermes -p seven6moa mcp login cloudflare` |
| submcp | TLS error | the host no longer presents a valid certificate | none, the endpoint looks dead |

**Gateway.** WhatsApp (phone-linked bridge) is the live platform: `WHATSAPP_ENABLED=true`, an allow-list is set, self-chat mode by default, Node 24 present, not yet paired. Google Chat is switched off with `platforms.google_chat.enabled: false`: its `.env` values were placeholders (project and subscription one character each, service-account file missing, home channel the word "whatsapp") and the Pub/Sub package is not installed. The gateway was not started during this review because starting it can message your channels.
Note for later: the `whatsapp` platform toolset includes terminal, file, code_execution, computer_use and browser, so anyone who can message the bridge can drive this PC. Self-chat mode limits that to your own number; trim the list if you ever widen access.

**Web tools.** `web_search` (ddgs) works. `web_extract` works even though `extract_backend: firecrawl` is pinned with no key (Hermes falls back to its keyless tier); it read huggingface.co. `example.com` does not resolve on this network (DNS answers "no such host"), so do not use it as a test page.

**Providers and limits.** NVIDIA model card for Super VL: up to 1M tokens of context, text temperature 1.0 / top_p 0.95, vision 0.6 / 0.95, reasoning switchable with `enable_thinking`. Hermes' catalog lists 8,192 output tokens for it, but a 3,347-token answer finished normally. The config keeps `context_length: 131072` (compaction near 85k tokens) on purpose; a too-large value costs a rejected request. Nano Omni: 256k context. The stale provider-level `model:` (an old Llama-Nemotron 253B) was corrected to Super VL.

**SOUL.md.** A 223-word "Seven6 operating charter" was appended (ask at most three clarifying questions before major generative work, verify before asserting, delegate independent work, never print keys, no local repo clones). The system prompt grew from 12.5 KB to 13.9 KB. Undo: copy `SOUL.md.bak-20261016` over `SOUL.md` in the profile folder.

**Plugins.** None installed. The catalog has 541 community plugins (third-party code), so nothing is installed without your say-so. Worth considering: `prompt-enhance` (rewrites your draft in the composer so you see it before sending; no hooks), the `hermes-council` plugin (a `council_deliberate` tool with four advisor seats and a chairman, borrowing your providers; up to 2N+1 model calls per use, so heavy on NVIDIA's shared rate limit; it replaces the dead council MCP without needing the private repo), and `supermemory` after its key is installed. Not recommended: `prompt-optimizer` (one extra model call on every message), `evalroute`, `fusion`.

**Housekeeping.** The six launcher stubs of the deleted profiles moved to `local-llm\profile-archive\orphan-aliases`. The stale auxiliary comment block was replaced. Backups: `config.yaml.bak-mcp-*`, `SOUL.md.bak-20261016`.

**Hermes doctor leftovers (not fixable here).** npm advisories in Hermes' bundled browser and UI tooling need an upstream lockfile bump; Docker/Podman, python-telegram-bot and discord.py are optional and absent; Nous, Codex, MiniMax and xAI OAuth logins are not set up; `image_gen`, `tts`, `a2a`, `connections` and `browser-cdp` report unmet dependencies; no `GITHUB_TOKEN` means the Skills Hub is limited to 60 requests an hour.

## 11. Night additions (2026-10-16): gpt-oss voice, Chrome DevTools MCP, trim plugin, smoke test

**gpt-oss-120b as MoA voice R6 (staged, waiting for the Hugging Face token).** You asked for gpt-oss-120B "in the best BF16".
- OpenAI shipped it with the MoE weights in MXFP4 (about 4.25 bits) and the rest in BF16. The BF16 repos on the Hub (`lmsys/gpt-oss-120b-bf16`, `unsloth/gpt-oss-120b-BF16`) are lossless upcasts of the same numbers (about 234 GB), so BF16 hosting does not add accuracy; the risk is a host that re-quantizes (fp8, int4).
- Hosts on the Hugging Face router today: Groq, Novita, Cerebras, nscale, Together, Fireworks, Featherless, Scaleway, Baseten, OVHcloud. OpenRouter's precision tags (self-reported): bf16 = AkashML, Crusoe, DeepInfra, DekaLLM (none on the HF router); fp16 = Cerebras; fp4 = BaseTen, CoreWeave, Near AI, Nebius, Novita, Parasail; fp8 = Mancer, SiliconFlow; int4 = Venice; unstated = Bedrock, Google, Groq, Together and others.
- Configured: provider `custom:hf-gptoss` (the HF router, `key_env: HF_TOKEN`, context declared as 131,072) with the model pinned to Cerebras (`openai/gpt-oss-120b:cerebras`): the closest thing to BF16 on the HF router (16-bit tag; its docs say a 16/8/4-bit mix, the same shape as OpenAI's release) and the fastest (about 1,150 tokens/s, 0.2 s to first token), so the 120 s reference timeout is no issue. `reasoning_effort: high`. About 0.35 / 0.75 USD per million tokens, billed to the Hugging Face account. Entry R6 in the flat list and in the default preset, `enabled: false`.
- Literal BF16 later: needs a working OpenRouter key and an OpenRouter provider preference `quantizations: ["bf16"]`, which routes only to the four BF16 hosts. Not set up.
- Why it is off: the first call returned HTTP 401. seven6moa's `.env` holds two HF_TOKEN lines (one rejected, one valid) and Hermes read the rejected one; the fallback chain answered instead, which the usage report exposed. `hermes auth list` shows the credential marked "auth failed (401)".
- To turn it on, in this order (each one is a single command):
  1. `install-api-keys.ps1 -Only huggingface` leaves one valid HF_TOKEN line in both profiles.
  2. `enable-gptoss-voice.ps1` clears the 401 mark, proves gpt-oss-120b through Hermes (the usage report must name it; a Nemotron answer counts as failure), then flips R6 on in both places with a config backup. `-ProveOnly` and `-Disable` also exist.
  3. `seven6-smoke.ps1 -Checks moa` should then list gpt-oss among the answering references.

**Chrome page "Build extensions with coding agents".** MCP server `chrome-devtools` added as `enabled: false` (pinned `chrome-devtools-mcp@1.11.0`, 16 of its 57 tools, no `--autoConnect`; reasons in the config comment). The two Modern Web Guidance skills were blocked by Hermes's own scanner and not forced: `modern-web-guidance` (CAUTION, 16 findings in documentation samples, installable only with `--force`) and `chrome-extensions` (DANGEROUS, 4 findings, not installable even with `--force`). Detail and the decision are in RESEARCH section 7.5.

**seven6-trim plugin.** `plugins\seven6-trim` uses the `transform_tool_result` hook to measure, and optionally shorten, big tool results. Observe mode by default; it logs tool name, sizes and milliseconds only. Tested: 21 unit tests pass; `hermes plugins validate` is green on all 15 checks (security scan "safe", no core override); live on a throwaway clone it logged a 2,362-character `web_search` result as `skip:small` in observe mode, and in trim mode with tiny limits it cut a 2,434-character result to 1,178 (-51.6%) and the model quoted the trim marker back. NOT installed in your live profile: run `install-seven6-trim.ps1`, restart Hermes, use it for a while, then `seven6-trim-report.ps1`. Switch on with `hermes -p seven6moa config set plugins.entries.seven6-trim.settings.mode trim`. Undo with `install-seven6-trim.ps1 -Remove`.

**seven6-smoke.ps1.** Four hard-capped checks, each proven from the usage report, the session database or the MoA trace (no model grades another). Last run on config hash `fcfc74ac`: all four PASS: one-shot 49 s (Super VL answered), fallback 68 s (wrong model rejected, Super 120B answered, chain entry 1 of 5), delegation 67 s (`delegate_task` once, child on nano-omni), MoA 111 s (both references answered, aggregator Super VL). That run is the stored baseline in `smoke-results.jsonl`.
First full run caveats: the MoA check once failed because hosted nano-omni answered busy; busy or timed-out providers now report ERROR instead of FAIL, so they never read as a regression. Free RAM was under 1 GB while Hermes Desktop was open, so run it with other Hermes windows closed.

**SOUL.md.** One sentence added to the verify rule: "When MoA advisors disagree, name the disputed claim and the check that settles it." Undo: copy `SOUL.md.bak-evidence-20261016` over `SOUL.md`. The charter already required confirmed / assumed / unknown labels, so nothing else was needed.

**Third scan (9 repos + 12 collections).** Verdicts in RESEARCH section 8. Order: fix the HF token and enable gpt-oss, observe with seven6-trim, then trial context-mode or xerj in a throwaway clone only if the numbers justify it; Superpowers by cherry-picking skills; scientific skills for named domains only.