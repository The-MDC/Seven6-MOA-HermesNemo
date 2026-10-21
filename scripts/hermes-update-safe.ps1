<#
.SYNOPSIS
  Update Hermes without the failures an update caused here, and check the result.

.DESCRIPTION
  Two things went wrong the one time Hermes updated on this box:

    1. The installer renamed a Python folder that a running Hermes process held open:
       "[WinError 5] Access is denied: ...\tools\python-3.14.7... -> .previous-python...".
       The gateway and the dashboard were both running.
    2. `hermes dashboard` finished a half-done update on its own and migrated the config
       (v0 -> v51), changing a file the repo copy had to catch up with.

  So, in this order:
    1. List what is running from the Hermes folder.
    2. Back up config.yaml (root and every profile) to <name>.bak-<stamp>.
    3. Stop the dashboard task, the gateway, and anything else running from that folder.
       If something is STILL running afterwards it stops there: that is the lock.
    4. `hermes update`.
    5. Check the installed configs against the repo copy (scripts/check-config-drift.py).
    6. Only if the update succeeded AND routing is intact: restart the gateway and the
       dashboard, then wait for the gateway to report running.

  It never applies the repo config for you. If routing drifted it says so, and
  hermes-apply.ps1 (which backs up first) is the way back. A config the update changed
  for a good reason belongs in configs/hermes/config.yaml, which is a PR, not a script.

  UNVERIFIED on a real 0.22.x install: the exact `hermes gateway stop|restart` and
  `hermes update` subcommands. `hermes update` and `gateway restart` appear in this
  box's own logs and output; `gateway stop` is the natural pair. Each is run, its exit
  code is checked, and a failure is reported rather than assumed away.

.EXAMPLE
  pwsh -File scripts/hermes-update-safe.ps1 -WhatIf     # the plan, nothing touched
  pwsh -File scripts/hermes-update-safe.ps1             # asks once, then does it
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Skip the "type YES" question. -WhatIf never asks and never changes anything.
    [switch]$Force,

    # Update and check, but leave the gateway and dashboard stopped.
    [switch]$NoRestart,

    # Seconds to wait for the gateway to report running after the restart. 0 = do not wait.
    [int]$WaitSeconds = 90,

    # Profiles whose drift is a failure; the rest only warn. Same meaning as hermes-verify.
    [string[]]$StrictProfiles = @('seven6moa')
)

. (Join-Path $PSScriptRoot 'hermes-common.ps1')
# `pwsh -File x.ps1 -StrictProfiles a,b` delivers ONE string "a,b"; split it.
$StrictProfiles = @(Split-NameList $StrictProfiles)

$ErrorActionPreference = 'Stop'
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$HermesHome = Get-HermesHomePath
$RepoRoot   = Split-Path $PSScriptRoot -Parent
$Golden     = Join-Path $RepoRoot 'configs/hermes/config.yaml'
$DriftTool  = Join-Path $PSScriptRoot 'check-config-drift.py'
$problems   = 0

function Step([string]$t)  { Write-Host "`n$t" -ForegroundColor Cyan }
function Good([string]$m)  { Write-Host "  ok    $m" -ForegroundColor Green }
function Note([string]$m)  { Write-Host "  ..    $m" -ForegroundColor DarkGray }
function Warn([string]$m)  { Write-Host "  warn  $m" -ForegroundColor Yellow }
function Bad([string]$m)   { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:problems++ }

function Invoke-Hermes {
    # Runs `hermes <args>`, shows what it printed, returns the exit code.
    param([string[]]$HermesArgs)
    $out = (& hermes @HermesArgs 2>&1 | Out-String).TrimEnd()
    $code = $LASTEXITCODE
    if ($out) { ($out -split "`r?`n") | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray } }
    return $code
}

