<#
.SYNOPSIS
  Verify a deployed Hermes install against configs/hermes/config.yaml.

.DESCRIPTION
  Answers one question: does the machine actually match what the repo says?

  CI can only check the config FILE. It cannot see whether `hermes` is installed,
  whether Ollama holds the models the config names, or whether an endpoint
  answers. Every silent failure recorded in docs/models/HANDOFF-NEXT-SESSION.md was
  of that second kind: a reference that is valid on paper and dangling on disk.

  Read-only. Changes nothing, starts nothing, prints no secret.

.EXAMPLE
  pwsh -File scripts/hermes-verify.ps1
  pwsh -File scripts/hermes-verify.ps1 -Deep     # also calls the remote endpoints
#>
[CmdletBinding()]
param(
    # Which bring-up phase to check. The stack comes up in stages, and a stage
    # gate that fails on something the NEXT stage installs is a gate nobody can
    # pass -- so each stage only requires what it was supposed to deliver.
    #
    #   a     the local floor model only (Hermes-3-Llama-3.2-3B-abliterated:Q8_0).
    #   b     adds the Codex bridge. (Vision routes to the cloud.)
    #   full  everything, including the hosted MCP servers. (default)
    [ValidateSet('a', 'b', 'full')]
    [string]$Stage = 'full',

    # Also make one live request per remote provider. Costs a few tokens and
    # proves the key works, which no local check can.
    [switch]$Deep,

    # Profiles whose config.yaml must follow the repo copy: drift in one is a FAILURE.
    # Every other profile is checked too, but its drift is only a warning, because a
    # profile such as `mylocal` may differ on purpose. A key a profile does not set is
    # never drift -- it inherits. Pass @() to make every profile advisory.
    [string[]]$StrictProfiles = @('seven6moa')
)

. (Join-Path $PSScriptRoot 'hermes-common.ps1')
$StrictProfiles = @(Split-NameList $StrictProfiles)   # -File delivers "a,b" as one string

$ErrorActionPreference = 'Continue'
$script:Fail = 0
$script:Warn = 0

function Section($t) { Write-Host "`n$t" -ForegroundColor Cyan }
function Ok($m)      { Write-Host "  ok    $m" -ForegroundColor Green }
function Warn($m)    { Write-Host "  warn  $m" -ForegroundColor Yellow; $script:Warn++ }
function Fail($m)    { Write-Host "  FAIL  $m" -ForegroundColor Red;    $script:Fail++ }
function Info($m)    { Write-Host "  ..    $m" -ForegroundColor DarkGray }

Write-Host "verifying stage '$Stage'" -ForegroundColor Cyan

$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME }
              else { Join-Path $env:LOCALAPPDATA 'hermes' }
$ConfigPath = Join-Path $HermesHome 'config.yaml'
$EnvPath    = Join-Path $HermesHome '.env'

# ---------------------------------------------------------------- toolchain
Section 'toolchain'

$hermes = Get-Command hermes -ErrorAction SilentlyContinue
if ($hermes) { Ok "hermes: $((& hermes --version 2>&1 | Select-Object -First 1))" }
else { Fail 'hermes not on PATH - nothing below can be trusted' }

$ollama = Get-Command ollama -ErrorAction SilentlyContinue
if ($ollama) {
    $ov = (& ollama --version 2>&1 | Out-String).Trim()
    # `ollama --version` exits 0 and prints a "could not connect" warning when the
    # server is down. A client that is installed is not a server that is running.
    if ($ov -match 'could not connect|Warning') { Warn "ollama client present, server not running: $(($ov -split "`n")[0])" }
    else { Ok "ollama: $(($ov -split "`n")[0])" }
}
else { Fail 'ollama not on PATH - the local tier and 5 auxiliary slots have no backend' }

$codex = Get-Command codex -ErrorAction SilentlyContinue
if ($codex) { Ok "codex: $((& codex --version 2>&1 | Select-Object -First 1))" }
elseif ($Stage -eq 'a') { Info 'codex not on PATH - not required until stage b' }
else { Warn 'codex not on PATH - delegation to Codex will fail, everything else is fine' }

