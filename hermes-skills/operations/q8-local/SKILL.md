---
name: q8-local
description: "Use this skill when asked to download, set up, start, check or troubleshoot the local Q8+ models: Nemotron 3.5 Super VL 120B Q8_0 (fallback 3, provider llamacpp-supervl-q8), Nemotron 3 Ultra UD-Q8_K_XL (provider llamacpp-ultra-q8) and GLM-5.3-Flash Q8_0 (provider llamacpp-glm-q8), the last two being opt-in MoA references. It decides WHICH machine may download, because the files are 134 GB, 594 GB and 342 GB. Triggers on: q8, Q8_K_XL, supervl-q8, ultra-q8, glm-q8, local-q8, ggml-org Super VL GGUF, unsloth Ultra GGUF, GLM-5.3-Flash GGUF, ports 8082 8083 8084."
version: 1.0.0
author: "Written for this Hermes build"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Q8, llama.cpp, GGUF, Download, Tunnel, Fallback, MoA]
    category: operations
    related_skills: [qwen-local, local-desktop, hermes-orchestration]
---

# The local Q8+ models

Three models, three `llama-server` processes, three tunnels. The repo's scripts do the
work; your job is to run them on the right machine and report what they print.

| Key | Model | Files | Size | Port | Role |
|---|---|---|---|---|---|
| `supervl` | Nemotron 3.5 Super VL 120B, Q8_0 (there is no Q8_K_XL) | 3 | 133.7 GB | 8082 | fallback 3, vision kept |
| `ultra` | Nemotron 3 Ultra 550B, UD-Q8_K_XL, text only | 14 shards | 594.5 GB | 8083 | opt-in MoA reference |
| `glm` | GLM-5.3-Flash, Q8_0 + F16 projector | 8 shards + 1 | 342.1 GB | 8084 | opt-in MoA reference |

The aggregator is NOT any of these. It stays on hosted NIM, full size. Do not move it.

## Step 0: which machine are you on? Do this before any download

Memory needed is at least the file size plus KV cache; Unsloth puts 8-bit Ultra at about
600 GB and 8-bit GLM at about 350 GB. All three together are about 1,070 GB of files.

Check free disk where the files go (`df -h`) and total memory (`free -g`).

- **Disk free below the file size, or memory below it: STOP. Do not download here.** The 8 GB
  laptop cannot run any of these. Tell the user which box should do it and ask for its SSH
  target (`user@host`). Use `ssh <target> 'cd <repo> && bash scripts/...'` only after the
  user gives you one.
- Otherwise continue, one model at a time. Never start `all` without being asked: it is
  1,070 GB.

## 1. Download (resumable, verified)

```
terminal(command = "bash scripts/q8-local-fetch.sh supervl", background = true, pty = true)
```

Long, so a background command; poll it with `process`. Success is `OK      N file(s) verified`
(3, 14 or 9). Each file is checked for exact size, the GGUF magic bytes and sha256, against
a pinned Hugging Face commit. The script refuses first if the rest cannot fit on disk. No
token is needed.

- Interrupted? Run it again; it resumes. `--check` verifies without downloading.
- A `FAIL` line names the file. Report it. Retry once at most. **Never edit the sizes or
  hashes in the script to make it pass** - a mismatch means a corrupt file or a stale pin.

## 2. Serve

```
terminal(command = "bash scripts/q8-local-serve.sh supervl", background = true, pty = true)
```

It binds 127.0.0.1 only and refuses any other host. Each model has its own port, so all
three can run at once on a box big enough.

- `supervl --spec mtp` adds the MTP head. Untested on this model; default is no speculation.
- `ultra` has no speculation option: Unsloth says MTP is not supported for its GGUFs.
- `glm` needs a llama.cpp build with the GLM-5.3-Flash architecture. As far as Unsloth's page
  shows, that is their branch `glm5next/upstream`, not mainline. Set `LLAMA_SERVER` to that
  build. If the server exits with an unknown-architecture error, report it verbatim. Do not
  build or install llama.cpp unasked.
- Anything after `--` goes straight to `llama-server` (for example `-- -ts 1,1,1,1` to split
  across GPUs).

## 3. Tunnel (on the machine that runs Hermes)

```
terminal(command = "ssh -N -L 8082:127.0.0.1:8082 -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 <user>@<box>", background = true, pty = true)
```

Use 8083 and 8084 for Ultra and GLM. Needs the user's SSH key. Never type or ask for a
password in the terminal.

## 4. Check it

`pwsh -File scripts/hermes-verify.ps1 -Deep` prints one line per server:

| Line | Meaning |
|---|---|
| `ok  llamacpp-supervl-q8 lists '...-q8'` and `completed a request` | working |
| `warn  nothing listening on 127.0.0.1:8082` | tunnel closed - normal for fallback 3, not a failure |
| `..    llamacpp-ultra-q8 is not running` | opt-in reference, tunnel closed - the default state |
| `FAIL  ... answers but lists [...]` | server started without the `--alias` the config names |

## Using the local Ultra and GLM

They are advisers in `moa.presets.local-q8`, which nothing selects. To use it, set
`moa.default_preset: local-q8` and copy that preset's `reference_models` into the flat
`moa.reference_models` (CI requires the two shapes to match). What Hermes does when a
reference endpoint refuses the connection is undocumented, so close a tunnel and run one MoA
turn before relying on it. Do this in the repo's `configs/hermes/config.yaml` and apply it
with `scripts/hermes-apply.ps1`, never by editing the installed file.

## Rules

- The ids `nemotron-3.5-super-vl-120b-a12b-q8`, `nemotron-3-ultra-550b-a55b-q8` and
  `glm-5.3-flash-q8` are this gateway's aliases. NIM, OpenRouter and Hugging Face each
  have different ids for the same weights. Never copy one into another's slot.
- If a tunnel is down, that link is skipped and Hermes moves on. That is by design.
