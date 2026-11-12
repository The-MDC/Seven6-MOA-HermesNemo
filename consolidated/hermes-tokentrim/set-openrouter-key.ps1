param(
    [string[]]$Profiles = @('default', 'seven6moa'),
    [string]$Key,                 # one key; normally leave it out and paste at the hidden prompt (keeps the key out of shell history)
    [string]$FromFile,            # a text file holding one or more OpenRouter keys (any token starting sk-or-); each is tried in turn
    [switch]$ListOnly,            # with -FromFile: only count the candidates and show their line numbers, touch nothing
    [switch]$NoEnable             # install the key but leave the OpenRouter MoA voice (qwen3.5-122b) staged off
)
# Installs a REAL OpenRouter API key for Hermes and switches the staged OpenRouter slots on.
#
# Why this exists: on 2026-10-16 the OPENROUTER_API_KEY stored in the Hermes .env files turned out not to be an
# OpenRouter key (73 characters, but it does not start with sk-or-). Every OpenRouter call returned
# HTTP 401 "Missing Authentication header", and Hermes' fallback chain quietly answered from NVIDIA instead, which
# hid the problem. Seven6MOA therefore has these slots staged off until a valid key exists:
#   moa.reference_models  R3 qwen/qwen3.5-122b-a10b via OpenRouter   (enabled: false)
#   fallback_providers    #3 nvidia/nemotron-3-super-120b-a12b:free via OpenRouter  (fails instantly with 401, chain moves on)
#
# Usage (you run it; nothing here is run for you):
#   .\set-openrouter-key.ps1 -FromFile "$env:USERPROFILE\Desktop\List of API keys.txt"     # tries every sk-or- key in the file
#   .\set-openrouter-key.ps1                                                               # paste one key at a hidden prompt
#   .\set-openrouter-key.ps1 -FromFile "<file>" -ListOnly                                  # just count the candidates
# Each candidate is (1) checked with OpenRouter, (2) written to the profiles' .env with a backup, (3) proved through
# Hermes with a usage report (the model that really answered must be qwen/qwen3.5-122b-a10b, which only OpenRouter
# serves, so a silent fallback cannot pass). A candidate that fails any step is rolled back from its backup and the
# next one is tried. The first one that works stays. No key character is ever printed; the file is only read.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Join-Path $env:LOCALAPPDATA 'hermes'
function Get-HomeDir([string]$p) { if ($p -eq 'default') { $root } else { Join-Path $root "profiles\$p" } }
function Clean([string]$s) { $s.Trim().Trim('"').Trim("'").Trim() }

# 1) Show what is installed now (shape only, never the value)
foreach ($p in $Profiles) {
    $envFile = Join-Path (Get-HomeDir $p) '.env'
    if (-not (Test-Path $envFile)) { throw "Hermes profile '$p' not found at $(Get-HomeDir $p)" }
    $line = Get-Content $envFile | Where-Object { $_ -match '^\s*OPENROUTER_API_KEY\s*=' } | Select-Object -First 1
    $cur = if ($line) { Clean ($line -replace '^\s*OPENROUTER_API_KEY\s*=', '') } else { '' }
    '{0,-10} current OPENROUTER_API_KEY: {1}' -f $p, $(if (-not $cur) { 'none' } else { "$($cur.Length) characters, starts with sk-or-: $($cur.StartsWith('sk-or-'))" })
}

# 2) Collect the candidates (values stay in memory; only counts and line numbers are ever shown)
$cands = New-Object System.Collections.Generic.List[object]
if ($FromFile) {
    if (-not (Test-Path $FromFile)) { throw "File not found: $FromFile" }
    $lines = [IO.File]::ReadAllText($FromFile) -split "`r?`n"
    $seen = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($m in [regex]::Matches($lines[$i], 'sk-or-[A-Za-z0-9_\-]{16,}')) {
            if (-not $seen.ContainsKey($m.Value)) { $seen[$m.Value] = $true; $cands.Add([pscustomobject]@{ Key = $m.Value; Line = $i + 1 }) }
        }
    }
    "Found $($cands.Count) OpenRouter-style key(s) (text starting sk-or-) in the file, on line(s): $(($cands | ForEach-Object { $_.Line }) -join ', ')"
    if ($cands.Count -eq 0) { 'Nothing to try. Nothing was changed.'; return }
    if ($ListOnly) { return }
} else {
    if (-not $Key) {
        $sec = Read-Host 'Paste your OpenRouter API key (starts with sk-or-v1-; input is hidden)' -AsSecureString
        $Key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    }
    $Key = Clean $Key
    if ($Key -notlike 'sk-or-*') { 'That is not an OpenRouter API key (it must start with sk-or-). Nothing was changed.'; return }
    $cands.Add([pscustomobject]@{ Key = $Key; Line = 0 })
    $Key = $null
}