# ---------------------------------------------------------------- config
Section 'config'

if (-not (Test-Path $ConfigPath)) {
    Fail "no config at $ConfigPath - run scripts/hermes-apply.ps1 first"
} else {
    $raw = Get-Content $ConfigPath -Raw
    Ok "config present: $ConfigPath"

    # The three provider keys every reference in the repo config resolves through.
    # A rename here is the exact failure that dangles every custom: reference.
    foreach ($p in @('nvidia-nim', 'or-fallback', 'local')) {
        if ($raw -match "(?m)^\s{2}$([regex]::Escape($p))\s*:") { Ok "provider '$p' defined" }
        else { Fail "provider '$p' is MISSING - every custom:$p reference dangles" }
    }

    # An inline key here would be committed-shaped and is the repo's one hard rule.
    # Match the shape, never print the match.
    $keyLeak = $false
    foreach ($shape in @('nvapi-[A-Za-z0-9_\-]{20,}', 'hf_[A-Za-z0-9]{30,}',
                         'sk-or-v1-[A-Za-z0-9]{20,}')) {
        if ($raw -match $shape) {
            Fail "config.yaml contains something shaped like a live key - rotate it, then move it to .env"
            $keyLeak = $true
        }
    }
    # Gated on THIS scan, not on $script:Fail. It used to read
    # `if ($script:Fail -eq 0)`, so any unrelated earlier failure -- `hermes` not
    # on PATH is enough -- silently swallowed the clean result. A security check
    # that goes quiet for a reason having nothing to do with security is worse
    # than one that is simply absent: the reader sees no line and cannot tell
    # whether it passed, failed, or never ran.
    if (-not $keyLeak) { Ok 'no key-shaped string in config.yaml' }

    # Render carried an inline bearer token in an earlier revision of this file.
    if ($raw -match '(?m)^\s{2}render\s*:') {
        Warn 'render MCP is present - it failed DNS repeatedly and once held an inline token. Confirm the token was rotated.'
    } else { Ok 'render MCP absent, as intended' }
}

if (-not (Test-Path $EnvPath)) {
    Fail "no .env at $EnvPath - every remote provider reads its key from there"
} else {
    $envRaw = Get-Content $EnvPath -Raw
    # NVIDIA_API_KEY is the PRIMARY model's key (nemotron-3.5-super-vl-120b-a12b);
    # without it there is no primary and everything runs on failover.
    foreach ($k in @('NVIDIA_API_KEY', 'OPENROUTER_API_KEY', 'HF_TOKEN')) {
        # Presence only. The value is never read, printed, or length-checked.
        if ($envRaw -match "(?m)^\s*$k\s*=\s*\S") { Ok "$k is set" }
        else { Warn "$k not set - the tier that uses it will fail over" }
    }
    # ANTHROPIC_API_KEY is not one of the three above ON PURPOSE: nothing in
    # config.yaml is wired to anthropic-direct, so its absence breaks nothing.
    # Reported as information, not a warning -- a warning here would train
    # someone to "fix" a gap that costs the stack nothing.
    if ($envRaw -match "(?m)^\s*ANTHROPIC_API_KEY\s*=\s*\S") {
        Ok 'ANTHROPIC_API_KEY is set (anthropic-direct - unwired, available via /model)'
    } else {
        Info 'ANTHROPIC_API_KEY not set - anthropic-direct unusable, nothing else affected'
    }
}

# ---------------------------------------------------------------- drift
# CI checks the repo copy; this checks the file Hermes reads. `hermes update` and
# `hermes dashboard` migrate the config format on their own (v0 -> v51 did), a UI
# model pick can land in a profile's config.yaml, and hermes-apply.ps1 writes the root
# config only -- each leaves a file that parses, loads, and routes somewhere else.
# The logic lives in scripts/check-config-drift.py, which has its own tests.
Section 'config drift (installed vs repo copy)'

$RepoRoot  = Split-Path $PSScriptRoot -Parent
$Golden    = Join-Path $RepoRoot 'configs/hermes/config.yaml'
$DriftTool = Join-Path $PSScriptRoot 'check-config-drift.py'

