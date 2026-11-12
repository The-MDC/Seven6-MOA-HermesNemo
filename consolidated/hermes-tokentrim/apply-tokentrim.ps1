param(
    [Parameter(Mandatory)][string]$ProfileName,
    # everyday     : the 'default' recipe (all five parts)
    # orchestrator : Seven6MOA-style profile - keeps every selected model, delegate_task stays eager, leaves compression/delegation/aux alone
    # local        : CPU-bound llama.cpp profile - only a small read cap (nothing else can be trimmed without costing re-prefill time)
    [ValidateSet('everyday', 'orchestrator', 'local')][string]$Preset = 'everyday',
    [string]$NimProvider = 'nvidia',        # NVIDIA NIM provider id in THIS profile ('nvidia' in default; 'custom:nvidia-nim' in seven6moa)
    [string]$NimSmallModel = 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',   # subagents. (Lightning 3.5 was the first pick; measured 93 s / timeout vs 41 s on 2026-10-16)
    [string]$NimCompressionModel = 'nvidia/nemotron-3-super-120b-a12b',          # summaries: fastest model that answered (29 s); thinking switched off below
    [string]$Keep = 'pdf,docx,xlsx,powerpoint,github,claude-code,deep-research',   # skills that stay individually indexed (plus the most-used per .usage.json)
    [switch]$SkipSuites
)
# Token-trim bundle for one Hermes profile. Every file it edits is backed up first (config.yaml.bak-tokens-* / bak-superskills-* / bak-pre-trim-*).
#   1) tools.tool_search.defer : rarely used big tool schemas load on demand through tool_search instead of being sent every request
#   2) memory provider off     : an external memory provider (if one is active and its store is unused)
#   3) context controls        : prune stale tool results (48k), cap one file read
#   4) delegation + compression: subagents pinned to nano-omni (medium reasoning, NVIDIA thinking-mode sampling); summaries pinned to Super 120B with thinking off
#   5) skill suites            : one router skill per category (originals stay on disk, only leave the index); see README.md
$d = $PSScriptRoot
$homeDir = if ($ProfileName -eq 'default') { Join-Path $env:LOCALAPPDATA 'hermes' } else { Join-Path $env:LOCALAPPDATA "hermes\profiles\$ProfileName" }
$cfg = Join-Path $homeDir 'config.yaml'
if (-not (Test-Path $cfg)) { throw "Hermes profile '$ProfileName' not found at $homeDir" }

# preset -> switches
$doTools = $true; $doMemory = $true; $doPrune = $true; $doCompressCap = $true; $doDelegation = $true; $doAux = $true; $doSuites = (-not $SkipSuites)
$keepEager = @(); $exclude = ''; $readCap = '124000'
switch ($Preset) {
    'orchestrator' { $keepEager = @('delegate_task'); $exclude = 'seven6'; $doCompressCap = $false; $doDelegation = $false; $doAux = $false; $doMemory = $false }
    'local'        { $doTools = $false; $doMemory = $false; $doPrune = $false; $doCompressCap = $false; $doDelegation = $false; $doAux = $false; $doSuites = $false; $readCap = '8000' }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item $cfg "$cfg.bak-pre-trim-$stamp"
"profile $ProfileName  preset $Preset  (full-config backup: config.yaml.bak-pre-trim-$stamp)"
& "$d\psize.ps1" -ProfileName $ProfileName -Label "BEFORE $ProfileName"

if ($doTools) {
    "--- 1) tool deferral" + $(if ($keepEager.Count) { " (kept eager: $($keepEager -join ', '))" } else { '' })
    $lines = [IO.File]::ReadAllLines("$d\tools-block.yaml") | Where-Object { $l = $_; -not ($keepEager | Where-Object { $l -match ('^\s+-\s+' + [regex]::Escape($_) + '\s*$') }) }
    $tmp = Join-Path $env:TEMP "tools-block-$ProfileName.yaml"
    [IO.File]::WriteAllLines($tmp, $lines, (New-Object Text.UTF8Encoding($false)))
    & "$d\yamlblock.ps1" -ProfileName $ProfileName -TopKey tools -BlockFile $tmp
    Remove-Item $tmp -Force
}
if ($doMemory) {
    "--- 2) memory provider"
    hermes -p $ProfileName memory off 2>&1 | Out-String
}
"--- 3/4) scalar settings"
$sets = [ordered]@{ 'file_read_max_chars' = $readCap }
if ($doPrune)       { $sets['compression.proactive_prune_tokens'] = '48000' }
if ($doCompressCap) { $sets['compression.threshold_tokens'] = '90000' }
if ($doDelegation)  { $sets['delegation.provider'] = $NimProvider; $sets['delegation.model'] = $NimSmallModel; $sets['delegation.reasoning_effort'] = 'medium'; $sets['delegation.max_concurrent_children'] = '3'
                      $sets['delegation.request_overrides.temperature'] = '0.6'; $sets['delegation.request_overrides.top_p'] = '0.95' }
if ($doAux)         { $sets['auxiliary.compression.provider'] = $NimProvider; $sets['auxiliary.compression.model'] = $NimCompressionModel
                      $sets['auxiliary.compression.extra_body.chat_template_kwargs.enable_thinking'] = 'false' }
foreach ($k in $sets.Keys) {
    $r = hermes -p $ProfileName config set $k $sets[$k] --force 2>&1 | Out-String
    ('{0,-38} = {1,-40} {2}' -f $k, $sets[$k], $(if ($r -match 'Set ') { 'ok' } else { 'CHECK: ' + $r.Trim() }))
}
if ($doSuites) {
    "--- 5) skill suites"
    $args_ = @('-I', "$d\build_superskills.py", '--home', $homeDir, '--keep', $Keep, '--apply')
    if ($exclude) { $args_ += @('--exclude', $exclude) }
    python @args_ 2>&1 | Select-String -Pattern 'kept individually|TOTAL|applied|left as' | ForEach-Object { $_.Line }
}
"--- result"
& "$d\psize.ps1" -ProfileName $ProfileName -Label "AFTER  $ProfileName"
"Start a NEW chat in Hermes Desktop - existing chats keep the prompt they started with."
