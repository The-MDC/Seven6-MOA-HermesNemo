<#
seven6-smoke.ps1 -- regression check for one Hermes profile. Every call is hard-capped and proven, not assumed:

  oneshot     the profile answers, and the model in the usage report is the one config.yaml names (a fallback
              answering instead is a FAIL, because a fallback chain hides a dead primary)
  fallback    a deliberately wrong model is requested; one model of fallback_providers must answer
  delegation  the model uses delegate_task; the session database shows the call and the child model
  moa         a MoA turn on a throwaway clone with traces on; every enabled reference must answer

  .\seven6-smoke.ps1                         # all four checks on seven6moa (about 6-9 minutes)
  .\seven6-smoke.ps1 -Quick                  # oneshot + fallback only
  .\seven6-smoke.ps1 -Checks oneshot,moa
  .\seven6-smoke.ps1 -Profile default

Statuses: PASS, FAIL (the system answered wrongly), ERROR (a timeout, missing report or network problem: the check
could not run, so it is never counted as a regression), SKIP. Exit code 0 = all pass, 1 = any FAIL, 2 = ERROR only.
Results are appended to smoke-results.jsonl with a hash of config.yaml + SOUL.md; a PASS that turns into a FAIL on the
SAME hash is reported as a REGRESSION. No model grades another model: every check is an exact-match or a database fact.
The script never reads .env and prints no secrets. MoA runs on a clone that is deleted afterwards.
#>
param(
    [string]$Profile = 'seven6moa',
    [string[]]$Checks = @('oneshot', 'fallback', 'delegation', 'moa'),
    [switch]$Quick,
    [switch]$NoLog,
    [switch]$KeepClone,
    [switch]$ParseOnly          # print what was read from config.yaml and stop (no model calls)
)
$ErrorActionPreference = 'Continue'   # native commands write to stderr (hermes profile delete does); 'Stop' turned that into a thrown error
$root  = $PSScriptRoot
$hh    = Join-Path $env:LOCALAPPDATA 'hermes'
$pdir  = if ($Profile -eq 'default') { $hh } else { Join-Path $hh "profiles\$Profile" }
if (-not (Test-Path -LiteralPath (Join-Path $pdir 'config.yaml'))) { throw "No config.yaml in $pdir" }
if ($Quick) { $Checks = @('oneshot', 'fallback') }

$py = $null
foreach ($c in @('python', 'py')) { $cmd = Get-Command $c -ErrorAction SilentlyContinue; if ($cmd) { $py = $cmd.Source; break } }

# ------------------------------------------------------------------ config readers (text level, no YAML library)
$cfgLines = [System.IO.File]::ReadAllLines((Join-Path $pdir 'config.yaml'))

function Get-TopBlock([string[]]$Lines, [string]$Key) {
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match ('^' + [regex]::Escape($Key) + ':\s*($|#)')) { $start = $i; break } }
    if ($start -lt 0) { return @() }
    $end = $Lines.Count
    for ($j = $start + 1; $j -lt $Lines.Count; $j++) { if ($Lines[$j] -match '^[A-Za-z_]') { $end = $j; break } }
    return @($Lines[$start..($end - 1)])
}
function Get-FirstValue([string[]]$Lines, [string]$Key) {
    foreach ($l in $Lines) { if ($l -match ('^\s+' + [regex]::Escape($Key) + ':\s*["'']?([^"''\s#]+)')) { return $Matches[1] } }
    return $null
}
$modelBlock   = Get-TopBlock $cfgLines 'model'
$expectedModel = Get-FirstValue $modelBlock 'default'
$primaryProv   = Get-FirstValue $modelBlock 'provider'
$chain = @(); foreach ($l in (Get-TopBlock $cfgLines 'fallback_providers')) { if ($l -match '^\s+model:\s*["'']?([^"''\s#]+)') { $chain += $Matches[1] } }
$delegBlock    = Get-TopBlock $cfgLines 'delegation'
$delegModel    = Get-FirstValue $delegBlock 'model'