function Show-Drift($r) {
    foreach ($line in ($r.Output -split "`r?`n")) {
        if (-not $line.Trim()) { continue }
        if     ($line -match '^\s+FAIL') { Write-Host $line -ForegroundColor Red }
        elseif ($line -match '^\s+warn') { Write-Host $line -ForegroundColor Yellow; $script:Warn++ }
        elseif ($line -match '^\s+ok')   { Write-Host $line -ForegroundColor Green }
        else                             { Write-Host $line -ForegroundColor DarkGray }
    }
}

if (-not (Test-Path $Golden))    { Fail "repo copy missing: $Golden - run this from a full checkout" }
elseif (-not (Test-Path $DriftTool)) { Fail "drift tool missing: $DriftTool" }
elseif (-not (Test-Path $ConfigPath)) { Info 'no installed config to compare (already reported above)' }
else {
    $py = Find-YamlPython
    if (-not $py) {
        # A warning, not silence: "did not run" must never read as "passed".
        Warn 'config drift NOT checked - no Python with PyYAML found. Set HERMES_DRIFT_PYTHON to one, or run: py -3 -m pip install pyyaml'
    } else {
        $r = Invoke-DriftCheck -Python $py -Tool $DriftTool -Golden $Golden -Installed $ConfigPath -Label 'root config'
        Show-Drift $r
        if ($r.Code -eq 1) { Fail 'root config drifted from the repo copy - see above. Restore with hermes-apply.ps1 (it backs up first), or fold the change into configs/hermes/config.yaml' }
        elseif ($r.Code -ne 0) { Fail 'root config could not be read or parsed - drift is unknown' }

        $profileRoot = Join-Path $HermesHome 'profiles'
        $dirs = @(Get-ChildItem $profileRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
        if (-not $dirs) { Info "no profiles under $profileRoot" }
        foreach ($d in $dirs) {
            $pc = Join-Path $d.FullName 'config.yaml'
            if (-not (Test-Path $pc)) { Info "profile '$($d.Name)': no config.yaml (inherits the root config)"; continue }
            $strict = $StrictProfiles -contains $d.Name
            $r = Invoke-DriftCheck -Python $py -Tool $DriftTool -Golden $Golden -Installed $pc -Label "profile '$($d.Name)'" -Profile -Strict:$strict
            Show-Drift $r
            if ($r.Code -eq 1) { Fail "profile '$($d.Name)' failed the routing check - see above" }
            elseif ($r.Code -ne 0) { Fail "profile '$($d.Name)' config could not be read or parsed" }
        }
    }
}

# Portable TCP reachability check.
#
# REPLACES Test-NetConnection, which is Windows-only. HANDOFF-NEXT-SESSION.md lists
# it under "Assumed, NOT verified" as a code path that has never executed -- and off
# Windows it does not fail cleanly, it throws "term not recognized" straight to
# stderr while the surrounding logic carries on. TcpClient ships with .NET core and
# behaves identically on every platform, so these two checks can now be exercised in
# a container and in CI rather than only on the target box. One fewer assumption.
function Test-Port($hostname, $port, $timeoutMs = 2000) {
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $async  = $client.BeginConnect($hostname, $port, $null, $null)
        $opened = $async.AsyncWaitHandle.WaitOne($timeoutMs, $false)
        if ($opened) {
            # WaitOne returning true only means the wait ended; EndConnect is what
            # distinguishes an accepted connection from a refused one.
            try { $client.EndConnect($async) } catch { $opened = $false }
        }
        $client.Close()
        return $opened
    } catch { return $false }
}

# ---------------------------------------------------------------- local models
Section 'local models (Ollama)'

