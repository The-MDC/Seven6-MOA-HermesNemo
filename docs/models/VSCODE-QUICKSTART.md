# VS Code quickstart — local tier + cloud tiers, on Windows

The fast path. Gets the local floor model
(`hf.co/mradermacher/Hermes-3-Llama-3.2-3B-abliterated-GGUF:Q8_0`) and the cloud tiers working, and nothing else. The full
bring-up, including MCP servers, is `TAKEOVER.md`; this is the subset you need
before any of that matters.

**Nemotron 3.5 Super VL is the only primary model (2026-10-19, on request).** The
parent, subagents, MoA reference and vision all run `nvidia/nemotron-3.5-super-vl-120b-a12b`
on NVIDIA NIM, so the fast path is cloud-first again: `NVIDIA_API_KEY` is what makes
Hermes start. The MoA aggregator is the one other model: `nvidia/nemotron-3-ultra-550b-a55b`
on the same NIM key (text-only, 550B). The local Ollama models are failover only, not the
parent and not the aggregator, so §2.2 is needed for offline strength, not for MoA or a first reply.

Every step has a **success line**. A step is done when the output matches it —
not when the command exits without complaining. That distinction is the whole
reason this file is written out rather than improvised: a wrong chat template
still chats, and a dangling model reference still answers, just on the wrong model.

Total download: about 3.4 GB. Budget a few minutes on a normal connection. There is
no second local service to set up: no llama-server, no build-floor check, no
`--mmproj`.

---

## 0. VS Code

### 0.1 — Open a PowerShell terminal

