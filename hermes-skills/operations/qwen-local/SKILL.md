---
name: qwen-local
description: "Use this skill when asked to download, set up, start, check or troubleshoot the local Qwen3.8-27B Q8_0 model that backs fallback 3 (provider llamacpp-qwen): fetching its four GGUF files, starting llama-server, opening the SSH tunnel, or testing whether the local Qwen answers. It decides WHICH machine may do the download, because the model does not fit a small laptop. Triggers on: qwen local, qwen3.8, llamacpp-qwen, download qwen, GGUF, llama-server, mmproj, MTP, DFlash, fallback 3, tunnel, port 8081."
version: 1.0.0
author: "Written for this Hermes build"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [Qwen, llama.cpp, GGUF, Download, Tunnel, Fallback]
    category: operations
    related_skills: [local-desktop, hermes-orchestration]
---

# The local Qwen3.8-27B (fallback 3)

Qwen3.8-27B at Q8_0 is fallback 3, served by `llama-server` and reached at
`http://127.0.0.1:8081/v1` through an SSH tunnel. Four files, about 34.4 GB, from
`ggml-org/Qwen3.8-27B-GGUF`: the model, the vision projector (`mmproj`), the MTP head
and the DFlash drafter. The repo's scripts do the work; your job is to run them on the
right machine and report what they print.

## Step 0: which machine are you on? Do this before any download

The model needs about 34.4 GB of disk and, at the full 262,144-token window, roughly
49 GB of memory (28.6 GB weights + 0.6 + 3.2 for the sidecars + about 16 GB of KV cache).

Check this machine: free disk where the files will go, and total memory
(`free -g` on Linux, `(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory` in
PowerShell).

- **Under 64 GB of memory: STOP. Do not download here.** The 8 GB laptop cannot run
  this model, and 34 GB of unusable files is the worst outcome. Tell the user the
  download belongs on their big box and ask for its SSH target (`user@host`). Run
  steps 1 and 2 there with `ssh <target> 'cd <repo> && bash scripts/...'` only after
  the user gives you that target.
- 64 GB or more and 40 GB of free disk: continue on this machine.

## 1. Download (resumable, verified)

```
terminal(command = "bash scripts/qwen-local-fetch.sh", background = true, pty = true)
```

It is long, so it must be a background command; poll it with `process`. The success
line is `OK      all 4 files verified`. Each file is checked for exact size, the GGUF
magic bytes and sha256, against a pinned Hugging Face commit. No token is needed.

- Interrupted? Run it again; it resumes. `--check` verifies without downloading.
- A `FAIL` line names the file. Report it. Retry once at most. **Never edit the sizes
  or hashes in the script to make it pass** - a mismatch means a corrupt file.

## 2. Serve

```
terminal(command = "bash scripts/qwen-local-serve.sh", background = true, pty = true)
```

Default is MTP speculative decoding; `--spec dflash` or `--spec none` are the
alternatives (one at a time). It binds 127.0.0.1:8080 only and refuses any other host.
If its preflight says `llama-server` lacks a flag or is not installed, report that
verbatim and offer `--spec none`. Do not build or install llama.cpp unasked.

## 3. Tunnel (on the machine that runs Hermes)

```
terminal(command = "ssh -N -L 8081:127.0.0.1:8080 -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 <user>@<box>", background = true, pty = true)
```

Needs the user's SSH key. Never type or ask for a password in the terminal.

## 4. Check it

`pwsh -File scripts/hermes-verify.ps1 -Deep` prints a `llamacpp-qwen` line:

| Line | Meaning |
|---|---|
| `ok  llamacpp-qwen lists 'qwen3.8-27b-q8'` and `completed a request` | working |
| `warn  nothing listening on 127.0.0.1:8081` | tunnel closed - normal, not a failure |
| `FAIL  ... answers but lists [...]` | server started without `--alias qwen3.8-27b-q8` |

## Rules

- The id `qwen3.8-27b-q8` is this gateway's alias. OpenRouter's id for the same weights
  is `qwen/qwen3.8-27b`, a different provider. Never copy one into the other's slot.
- Change routing in the repo's `configs/hermes/config.yaml` and apply it with
  `scripts/hermes-apply.ps1`, never by editing the installed file
  (see `hermes-orchestration`).
- If the tunnel is down, fallback 3 is skipped and Hermes moves on. That is by design.