if ($ollama) {
    $port = Test-Port '127.0.0.1' 11434
    if (-not $port) {
        # Probe the port BEFORE `ollama list`: with the server down, `list` can hang
        # or print an error, and either one hid every line below it.
        Fail 'nothing listening on 127.0.0.1:11434 - run `ollama serve`; the local floor model and 5 light aux slots are unreachable'
        $tags = ''
    } else {
        Ok 'Ollama answering on 127.0.0.1:11434'
        $tags = (& ollama list 2>&1 | Out-String)
    }
    # These names must match `providers.local.models` in the repo config exactly.
    # A tag mismatch is not a loud failure: Hermes resolves the miss by falling
    # back to the main model, so you get an answer from the wrong tier.
    #
    # Ollama carries the whole local tier; vision routes to the cloud, so there is no
    # second local server to check.
    if ($port) {
        foreach ($m in @('hf.co/mradermacher/Hermes-3-Llama-3.2-3B-abliterated-GGUF:Q8_0')) {
            if ($tags -match [regex]::Escape($m)) { Ok "$m present" }
            else {
                Fail "$m NOT in Ollama - config.yaml names it, so selecting it silently falls back. Pull it with: ollama pull $m"
            }
        }
    }
}

# ---------------------------------------------------------------- MCP
Section 'MCP servers'

if ($hermes) {
    $mcpOut = (& hermes mcp list 2>&1 | Out-String)
    $expected = switch ($Stage) {
        'a'  { @('crawl4ai', 'atomicmemory') }
        'b'  { @('crawl4ai', 'atomicmemory', 'hermes-skills') }
        default { @('voicebox', 'crawl4ai', 'atomicmemory', 'hermes-skills',
                    'hermes-council', 'cloudflare', 'submcp', 'codex-mcp') }
    }
    foreach ($s in $expected) {
        if ($mcpOut -match [regex]::Escape($s)) { Ok "$s registered" }
        else { Warn "$s not listed by 'hermes mcp list'" }
    }
    # hermes-council's failure was interpreter substitution by the supervisor,
    # NOT a missing dependency -- see configs/hermes/config.yaml. Fixed by
    # pointing `command` at a launcher that pins the interpreter. If it is
    # erroring again, check which interpreter is actually being used before
    # touching any package version.
    if ($mcpOut -match 'hermes-council' -and $mcpOut -match '(?i)error|failed|unsupported') {
        Warn 'hermes-council is erroring - check WHICH interpreter it ran under (scripts/hermes-blockers.ps1) before suspecting packages'
    }
    # Upstream optional skills this build DEPENDS on, declared in capabilities.yaml's
    # `upstream_skills` section. They ship with Hermes rather than with this repo, so
    # check-capabilities.py cannot see them -- it only walks this tree. The box is the
    # only place the question "is it actually enabled?" has an answer, so it is asked
    # here. Warn rather than Fail: each one is a capability gap, not a broken install.
    if ($Stage -ne 'a') {
        $skillOut = (& hermes skills list 2>&1 | Out-String)
        $upstream = @{
            'searxng-search'             = 'web.search_backend is searxng and nothing teaches its use'
            'mcporter'                   = 'the only way to diagnose a silently-filtered MCP server'
            'subagent-driven-development' = 'delegation and moa are configured but untaught'
        }
        foreach ($s in $upstream.Keys) {
            if ($skillOut -match [regex]::Escape($s)) { Ok "upstream skill $s enabled" }
            else { Warn "upstream skill $s NOT enabled - $($upstream[$s])" }
        }
    }

    # Same check, one runtime over. config.yaml names this launcher as codex-mcp's
    # command, and an unset variable means the server never starts -- which surfaces
    # as the Codex tools simply being absent, not as an error.
    if (-not $env:HERMES_CODEX_LAUNCHER) {
        Warn 'HERMES_CODEX_LAUNCHER not set - config.yaml names it as codex-mcp''s command'
    } elseif (-not (Test-Path $env:HERMES_CODEX_LAUNCHER)) {
        Fail "HERMES_CODEX_LAUNCHER points at a missing file: $env:HERMES_CODEX_LAUNCHER"
    } else { Ok 'codex-mcp launcher present' }

    if (-not $env:HERMES_COUNCIL_LAUNCHER) {
        Warn 'HERMES_COUNCIL_LAUNCHER not set - config.yaml names it as hermes-council''s command'
    } elseif (-not (Test-Path $env:HERMES_COUNCIL_LAUNCHER)) {
        Fail "HERMES_COUNCIL_LAUNCHER points at a missing file: $env:HERMES_COUNCIL_LAUNCHER"
    } else { Ok 'council launcher present' }
}