`` Ctrl+` `` opens the panel. The dropdown on its right must say **PowerShell**,
not Command Prompt or Git Bash. Everything below is PowerShell syntax; the
backtick line-continuations silently break in cmd.

```powershell
$PSVersionTable.PSVersion.Major
```

**Success:** `5` or higher. If the number is `5`, everything here still works —
`7` is nicer but nothing below requires it.

### 0.2 — Get the repo

```powershell
cd $HOME
git clone https://github.com/The-MDC/seven6-hermes-moa.git
cd seven6-hermes-moa
```

**Success:** `git log -1 --oneline` prints a commit, and `.hermes.md` exists in the folder.

Then **File → Open Folder** on that directory, so the Claude Code extension picks
up `CLAUDE.md` and the repo's skills. Install the extension from the Marketplace
(search "Claude Code") if it is not there yet.

### 0.3 — Baseline

```powershell
pwsh -File scripts/hermes-verify.ps1 -Stage a
```

**Success:** it prints a verdict line. `FAILED` here is expected and fine — this
is a *baseline*, not a gate. Keep the output; you will compare at step 4.

If `pwsh` is not recognised, use `powershell` instead, or install PowerShell 7:
`winget install Microsoft.PowerShell`.

---

## 1. Ollama

### 1.1 — Install

```powershell
winget install Ollama.Ollama
```

Then **close and reopen the terminal** — `winget` does not refresh `PATH` in a
running shell, and this is the single most common reason the next step "fails".

```powershell
ollama --version
```

**Success:** a version prints.

### 1.2 — Confirm it is serving

```powershell
ollama list
```

**Success:** a table header prints, even with no rows.

If it hangs or errors, start the service in its own terminal with `ollama serve`
and leave it running.

---

## 2. Local models

### 2.1 — Support model

```powershell
ollama pull hf.co/mradermacher/Hermes-3-Llama-3.2-3B-abliterated-GGUF:Q8_0
```

~3.4 GB, verified against the Hugging Face repo directly (3,421,895,840 bytes).
Pulled straight from Hugging Face via Ollama's own `hf.co/` feature -- needs a
reasonably current Ollama; check `ollama --version` if the pull is rejected.
**Success:** `ollama list` shows the full tag above. Note it is an "abliterated"
(refusal-removed) fine-tune -- a real behavior change, not just a smaller
download, and it backs every slot below including `approval`.

This one model already unblocks five of the eight auxiliary slots — routing,
classification, tool selection, titles, curation.

### 2.2 — The 49B is no longer part of this build

The local 49B GGUF (~58.68 GB) was the parent from 2026-09-28 to 2026-10-19 and
fallback 2 after that. It was removed on 2026-10-19: the target machine has 8 GB of
RAM, and no hosted endpoint serves that model. Fallback 2 is now
`nvidia/nemotron-3.5-lightning-30b-a3b` on NVIDIA NIM (§3), which needs no download.

If you only want Hermes conversing, you can stop after 2.1 and §3: the parent is
on NIM.

## 3. Cloud tiers

**Nothing here is installed locally.** These are all API-only. This step is
keys and a file.

### 3.1 — Create the env file

```powershell
$envFile = Join-Path $env:LOCALAPPDATA 'hermes\.env'
New-Item -ItemType File -Path $envFile -Force | Out-Null
$envFile
```

### 3.2 — Add the keys

Open it in VS Code — `code $envFile` — and add two lines. **Paste the values in
the editor, never into a terminal**, so they do not land in shell history:

```
NVIDIA_API_KEY=nvapi-...
OPENROUTER_API_KEY=sk-or-v1-...
```

| key | from | serves |
|---|---|---|
| `OPENROUTER_API_KEY` | openrouter.ai/keys | **fallback 1 + heavy aux** — Qwen3.5-122B-A10B |
| `NVIDIA_API_KEY` | build.nvidia.com | **the primary: parent + subagents + MoA reference + vision** — nemotron-3.5-super-vl-120b-a12b |

`NVIDIA_API_KEY` is strictly required for Hermes to start. Missing
`OPENROUTER_API_KEY` makes that tier fail over silently rather than error,
which is why step 4 checks it explicitly.

**Optional fourth key**, only if you want Claude reachable from inside Hermes:

```
ANTHROPIC_API_KEY=sk-ant-...
```

From console.anthropic.com/settings/keys. **Use a key dedicated to this
provider** — not whatever authenticates Claude Code or any other Anthropic
surface on this machine, or spend on one becomes invisible to the other, the
same failure this config already excludes `openai-codex` to prevent for
ChatGPT. Enables `anthropic-direct` — reachable via
`/model custom:anthropic-direct:claude-sonnet-5`, wired into nothing by
default. Its absence changes no other tier; skip it if you don't need Claude
inside Hermes specifically.

**Never put a key in `config.yaml`.** CI rejects key-shaped strings there, and
`hermes-verify.ps1` checks the installed copy too.

### 3.3 — Install the config

```powershell
cd $HOME\seven6-hermes-moa
pwsh -File scripts\hermes-apply.ps1 -WhatIf     # look first
pwsh -File scripts\hermes-apply.ps1
```

**Success:** `installed` lines for `config.yaml` and `config.toml`. Anything
already there is copied to `<name>.bak-<timestamp>` first — your existing config
is not destroyed, and any local edit survives in that backup.

---

## 4. Verify

### 4.1 — Local only

```powershell
pwsh -File scripts\hermes-verify.ps1 -Stage b
```

**Success:** both models report `present`, and Ollama answers on `127.0.0.1:11434`.

### 4.2 — The live check that matters

```powershell
pwsh -File scripts\hermes-verify.ps1 -Stage full -Deep
```

`-Deep` reads the keys from `.env` and makes one real request per provider. It
checks each provider's **catalog first**, then the completion — because a failed
completion alone cannot tell a wrong model id from an exhausted quota, and those
need opposite fixes.

**This is the step that answers the one thing CI structurally cannot:** whether
Ollama actually has the floor model loaded and serving (§2.1), whether
`nvidia/nemotron-3.5-lightning-30b-a3b` is callable with your NVIDIA key, and
whether `qwen/qwen3.5-122b-a10b` is actually on OpenRouter. Neither is
verifiable from the build container.

Three outcomes, three different meanings:

| Output | Means | Do |
|---|---|---|
| `catalog lists '<model>'` then `served '<model>'` | working | nothing |
| `catalog does NOT list '<model>'` | **the id is wrong for that provider** | use one of the nearest ids it prints; edit the repo config, re-run 3.3 |
| catalog lists it but the completion fails | quota, billing, or rate limit | check the provider dashboard — the config is right |
| `answered as '<other>', NOT the '<model>' we asked for` | **silent substitution** — a router quietly swapped models | pin the provider explicitly |

Report the `catalog does NOT list` case back before changing anything: choosing a
replacement model is a design decision, not a retry.

---

## What you have at this point

```
parent      nvidia-nim    nemotron-3.5-super-vl-120b-a12b      API only, the primary
subagents   nvidia-nim    nemotron-3.5-super-vl-120b-a12b      same model, same bucket
vision      nvidia-nim    nemotron-3.5-super-vl-120b-a12b      pinned; it is a VL model
moa ref     nvidia-nim    nemotron-3.5-super-vl-120b-a12b
aggregator  nvidia-nim    nemotron-3-ultra-550b-a55b       API only, text-only, the acting model on MoA turns
fallback 1  or-fallback   Qwen3.5-122B-A10B      API only, also 2 heavy aux slots
fallback 2  nvidia-nim    nvidia/nemotron-3.5-lightning-30b-a3b     API only; same bucket as the parent (model-level failover, not a 429 escape)
fallback 3  local         Hermes-3-Llama-3.2-3B-abliterated:Q8_0
                          last resort + 5 light aux slots
unrouted    anthropic-direct  claude-sonnet-5    configured, intact, via /model only
```

The total download is the 3.4 GB floor model.

Not covered here, deliberately: the seven MCP servers, `hermes-council`'s
dependency fault, and the Codex bridge handshake. None of them gate the model
tiers. `scripts\hermes-blockers.ps1` diagnoses the last two without changing
anything, and `TAKEOVER.md` phases 3–6 cover the rest.

**There is no separate vision tier to set up.** `vision` routes to
`custom:nvidia-nim` / `nvidia/nemotron-3.5-super-vl-120b-a12b`: the primary is a
vision-language model. Vision fails the way every cloud tier does, with no network.