$want = 'qwen/qwen3.5-122b-a10b'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$winner = $null
for ($n = 0; $n -lt $cands.Count; $n++) {
    $c = $cands[$n]; $tag = "candidate $($n + 1) of $($cands.Count)" + $(if ($c.Line) { " (line $($c.Line))" } else { '' })

    # (1) does OpenRouter accept it?
    try {
        $r = Invoke-RestMethod -Uri 'https://openrouter.ai/api/v1/auth/key' -Headers @{ Authorization = "Bearer $($c.Key)" } -TimeoutSec 30
    } catch {
        $code = $null; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        "${tag}: rejected by OpenRouter (HTTP $code)"
        continue
    }
    "${tag}: accepted by OpenRouter. Label: $($r.data.label)   usage: $($r.data.usage)   limit: $(if ($null -eq $r.data.limit) { 'none' } else { $r.data.limit })   free tier: $($r.data.is_free_tier)"

    # (2) install with backups
    $bak = @{}
    foreach ($p in $Profiles) {
        $envFile = Join-Path (Get-HomeDir $p) '.env'
        $bak[$envFile] = "$envFile.bak-openrouter-$stamp-c$($n + 1)"
        Copy-Item $envFile $bak[$envFile]
        $t = [IO.File]::ReadAllText($envFile)
        if ($t -match '(?m)^\s*OPENROUTER_API_KEY\s*=') { $t = [regex]::Replace($t, '(?m)^\s*OPENROUTER_API_KEY\s*=.*$', { param($m) 'OPENROUTER_API_KEY=' + $c.Key }) }
        else { $t = $t.TrimEnd() + "`nOPENROUTER_API_KEY=" + $c.Key + "`n" }
        [IO.File]::WriteAllText($envFile, $t, (New-Object Text.UTF8Encoding($false)))
    }

    # (3) prove it end to end through Hermes
    $u = Join-Path $env:TEMP 'openrouter-check.json'
    if (Test-Path $u) { Remove-Item $u -Force }
    "${tag}: testing through Hermes (seven6moa -> custom:or-fallback -> $want), up to 2 minutes..."
    $proc = Start-Process hermes -ArgumentList @('-p', 'seven6moa', '--provider', 'custom:or-fallback', '-m', $want, '-z', '"Reply with the single word: ready"', '--usage-file', $u) -PassThru -WindowStyle Hidden
    if (-not $proc.WaitForExit(120000)) { taskkill /T /F /PID $proc.Id 2>&1 | Out-Null; "${tag}: test timed out." }
    $ok = $false
    if (Test-Path $u) { $j = Get-Content $u -Raw | ConvertFrom-Json; $ok = ($j.model -eq $want -and -not $j.failed); "${tag}: Hermes reports provider $($j.provider), model $($j.model), failed $($j.failed)" }
    Remove-Item $u -Force -ErrorAction SilentlyContinue
    if ($ok) { $winner = $n + 1; "${tag}: OpenRouter answered through Hermes. Keeping this key."; break }

    # roll back this candidate
    foreach ($f in $bak.Keys) { Copy-Item $bak[$f] $f -Force; Remove-Item $bak[$f] -Force }
    "${tag}: accepted by OpenRouter but Hermes did not answer from it. Rolled back."
}
foreach ($c in $cands) { $c.Key = $null }

if (-not $winner) {
    'No key worked, so no .env file was changed. If a key was accepted but Hermes did not answer from it, run:  hermes -p seven6moa auth list   and remove any stale openrouter entry (hermes auth remove openrouter <index>), then run this again.'
    return
}
foreach ($p in $Profiles) { "$p : key installed (backup: .env.bak-openrouter-$stamp-c$winner)" }

# 4) Switch the staged OpenRouter MoA voice on
if (-not $NoEnable) {
    $cfg = Join-Path (Get-HomeDir 'seven6moa') 'config.yaml'
    Copy-Item $cfg "$cfg.bak-openrouter-$stamp"
    $t = [IO.File]::ReadAllText($cfg)
    $rx = '(?m)(model: qwen/qwen3\.5-122b-a10b[ \t]*\r?\n[ \t]*enabled:)[ \t]*false'
    $cnt = [regex]::Matches($t, $rx).Count
    $t = [regex]::Replace($t, $rx, '$1 true')
    $t = $t.Replace('# STAGED OFF until a valid OpenRouter key is installed (see the MoA header above).', "# ENABLED $(Get-Date -Format yyyy-MM-dd) by set-openrouter-key.ps1 (valid OpenRouter key installed).")
    [IO.File]::WriteAllText($cfg, $t, (New-Object Text.UTF8Encoding($false)))
    "seven6moa MoA: qwen3.5-122b enabled in $cnt place(s) (flat list and the default preset). Backup: config.yaml.bak-openrouter-$stamp"
    hermes -p seven6moa moa list
}
"Done. Undo: restore the .bak-openrouter-$stamp* files over .env / config.yaml."