# The Codex MCP bridge. WARN, not FAIL, and the demotion is the point.
#
# `Unsupported` here is PERMANENT and not a fault of this install. Codex 0.154.0
# removed the `codex mcp-server` entry point on 2026-09-05; the replacement,
# `codex app-server`, speaks its own JSON-RPC 2.0 protocol and is not an MCP
# server. Codex is an MCP *client* now. No handshake exists to succeed.
#
# This used to raise Fail, which made the whole script unpassable: TAKEOVER.md
# phase 6.1 asks for `OK no failures` as the final gate, and on any box with
# codex on PATH that verdict could never be reached. A gate that cannot go green
# stops being read -- and then it hides the failures that ARE real. Worse, this
# script contradicted scripts/hermes-blockers.ps1, which already recommends
# option (a): do nothing, because delegation does not use this interface.
#
# Hermes reaches Codex as a SUBPROCESS via the bundled `codex` skill
# (docs/models/codex-handoff.md). That path is unaffected and is the supported
# one. Do not "fix" this by setting model.openai_runtime: codex_app_server --
# that routes Hermes' own reasoning through Codex and creates a second, invisible
# consumer of the same ChatGPT 5-hour window, which is exactly what
# `openai-codex` sits in excluded_providers to prevent.
#
# Gated on stage because line 26 says codex is not required until stage b, and
# this check ran at stage a regardless.
if ($codex -and $Stage -ne 'a') {
    $codexOut = (& codex mcp list 2>&1 | Out-String)
    if ($codexOut -match '(?i)unsupported') {
        Warn 'codex mcp list reports Unsupported - EXPECTED. The interface was removed upstream (Codex 0.154.0, 2026-09-05); Codex is MCP-client-only now. Delegation runs as a subprocess and is unaffected. Not a blocker, and not fixable here'
    } elseif ($codexOut -match 'hermes') { Ok 'codex bridge handshake OK' }
    else { Warn 'no hermes entry in codex mcp list - delegation uses the subprocess path, so this is informational' }
}