function Get-PresetInfo([string[]]$MoaLines) {
    $refs = @(); $aggModel = $null; $seenP = $false; $seenD = $false; $in = $false; $base = 0; $cur = $null; $inAgg = $false
    foreach ($l in $MoaLines) {
        if (-not $seenP) { if ($l -match '^\s{2}presets:\s*$') { $seenP = $true }; continue }
        if (-not $seenD) { if ($l -match '^\s{4}default:\s*$') { $seenD = $true }; continue }
        if ($l -match '^\s*$' -or $l -match '^\s*#') { continue }
        if ($l -match '^\s{0,4}\S') { break }                                   # left the default preset
        if ($l -match '^(\s+)reference_models:\s*$') { $in = $true; $inAgg = $false; $base = $Matches[1].Length; continue }
        if ($l -match '^\s+aggregator:\s*$') { if ($in -and $cur) { $refs += $cur; $cur = $null }; $in = $false; $inAgg = $true; continue }
        if ($inAgg) { if ($l -match '^\s+model:\s*["'']?([^"''\s#]+)') { $aggModel = $Matches[1]; $inAgg = $false }; continue }
        if ($in) {
            if ($l -match '^\s*-\s*provider:\s*["'']?([^"''\s#]+)') { if ($cur) { $refs += $cur }; $cur = [ordered]@{ provider = $Matches[1]; model = ''; enabled = $false }; continue }
            if ($cur -and $l -match '^\s+model:\s*["'']?([^"''\s#]+)') { $cur.model = $Matches[1]; continue }
            if ($cur -and $l -match '^\s+enabled:\s*(true|false)') { $cur.enabled = ($Matches[1] -eq 'true'); continue }
        }
    }
    if ($cur) { $refs += $cur }
    return [pscustomobject]@{ Refs = $refs; Aggregator = $aggModel }
}
$preset = Get-PresetInfo (Get-TopBlock $cfgLines 'moa')

# ------------------------------------------------------------------ helpers
function Get-ConfigHash {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $pdir 'config.yaml'))
    $soul = Join-Path $pdir 'SOUL.md'
    if (Test-Path -LiteralPath $soul) { $bytes += [System.IO.File]::ReadAllBytes($soul) }
    (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 8)
}

function Invoke-Capped {
    param([string]$ProfileName, [string[]]$HermesArgs, [int]$TimeoutSec)
    $tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $out = Join-Path $env:TEMP "s6smoke-$tag.out"; $err = Join-Path $env:TEMP "s6smoke-$tag.err"
    $a = if ($ProfileName -eq 'default') { @() } else { @('-p', $ProfileName) }
    $a += $HermesArgs
    $p = Start-Process hermes -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) { Start-Sleep -Milliseconds 500 }
    $timedOut = -not $p.HasExited
    if ($timedOut) { & taskkill /T /F /PID $p.Id 2>&1 | Out-Null }
    $o = if (Test-Path -LiteralPath $out) { (Get-Content -LiteralPath $out -Raw) } else { '' }
    $e = if (Test-Path -LiteralPath $err) { (Get-Content -LiteralPath $err -Raw) } else { '' }
    Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{ Seconds = [int]$sw.Elapsed.TotalSeconds; TimedOut = $timedOut; Stdout = "$o".Trim(); Stderr = "$e".Trim() }
}