function Get-ConfigTargets {
    $t = @()
    $root = Join-Path $HermesHome 'config.yaml'
    if (Test-Path $root) { $t += [pscustomobject]@{ Name = 'root'; Path = $root; Profile = $false } }
    foreach ($d in @(Get-ChildItem (Join-Path $HermesHome 'profiles') -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $p = Join-Path $d.FullName 'config.yaml'
        if (Test-Path $p) { $t += [pscustomobject]@{ Name = $d.Name; Path = $p; Profile = $true } }
    }
    return $t
}

# ------------------------------------------------------------------ 1. look
Step '1. what is running from the Hermes folder'
if (-not (Get-Command hermes -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'hermes is not on PATH - nothing to update'
}
$running = @(Get-HermesProcess)
if ($running) { $running | ForEach-Object { Note "pid $($_.Id)  $($_.ProcessName)  $($_.Path)" } }
else { Note 'nothing is running from the Hermes folder' }
$targets = @(Get-ConfigTargets)
Note "$($targets.Count) config file(s) will be backed up and checked: $((($targets | ForEach-Object Name) -join ', '))"

if (-not $Force -and -not $WhatIfPreference) {
    Write-Host "`nThis stops Hermes (gateway, dashboard, Desktop's backend), updates it, and restarts it." -ForegroundColor Yellow
    if ((Read-Host "Type YES to continue") -ne 'YES') { Write-Host 'cancelled; nothing changed'; exit 0 }
}

# ------------------------------------------------------------------ 2. back up
Step '2. back up the configs'
foreach ($t in $targets) {
    $bak = "$($t.Path).bak-$stamp"
    if ($PSCmdlet.ShouldProcess($t.Path, "back up to $(Split-Path $bak -Leaf)")) {
        Copy-Item $t.Path $bak -Force
        Good "$($t.Name): $(Split-Path $bak -Leaf)"
    }
}

# ------------------------------------------------------------------ 3. stop
Step '3. stop Hermes'
if ($IsWindows -and (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) -and
    (Get-ScheduledTask -TaskName $script:DashboardTaskName -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess("scheduled task '$($script:DashboardTaskName)'", 'stop')) {
        Stop-ScheduledTask -TaskName $script:DashboardTaskName -ErrorAction SilentlyContinue
        Good 'dashboard task stopped'
    }
}
if ($PSCmdlet.ShouldProcess('hermes gateway', 'stop')) {
    $code = Invoke-Hermes @('gateway', 'stop')
    if ($code -eq 0) { Good 'hermes gateway stop' } else { Warn "hermes gateway stop exited $code - falling back to stopping the processes" }
}
$left = @(Get-HermesProcess)
if ($left -and $PSCmdlet.ShouldProcess("$($left.Count) process(es): $(($left | ForEach-Object Id) -join ', ')", 'stop')) {
    foreach ($p in $left) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    $deadline = (Get-Date).AddSeconds(15)
    do { Start-Sleep -Milliseconds 500; $left = @(Get-HermesProcess) } while ($left -and (Get-Date) -lt $deadline)
}
if (-not $WhatIfPreference) {
    if ($left) {
        # This is the exact condition that produced WinError 5. Do not run the update on top of it.
        $left | ForEach-Object { Bad "still running, would hold files open: pid $($_.Id) $($_.ProcessName) $($_.Path)" }
        Write-Host "`nStopped before updating. Close those (Hermes Desktop is the usual one) and rerun." -ForegroundColor Red
        exit 1
    }
    Good 'nothing is running from the Hermes folder'
}

# ------------------------------------------------------------------ 4. update
Step '4. hermes update'
$updateOk = $false
if ($PSCmdlet.ShouldProcess('hermes', 'update')) {
    $code = Invoke-Hermes @('update')
    if ($code -eq 0) { $updateOk = $true; Good 'hermes update finished' }
    else { Bad "hermes update exited $code - the install may be half-updated; the config backups above are intact" }
}

# ------------------------------------------------------------------ 5. check
Step '5. routing intact?'
$routingOk = $true
if ($WhatIfPreference) { Note 'would compare every config against configs/hermes/config.yaml' }
elseif (-not $updateOk) { Note 'skipped: the update did not finish' }
else {
    $py = Find-YamlPython
    if (-not $py) {
        Bad 'drift NOT checked - no Python with PyYAML found (set HERMES_DRIFT_PYTHON). Routing is unverified, so Hermes is not restarted.'
        $routingOk = $false
    } else {
        foreach ($t in (Get-ConfigTargets)) {
            $strict = $t.Profile -and ($StrictProfiles -contains $t.Name)
            $r = Invoke-DriftCheck -Python $py -Tool $DriftTool -Golden $Golden -Installed $t.Path -Label $t.Name -Profile:$t.Profile -Strict:$strict
            ($r.Output -split "`r?`n") | Where-Object { $_.Trim() } | ForEach-Object {
                $c = if ($_ -match '^\s+FAIL') { 'Red' } elseif ($_ -match '^\s+warn') { 'Yellow' } elseif ($_ -match '^\s+ok') { 'Green' } else { 'DarkGray' }
                Write-Host $_ -ForegroundColor $c
            }
            if ($r.Code -ne 0) { $routingOk = $false; Bad "$($t.Name): routing check failed (exit $($r.Code))" }
        }
        if (-not $routingOk) {
            Write-Host "  The update changed routing. Nothing was restarted. To restore the repo's: pwsh -File scripts/hermes-apply.ps1 -WhatIf, then without -WhatIf (it backs up first)." -ForegroundColor Yellow
        }
    }
}

# ------------------------------------------------------------------ 6. restart
Step '6. restart'
if ($NoRestart)               { Note '-NoRestart: leaving Hermes stopped' }
elseif ($WhatIfPreference)    { Note 'would restart the gateway and the dashboard, then wait for the gateway' }
elseif (-not ($updateOk -and $routingOk)) { Note 'not restarting: the update or the routing check failed (above)' }
else {
    if ($PSCmdlet.ShouldProcess('hermes gateway', 'restart')) {
        $code = Invoke-Hermes @('gateway', 'restart')
        if ($code -eq 0) { Good 'hermes gateway restart' } else { Bad "hermes gateway restart exited $code" }
    }
    if ($IsWindows -and (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) -and
        (Get-ScheduledTask -TaskName $script:DashboardTaskName -ErrorAction SilentlyContinue)) {
        if (-not (Test-LocalPort -Port $script:DashboardPort)) {
            Start-ScheduledTask -TaskName $script:DashboardTaskName
            Good 'dashboard task started'
        }
    } else {
        Note 'no dashboard task installed (scripts/hermes-dashboard-autostart.ps1 -Action Install); start the dashboard yourself if you use Desktop'
    }
    if ($WaitSeconds -gt 0) {
        $deadline = (Get-Date).AddSeconds($WaitSeconds); $up = $false
        while ((Get-Date) -lt $deadline -and -not $up) {
            Start-Sleep -Seconds 3
            try {
                $st = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:DashboardPort)/api/status" -TimeoutSec 4
                if ($st.gateway_running) { $up = $true; Good "gateway running (Hermes $($st.version), config v$($st.config_version), overall '$($st.overall)')" }
            } catch { }
        }
        if (-not $up) { Bad "the gateway did not report running within $WaitSeconds s (is the dashboard up? curl.exe http://127.0.0.1:$($script:DashboardPort)/api/status)" }
    } else { Note '-WaitSeconds 0: not waiting for the gateway' }
}

Write-Host ''
if ($WhatIfPreference) { Write-Host 'WhatIf: nothing was stopped, changed or started.'; exit 0 }
if ($problems) { Write-Host "FINISHED WITH $problems PROBLEM(S) - see above" -ForegroundColor Red; exit 1 }
Write-Host 'OK      updated, routing intact. Run scripts/hermes-verify.ps1 for the full check.' -ForegroundColor Green
exit 0