# ---------------------------------------------------------------- endpoints
if ($Deep) {
    Section 'endpoints (live, one request each)'

    # Keys live in $HERMES_HOME\.env, which Hermes reads at runtime -- they are
    # NOT normally exported into an interactive shell. Reading only the process
    # environment meant -Deep skipped every probe on a correctly configured box
    # and reported it as "not set", which looks like a finding and is not one.
    function Get-ProviderKey($keyVar) {
        $v = [Environment]::GetEnvironmentVariable($keyVar)
        if ($v) { return $v }
        if (Test-Path $EnvPath) {
            foreach ($line in Get-Content $EnvPath) {
                if ($line -match "^\s*$([regex]::Escape($keyVar))\s*=\s*(.+?)\s*$") {
                    return $Matches[1].Trim('"').Trim("'")
                }
            }
        }
        return $null
    }

    # Two questions, and one request cannot answer both. A failed completion looks
    # identical whether the model id is wrong or the account is out of quota, so
    # the catalog is checked FIRST: it isolates "this id does not exist here",
    # which is the failure this repo keeps hitting and CI cannot see.
    function Probe($name, $url, $keyVar, $model, $CatalogAuthHeader = 'Authorization', $CatalogAuthPrefix = 'Bearer ') {
        $key = Get-ProviderKey $keyVar
        if (-not $key) { Warn "$name skipped - $keyVar not in the environment or $EnvPath"; return }
        $auth = @{ Authorization = "Bearer $key" }

        # The completions leg below always uses Bearer -- every OpenAI-compatible
        # gateway this file talks to accepts it there, confirmed live per provider
        # (see config.yaml). The CATALOG leg is not always the same endpoint under
        # the same rules: Anthropic's /chat/completions accepts Bearer, but its
        # /models is the NATIVE Models API and answered a Bearer token with
        # "invalid x-api-key" when tested live 2026-09-25 -- it wants the raw key
        # under x-api-key, no prefix. $CatalogAuthHeader/$CatalogAuthPrefix exist
        # for exactly that split; every other caller omits them and gets the
        # original Bearer-everywhere behavior unchanged.
        $catalogAuth = @{ $CatalogAuthHeader = "$CatalogAuthPrefix$key" }

        try {
            $cat = Invoke-RestMethod -Method Get -Uri "$url/models" -Headers $catalogAuth -TimeoutSec 30
            $ids = @($cat.data | ForEach-Object { $_.id })
            if ($ids -contains $model) {
                Ok "$name catalog lists '$model' ($($ids.Count) models visible to this key)"
            } else {
                Fail "$name catalog does NOT list '$model' - the id is wrong for this provider, not a quota problem ($($ids.Count) models visible)"
                $near = @($ids | Where-Object { $_ -match 'deepseek|nemotron' } | Select-Object -First 5)
                if ($near) { Info "closest ids here: $($near -join ', ')" }
            }
        } catch {
            Warn "$name catalog unreadable: $($_.Exception.Message)"
        }

        try {
            $body = @{ model = $model
                       messages = @(@{ role = 'user'; content = 'ping' })
                       max_tokens = 1 } | ConvertTo-Json -Depth 5
            $r = Invoke-RestMethod -Method Post -Uri "$url/chat/completions" `
                    -Headers $auth -ContentType 'application/json' `
                    -Body $body -TimeoutSec 60
            # Echo the id the endpoint RETURNED, not the one we asked for: a router
            # that silently substitutes a model is invisible any other way.
            if ($r.model -and $r.model -ne $model) {
                Warn "$name answered as '$($r.model)', NOT the '$model' we asked for - silent substitution"
            } else {
                Ok "$name served '$($r.model)'"
            }
        } catch {
            Fail "$name did not answer for '$model': $($_.Exception.Message)"
        }
    }

    # Read the endpoint and the model id OUT OF THE CONFIG BEING VERIFIED rather
    # than restating them here.
    #
    # Two copies of one fact can each be fixed without the other: correcting
    # config.yaml alone would leave this script probing a stale id and reporting
    # green.
    #
    # There is one copy, and it is the one Hermes actually reads.
    #
    # Deliberately NOT a YAML parser. It reads two scalars out of a known block
    # shape and FAILS when it cannot find them. Falling back to a literal on a parse
    # miss would rebuild the exact hazard this replaces -- and a silent fallback is
    # the bug class this whole file exists to catch.
    function Get-ProviderField($provider, $field) {
        $lines = Get-Content $ConfigPath
        $start = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s{2}$([regex]::Escape($provider))\s*:\s*$") { $start = $i; break }
        }
        if ($start -lt 0) { return $null }
        for ($i = $start + 1; $i -lt $lines.Count; $i++) {
            # A key at column 0 or 2 ends this provider's block. Everything that
            # belongs to it -- including its comments -- is indented 4.
            if ($lines[$i] -match '^\s{0,2}\S') { break }
            if ($lines[$i] -match "^\s{4}$([regex]::Escape($field))\s*:\s*(\S+)\s*$") {
                return $Matches[1]
            }
        }
        return $null
    }

    function Probe-Configured($name, $keyVar, $CatalogAuthHeader = 'Authorization', $CatalogAuthPrefix = 'Bearer ') {
        $url   = Get-ProviderField $name 'api'
        $model = Get-ProviderField $name 'default_model'
        if (-not $url -or -not $model) {
            Fail "could not read providers.$name (api / default_model) from $ConfigPath - refusing to guess; a probe against a guessed id proves nothing"
            return
        }
        Info "$name -> $model @ $url"
        Probe $name $url $keyVar $model $CatalogAuthHeader $CatalogAuthPrefix
    }

    Probe-Configured 'nvidia-nim'  'NVIDIA_API_KEY'
    Probe-Configured 'or-fallback' 'OPENROUTER_API_KEY'
    # Fallback 2. Its /models answers 200 for a bad token, so the one-token chat inside
    # Probe is the only leg that can fail on a bad HF_TOKEN.
    Probe-Configured 'hf-fallback' 'HF_TOKEN'
    # Present only if the key is set -- absence is fine (see the toolchain
    # section above), so this stays silent rather than warning about a tier
    # nothing depends on.
    if (Get-ProviderKey 'ANTHROPIC_API_KEY') {
        Probe-Configured 'anthropic-direct' 'ANTHROPIC_API_KEY' 'x-api-key' ''
    }

    # Fallbacks 3 and 4 and the two opt-in MoA references: the llama.cpp servers behind
    # SSH tunnels. No key, and ADVISORY on purpose: a closed tunnel is a normal state (the laptop was closed, the big box is
    # off), and a gate that fails on a normal state is a gate no install can pass. A
    # dead tunnel makes Hermes skip the link; it does not break the install. What IS a
    # failure is a server that answers but does not serve the alias the config names.
    #   $role       what is skipped while the tunnel is down, for the warning text
    #   $remotePort the port llama-server binds on the big box (the tunnel's far end)
    #   $serveCmd   the command that starts the server with the alias the config names
    #   $optIn      the two MoA-preset-only servers: a closed tunnel is the DEFAULT state,
    #               so it is reported as info, not a warning; an open one is probed in full
    function Probe-Tunnel($name, $role, $remotePort, $serveCmd, $optIn = $false) {
        $url   = Get-ProviderField $name 'api'
        $model = Get-ProviderField $name 'default_model'
        if (-not $url -or -not $model) {
            Fail "could not read providers.$name (api / default_model) from $ConfigPath - refusing to guess"
            return
        }
        Info "$name -> $model @ $url"
        $u = [Uri]$url
        if (-not (Test-Port $u.Host $u.Port)) {
            if ($optIn) {
                Info "$name is not running ($role; tunnel closed). Fine unless moa.presets.local-q8 is selected: ssh -N -L $($u.Port):127.0.0.1:${remotePort} <user>@<big-box>"
            } else {
                Warn "nothing listening on $($u.Host):$($u.Port) - $role is skipped until the tunnel is open: ssh -N -L $($u.Port):127.0.0.1:${remotePort} <user>@<big-box>"
            }
            return
        }
        try {
            $cat = Invoke-RestMethod -Method Get -Uri "$url/models" -TimeoutSec 10
            $ids = @($cat.data | ForEach-Object { $_.id })
            if ($ids -contains $model) { Ok "$name lists '$model'" }
            else { Fail "$name answers but lists [$($ids -join ', ')], not '$model' - start the server with --alias $model ($serveCmd)" }
        } catch {
            Warn "$name accepted the connection but /models is unreadable: $($_.Exception.Message) (is the server behind the tunnel running?)"
            return
        }
        try {
            $body = @{ model = $model; messages = @(@{ role = 'user'; content = 'ping' }); max_tokens = 1 } | ConvertTo-Json -Depth 5
            $r = Invoke-RestMethod -Method Post -Uri "$url/chat/completions" -ContentType 'application/json' -Body $body -TimeoutSec 120
            if ($r.choices) { Ok "$name completed a request (served as '$($r.model)')" }
            else { Fail "$name answered a completion with no choices" }
        } catch {
            Fail "$name did not complete a request for '$model': $($_.Exception.Message)"
        }
    }
    Probe-Tunnel 'llamacpp-supervl-q8' 'fallback 3' 8082 'scripts/q8-local-serve.sh supervl'
    Probe-Tunnel 'llamacpp-qwen'       'fallback 4' 8080 'scripts/qwen-local-serve.sh'
    Probe-Tunnel 'llamacpp-ultra-q8'   'the opt-in Ultra reference' 8083 'scripts/q8-local-serve.sh ultra' $true
    Probe-Tunnel 'llamacpp-glm-q8'     'the opt-in GLM reference'   8084 'scripts/q8-local-serve.sh glm' $true
}

# ---------------------------------------------------------------- verdict
Write-Host ''
if ($script:Fail -gt 0) {
    Write-Host "FAILED  $($script:Fail) failure(s), $($script:Warn) warning(s)" -ForegroundColor Red
    Write-Host 'Do not route production work through this install until the failures above are cleared.'
    exit 1
}
Write-Host "OK      no failures, $($script:Warn) warning(s)" -ForegroundColor Green
exit 0