function Read-Usage([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}
function New-Result([string]$Name, [string]$Status, [int]$Seconds, [string]$Detail) {
    [pscustomobject]@{ name = $Name; status = $Status; seconds = $Seconds; detail = $Detail }
}
function Short([string]$s, [int]$n = 140) { $s = "$s" -replace '\s+', ' '; if ($s.Length -gt $n) { $s.Substring(0, $n) + '...' } else { $s } }
function Get-DbFacts([string]$ProfileDir, [string]$SessionId) {
    if (-not $py) { return $null }
    $o = & $py -I (Join-Path $root 'smoke_db.py') $ProfileDir $SessionId 2>&1
    try { return (($o | ForEach-Object { "$_" }) -join "`n" | ConvertFrom-Json) } catch { return $null }
}
function Tmp([string]$suffix) { Join-Path $env:TEMP ("s6smoke-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + $suffix) }

# ------------------------------------------------------------------ checks
function Test-OneShot {
    $u = Tmp '.json'
    $r = Invoke-Capped $Profile @('--usage-file', $u, '-z', '"Reply with exactly the single word PONG"') 150
    $rep = Read-Usage $u; Remove-Item -LiteralPath $u -Force -ErrorAction SilentlyContinue
    if ($r.TimedOut) { return New-Result 'oneshot' 'ERROR' $r.Seconds 'timed out after 150 s (the check could not run)' }
    if (-not $rep) { return New-Result 'oneshot' 'ERROR' $r.Seconds ('no usage report. ' + (Short $r.Stderr)) }
    if ($rep.failed -or -not $rep.completed) { return New-Result 'oneshot' 'FAIL' $r.Seconds ("run did not complete: $($rep.turn_exit_reason)") }
    if ($expectedModel -and $rep.model -ne $expectedModel) { return New-Result 'oneshot' 'FAIL' $r.Seconds ("answered by $($rep.model) ($($rep.provider)), config says ${expectedModel}: a fallback is answering") }
    if ($r.Stdout -notmatch 'PONG') { return New-Result 'oneshot' 'FAIL' $r.Seconds ('answer lacked PONG: ' + (Short $r.Stdout 80)) }
    $cached = [int]$rep.cache_read_tokens; $total = [int]$rep.input_tokens + $cached + [int]$rep.cache_write_tokens    # input_tokens alone drops when the host caches the prompt prefix
    New-Result 'oneshot' 'PASS' $r.Seconds ("answered by $($rep.model); $('{0:N0}' -f $total) prompt tokens ($('{0:N0}' -f $cached) read from cache)")
}

function Test-Fallback {
    $prov = if ($primaryProv) { $primaryProv } else { 'nvidia-nim' }
    $bogus = 'nvidia/no-such-model-9000'
    $u = Tmp '.json'
    $r = Invoke-Capped $Profile @('--provider', $prov, '-m', $bogus, '--usage-file', $u, '-z', '"Reply with exactly the single word PONG"') 200
    $rep = Read-Usage $u; Remove-Item -LiteralPath $u -Force -ErrorAction SilentlyContinue
    if ($r.TimedOut) { return New-Result 'fallback' 'ERROR' $r.Seconds 'timed out after 200 s (the check could not run)' }
    if (-not $rep) { return New-Result 'fallback' 'ERROR' $r.Seconds ('no usage report. ' + (Short $r.Stderr)) }
    if ($rep.failed -or -not $rep.completed) { return New-Result 'fallback' 'FAIL' $r.Seconds 'the wrong model was rejected but no model in the fallback chain answered' }
    if ($rep.model -eq $bogus) { return New-Result 'fallback' 'FAIL' $r.Seconds 'the wrong model name answered, so the test is not testing anything' }
    $pos = [array]::IndexOf($chain, $rep.model)
    if ($pos -lt 0) { return New-Result 'fallback' 'FAIL' $r.Seconds ("answered by $($rep.model), which is not in fallback_providers") }
    New-Result 'fallback' 'PASS' $r.Seconds ("wrong model rejected; $($rep.model) answered (chain entry $($pos + 1) of $($chain.Count))")
}

function Test-Delegation {
    $u = Tmp '.json'
    $r = Invoke-Capped $Profile @('--usage-file', $u, '-z', '"Use the delegate_task tool once to ask a subagent to reply with exactly the word GAMMA. Then reply with only the word the subagent returned."') 240
    $rep = Read-Usage $u; Remove-Item -LiteralPath $u -Force -ErrorAction SilentlyContinue
    if ($r.TimedOut) { return New-Result 'delegation' 'ERROR' $r.Seconds 'timed out after 240 s (the check could not run)' }
    if (-not $rep) { return New-Result 'delegation' 'ERROR' $r.Seconds ('no usage report. ' + (Short $r.Stderr)) }
    if ($rep.failed -or -not $rep.completed) { return New-Result 'delegation' 'FAIL' $r.Seconds ("run did not complete: $($rep.turn_exit_reason)") }
    $db = Get-DbFacts $pdir $rep.session_id
    if (-not $db -or $db.error) { return New-Result 'delegation' 'ERROR' $r.Seconds 'could not read the session database (needs Python)' }
    $called = 0; if ($db.tools.PSObject.Properties['delegate_task']) { $called = [int]$db.tools.delegate_task }
    if ($called -lt 1) { return New-Result 'delegation' 'FAIL' $r.Seconds ('delegate_task was never called; tools used: ' + (($db.tools.PSObject.Properties | ForEach-Object { "$($_.Name) x$($_.Value)" }) -join ', ')) }
    if ($r.Stdout -notmatch 'GAMMA') { return New-Result 'delegation' 'FAIL' $r.Seconds ('delegate_task ran but the answer lacked GAMMA: ' + (Short $r.Stdout 80)) }
    $childModels = @($db.usage | Where-Object { $_.session -ne $rep.session_id } | ForEach-Object { $_.model } | Select-Object -Unique)
    $note = if ($childModels.Count -eq 0) { 'child usage not recorded' } elseif ($delegModel -and ($childModels -notcontains $delegModel)) { "child ran on $($childModels -join ', ') (configured $delegModel; a child fallback is by design)" } else { "child model $($childModels -join ', ')" }
    New-Result 'delegation' 'PASS' $r.Seconds ("delegate_task x$called; $note")
}

function Test-Moa {
    $clone = 's6smoke' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    $cdir = Join-Path $hh "profiles\$clone"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $mk = & hermes profile create $clone --clone-from $Profile --no-alias --description 'smoke test (auto-deleted)' 2>&1 | Out-String
        if (-not (Test-Path -LiteralPath $cdir)) { return New-Result 'moa' 'ERROR' ([int]$sw.Elapsed.TotalSeconds) ('could not create the throwaway clone. ' + (Short $mk)) }
        & hermes -p $clone config set moa.save_traces true 2>&1 | Out-Null
        $u = Tmp '.json'
        $r = Invoke-Capped $clone @('--provider', 'moa', '-m', 'default', '--usage-file', $u, '-z', '"What is 17 times 23? Reply with only the number."') 300
        $rep = Read-Usage $u; Remove-Item -LiteralPath $u -Force -ErrorAction SilentlyContinue
        $secs = [int]$sw.Elapsed.TotalSeconds
        if ($r.TimedOut) { return New-Result 'moa' 'ERROR' $secs 'timed out after 300 s (the check could not run)' }
        if (-not $rep) { return New-Result 'moa' 'ERROR' $secs ('no usage report. ' + (Short $r.Stderr)) }
        $trace = Join-Path $cdir ("moa-traces\" + ($rep.session_id -replace '[^A-Za-z0-9_.-]', '_') + '.jsonl')
        if (-not (Test-Path -LiteralPath $trace)) { return New-Result 'moa' 'FAIL' $secs 'no MoA trace was written: the turn did not run the reference fan-out' }
        $rec = Get-Content -LiteralPath $trace | Select-Object -First 1 | ConvertFrom-Json
        $bad = @(); $ok = @()
        foreach ($ref in $rec.references) {
            $out = "$($ref.output)"
            $outTok = 0; if ($ref.usage) { $outTok = [int]$ref.usage.output_tokens }
            if ([string]::IsNullOrWhiteSpace($out) -or $out -match '^\s*\[?\s*(failed|skipped|error)' -or $outTok -le 0) {
                $why = if ([string]::IsNullOrWhiteSpace($out)) { 'empty answer' } else { Short $out 110 }
                # a busy or unreachable provider is not a Seven6 fault: report it as ERROR (could not run), never as a regression
                $busy = [bool]($why -match '(?i)\b(429|500|502|503|504)\b|timed? ?out|overload|ResourceExhausted|rate.?limit|temporar|unavailable|capacity|connection (reset|aborted|error)|server error')
                $bad += [pscustomobject]@{ model = "$($ref.model)"; why = $why; busy = $busy }
            } else { $ok += "$($ref.model)" }
        }
        $want = @($preset.Refs | Where-Object { $_.enabled })
        if ($want.Count -gt 0 -and $rec.references.Count -lt $want.Count) { return New-Result 'moa' 'FAIL' $secs ("$($rec.references.Count) references ran but $($want.Count) are enabled in the default preset") }
        $hard = @($bad | Where-Object { -not $_.busy }); $busyRefs = @($bad | Where-Object { $_.busy })
        if ($hard.Count -gt 0) { return New-Result 'moa' 'FAIL' $secs ("reference(s) failed: " + (($hard | ForEach-Object { "$($_.model): $($_.why)" }) -join ' | ') + " (answered: $($ok -join ', '))") }
        if ($busyRefs.Count -gt 0) { return New-Result 'moa' 'ERROR' $secs ("provider busy, not a config fault: " + (($busyRefs | ForEach-Object { "$($_.model): $($_.why)" }) -join ' | ') + " (answered: $($ok -join ', ')). Run again in a few minutes.") }
        if ($ok.Count -lt 1) { return New-Result 'moa' 'FAIL' $secs 'the trace has no references' }
        if ($preset.Aggregator -and $rec.aggregator.model -ne $preset.Aggregator) { return New-Result 'moa' 'FAIL' $secs ("aggregator was $($rec.aggregator.model), config says $($preset.Aggregator)") }
        if ($r.Stdout -notmatch '391') { return New-Result 'moa' 'FAIL' $secs ('MoA answer lacked 391: ' + (Short $r.Stdout 80)) }
        New-Result 'moa' 'PASS' $secs ("$($ok.Count) references answered ($($ok -join ', ')); aggregator $($rec.aggregator.model)")
    } finally {
        if (-not $KeepClone) {
            try {
                & hermes profile delete $clone --yes 2>&1 | Out-Null
                & hermes profile purge-identity $clone 2>&1 | Out-Null     # delete leaves the session/routing identity pending
            } catch { }
        }
        if ((Test-Path -LiteralPath $cdir) -and -not $KeepClone) { Write-Warning "Throwaway clone still present: $cdir (delete it with: hermes profile delete $clone --yes)" }
    }
}

# ------------------------------------------------------------------ run
$hash = Get-ConfigHash
"Seven6 smoke test   profile=$Profile   config=$hash   $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
"  expected model: $expectedModel | fallback chain: $($chain.Count) | delegation model: $delegModel | MoA preset: $(@($preset.Refs | Where-Object { $_.enabled }).Count) enabled references"
if (-not $py) { "  note: no Python found, the delegation check will report ERROR" }
if ($ParseOnly) {
    "  fallback chain: " + ($chain -join ' > ')
    "  primary provider: $primaryProv"
    "  default preset references:"; $preset.Refs | ForEach-Object { "    {0}  {1}  enabled={2}" -f $_.provider, $_.model, $_.enabled }
    "  default preset aggregator: $($preset.Aggregator)"
    "  python: $py"
    exit 0
}
""
$results = @()
foreach ($c in $Checks) {
    $res = try {
        switch ($c) {
            'oneshot'    { Test-OneShot }
            'fallback'   { Test-Fallback }
            'delegation' { Test-Delegation }
            'moa'        { Test-Moa }
            default      { New-Result $c 'SKIP' 0 'unknown check name' }
        }
    } catch { New-Result $c 'ERROR' 0 ("script error: " + (Short $_.Exception.Message)) }
    $res = @($res) | Where-Object { $_ -and $_.PSObject.Properties['status'] } | Select-Object -Last 1     # a check returns exactly one result
    if (-not $res) { $res = New-Result $c 'ERROR' 0 'the check returned no result' }
    $results += $res
    "  {0,-11} {1,-5} {2,4} s  {3}" -f $res.name, $res.status, $res.seconds, $res.detail
}

# ------------------------------------------------------------------ compare with the last run on the same config
$store = Join-Path $root 'smoke-results.jsonl'
$prev = $null
if (Test-Path -LiteralPath $store) {
    $prev = Get-Content -LiteralPath $store | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } |
        Where-Object { $_.profile -eq $Profile -and $_.config -eq $hash } | Select-Object -Last 1
}
$regressions = @()
if ($prev) {
    foreach ($res in $results) {
        $was = $prev.checks | Where-Object { $_.name -eq $res.name } | Select-Object -First 1
        if ($was -and $was.status -eq 'PASS' -and $res.status -eq 'FAIL') { $regressions += $res.name }
    }
}
$nFail = @($results | Where-Object { $_.status -eq 'FAIL' }).Count
$nErr  = @($results | Where-Object { $_.status -eq 'ERROR' }).Count
$nPass = @($results | Where-Object { $_.status -eq 'PASS' }).Count
$overall = if ($nFail) { 'FAIL' } elseif ($nErr) { 'ERROR' } else { 'PASS' }
""
"Result: $overall ($nPass of $($results.Count) passed, $nFail failed, $nErr could not run)"
if ($prev) { if ($regressions) { "REGRESSION against the last run on this same config ($($prev.ts)): $($regressions -join ', ')" } else { "No regression against the last run on this same config ($($prev.ts))." } }
else { "No earlier run on this config hash: this run is the new baseline." }
if (-not $NoLog) {
    $row = [ordered]@{ ts = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); profile = $Profile; config = $hash; overall = $overall; checks = $results }
    Add-Content -LiteralPath $store -Value ($row | ConvertTo-Json -Depth 5 -Compress) -Encoding UTF8
}
if ($nFail) { exit 1 } elseif ($nErr) { exit 2 } else { exit 0 }
