<#
.SYNOPSIS
  Tests for the PowerShell glue: hermes-common, the dashboard launcher and autostart,
  and the drift section of hermes-verify. Runs on Linux/macOS pwsh (CI); skips on Windows.

.DESCRIPTION
  The Python drift checker has its own tests. What nothing exercised was the glue
  around it -- argument splatting, exit-code capture, the strict/advisory split, the
  "no Python" warning -- and the new scripts' promises: the token is never printed, a
  second dashboard is never started, a non-loopback bind is refused, -WhatIf writes
  nothing.

  Windows-only calls (Register-ScheduledTask, the Startup folder) cannot run here and
  are NOT covered: scripts/hermes-dashboard-autostart.ps1 -Action Install -WhatIf on
  the box is that test. Everything else is run as a child process, so exit codes and
  output are what a user would see.

  pwsh -File scripts/test-hermes-ps.ps1
#>
$ErrorActionPreference = 'Stop'

if ($IsWindows) { Write-Host 'skipped: these tests use a POSIX fake `hermes`; run them on Linux/macOS or in CI'; exit 0 }

$Scripts = $PSScriptRoot
$Repo    = Split-Path $Scripts -Parent
$Pwsh    = (Get-Process -Id $PID).Path
$Tmp     = Join-Path ([IO.Path]::GetTempPath()) ("hermes-ps-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp | Out-Null

$script:Pass = 0
$script:Fail = 0
function Check([bool]$ok, [string]$name, [string]$detail = '') {
    if ($ok) { $script:Pass++; Write-Host "  ok    $name" -ForegroundColor Green }
    else     { $script:Fail++; Write-Host "  FAIL  $name" -ForegroundColor Red; if ($detail) { Write-Host ($detail -split "`n" | ForEach-Object { "          $_" }) -Separator "`n" } }
}

# Run a script in a CHILD pwsh with extra environment, restore the environment after.
function Invoke-Child {
    param([string[]]$ArgList, [hashtable]$Env = @{}, [string]$PathPrefix = '', [string]$PathOverride = '')
    $saved = @{}
    foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    $savedPath = $env:PATH
    if ($PathOverride) { $env:PATH = $PathOverride } elseif ($PathPrefix) { $env:PATH = "$PathPrefix$([IO.Path]::PathSeparator)$env:PATH" }
    try {
        $out = (& $Pwsh -NoLogo -NoProfile @ArgList 2>&1 | Out-String)
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
    } finally {
        $env:PATH = $savedPath
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
}

$hex64 = '[0-9A-Fa-f]{64}'

try {
    # ------------------------------------------------------------ common helpers
    Write-Host "`nhermes-common.ps1" -ForegroundColor Cyan
    . (Join-Path $Scripts 'hermes-common.ps1')

    $t1 = New-DashboardToken; $t2 = New-DashboardToken
    Check ($t1 -match "^$hex64$") 'token is 64 hex characters (256 bits)' $t1.Length
    Check ($t1 -ne $t2) 'two tokens differ'

    $py = Find-YamlPython
    Check ($null -ne $py) 'Find-YamlPython finds an interpreter that can import yaml'
    $bogus = Join-Path $Tmp 'no-such-python'
    $saved = $env:HERMES_DRIFT_PYTHON; $env:HERMES_DRIFT_PYTHON = $bogus
    try { $py2 = Find-YamlPython } finally { $env:HERMES_DRIFT_PYTHON = $saved }
    Check ($null -ne $py2 -and $py2[0] -ne $bogus) 'a bogus HERMES_DRIFT_PYTHON is rejected, not returned'

    # An interpreter that EXISTS but cannot import yaml -- the Microsoft Store stub on a
    # stock Windows box is exactly this. Only the import test can reject it; a missing
    # path is rejected by the call failing, so the check above cannot tell the two apart.
    $noYaml = Join-Path $Tmp 'python-without-yaml'
    Set-Content $noYaml -Value "#!/bin/sh`nexit 1`n"; chmod +x $noYaml
    $saved = $env:HERMES_DRIFT_PYTHON; $env:HERMES_DRIFT_PYTHON = $noYaml
    try { $py3 = Find-YamlPython } finally { $env:HERMES_DRIFT_PYTHON = $saved }
    Check ($null -ne $py3 -and $py3[0] -ne $noYaml) 'an interpreter that exists but cannot import yaml is rejected'

    $r = Invoke-DriftCheck -Python $py -Tool (Join-Path $Scripts 'check-config-drift.py') `
            -Golden (Join-Path $Repo 'configs/hermes/config.yaml') -Installed (Join-Path $Repo 'configs/hermes/config.yaml') -Label 'repo'
    Check ($r.Code -eq 0) 'Invoke-DriftCheck: repo against itself exits 0' $r.Output
    $missing = Join-Path $Tmp 'absent.yaml'
    $r = Invoke-DriftCheck -Python $py -Tool (Join-Path $Scripts 'check-config-drift.py') `
            -Golden (Join-Path $Repo 'configs/hermes/config.yaml') -Installed $missing -Label 'x'
    Check ($r.Code -eq 2) 'Invoke-DriftCheck: unreadable file exits 2, not 0' "code $($r.Code)"

    # ------------------------------------------------------------ launcher
    Write-Host "`nhermes-dashboard-launch.ps1" -ForegroundColor Cyan
    $fakeBin = Join-Path $Tmp 'bin'; New-Item -ItemType Directory $fakeBin | Out-Null
    $rec = Join-Path $Tmp 'hermes-called.txt'
    $fake = Join-Path $fakeBin 'hermes'
    Set-Content $fake -Value @"
#!/bin/sh
echo "ARGS: `$*" >> '$rec'
echo "TOKEN_LEN: `${#HERMES_DASHBOARD_SESSION_TOKEN}" >> '$rec'
exit 0
"@
    chmod +x $fake
    $home1 = Join-Path $Tmp 'home1'; New-Item -ItemType Directory $home1 | Out-Null
    $launch = Join-Path $Scripts 'hermes-dashboard-launch.ps1'

    $r = Invoke-Child -ArgList @('-File', $launch, '-Port', '39119') -Env @{ HERMES_HOME = $home1; HERMES_DASHBOARD_SESSION_TOKEN = '' } -PathPrefix $fakeBin
    Check ($r.Code -eq 78) 'no token -> exit 78' "code $($r.Code): $($r.Output)"
    Check (-not (Test-Path $rec)) 'no token -> the dashboard was not started'
    Check ((Get-Content (Join-Path $home1 'dashboard-launch.log') -Raw) -match 'no HERMES_DASHBOARD_SESSION_TOKEN') 'no token -> the log says why'

    $tok = New-DashboardToken
    $r = Invoke-Child -ArgList @('-File', $launch, '-Port', '39119') -Env @{ HERMES_HOME = $home1; HERMES_DASHBOARD_SESSION_TOKEN = $tok } -PathPrefix $fakeBin
    $called = if (Test-Path $rec) { Get-Content $rec -Raw } else { '' }
    Check ($r.Code -eq 0) 'token set -> exit 0' "code $($r.Code): $($r.Output)"
    Check ($called -match 'ARGS: dashboard --no-open --host 127\.0\.0\.1 --port 39119') 'runs: hermes dashboard --no-open --host 127.0.0.1 --port <port>' $called
    Check ($called -match 'TOKEN_LEN: 64') 'the token reaches the dashboard process (64 chars)' $called
    $logText = Get-Content (Join-Path $home1 'dashboard-launch.log') -Raw
    Check ($logText -notmatch [regex]::Escape($tok) -and $r.Output -notmatch [regex]::Escape($tok)) 'the token is in neither the log nor the output'

    Remove-Item $rec -Force
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $listener.Start()
    try {
        $busy = $listener.LocalEndpoint.Port
        $r = Invoke-Child -ArgList @('-File', $launch, '-Port', "$busy") -Env @{ HERMES_HOME = $home1; HERMES_DASHBOARD_SESSION_TOKEN = $tok } -PathPrefix $fakeBin
        Check ($r.Code -eq 0 -and -not (Test-Path $rec)) 'port already answering -> exits 0 without starting a second dashboard' "code $($r.Code), recorded: $(Test-Path $rec)"
    } finally { $listener.Stop() }

    $r = Invoke-Child -ArgList @('-File', $launch, '-BindHost', '0.0.0.0') -Env @{ HERMES_HOME = $home1; HERMES_DASHBOARD_SESSION_TOKEN = $tok } -PathPrefix $fakeBin
    Check ($r.Code -ne 0 -and -not (Test-Path $rec)) 'a non-loopback bind is refused (the token travels over plain HTTP)' "code $($r.Code): $($r.Output)"

    # ------------------------------------------------------------ autostart
    Write-Host "`nhermes-dashboard-autostart.ps1" -ForegroundColor Cyan
    $auto = Join-Path $Scripts 'hermes-dashboard-autostart.ps1'
    $home2 = Join-Path $Tmp 'home2'; New-Item -ItemType Directory $home2 | Out-Null
    $e = @{ HERMES_HOME = $home2; HERMES_DASHBOARD_SESSION_TOKEN = '' }

    $r = Invoke-Child -ArgList @('-File', $auto) -Env $e
    Check ($r.Code -eq 0 -and $r.Output -match 'is NOT set') 'Status with no token: exits 0 and says NOT set' $r.Output

    $r = Invoke-Child -ArgList @('-File', $auto, '-Action', 'Install', '-WhatIf') -Env $e
    Check ($r.Output -match 'What if' -and $r.Output -match 'is NOT set' -and $r.Output -notmatch $hex64) 'Install -WhatIf: announces the change, makes none, prints no token' $r.Output

    $r = Invoke-Child -ArgList @('-File', $auto, '-Action', 'Install') -Env $e
    Check ($r.Output -match 'token created' -and $r.Output -match '\(64 chars' -and $r.Output -notmatch $hex64) 'Install: creates a 64-char token and never prints it' $r.Output

    $pre = New-DashboardToken
    $r = Invoke-Child -ArgList @('-File', $auto, '-Action', 'Install') -Env @{ HERMES_HOME = $home2; HERMES_DASHBOARD_SESSION_TOKEN = $pre }
    Check ($r.Output -match 'kept' -and $r.Output -notmatch [regex]::Escape($pre)) 'Install with a token set: keeps it, prints nothing secret' $r.Output

    $r = Invoke-Child -ArgList @('-File', $auto, '-Action', 'Install', '-RotateToken') -Env @{ HERMES_HOME = $home2; HERMES_DASHBOARD_SESSION_TOKEN = $pre }
    Check ($r.Output -match 'token rotated' -and $r.Output -notmatch [regex]::Escape($pre) -and $r.Output -notmatch $hex64) 'Install -RotateToken: replaces it, prints neither token' $r.Output

    $r = Invoke-Child -ArgList @('-File', $auto, '-Action', 'Remove') -Env $e
    Check ($r.Code -ne 0 -and $r.Output -match 'Windows') 'Remove off Windows says so instead of pretending' $r.Output

    . $auto
    Check ((Get-LauncherArguments -LauncherPath '/a b/c.ps1') -match '-File "/a b/c\.ps1"$') 'launcher path with a space is quoted'
    Check ((Get-LauncherArguments -LauncherPath '/x.ps1') -match '-WindowStyle Hidden') 'the task runs hidden'

    # ------------------------------------------------------------ verify: drift section
    Write-Host "`nhermes-verify.ps1 (drift section)" -ForegroundColor Cyan
    $verify = Join-Path $Scripts 'hermes-verify.ps1'
    $golden = Join-Path $Repo 'configs/hermes/config.yaml'
    function New-Home([string]$name) {
        $h = Join-Path $Tmp $name
        New-Item -ItemType Directory -Path (Join-Path $h 'profiles/seven6moa'), (Join-Path $h 'profiles/mylocal') -Force | Out-Null
        Copy-Item $golden (Join-Path $h 'config.yaml')
        Copy-Item $golden (Join-Path $h 'profiles/seven6moa/config.yaml')
        Set-Content (Join-Path $h 'profiles/mylocal/config.yaml') "model:`n  provider: custom:local`n  default: hf.co/mradermacher/Hermes-3-Llama-3.2-3B-abliterated-GGUF:Q8_0`n"
        New-Item -ItemType File (Join-Path $h '.env') | Out-Null
        return $h
    }
    function Get-Section([string]$text) {
        $m = [regex]::Match($text, '(?s)config drift \(installed vs repo copy\)\r?\n(.*?)(?:\r?\n\r?\n|\z)')
        return $m.Groups[1].Value
    }

    $h = New-Home 'ok'
    $r = Invoke-Child -ArgList @('-File', $verify, '-Stage', 'a') -Env @{ HERMES_HOME = $h }
    $sec = Get-Section $r.Output
    Check ($sec -match "root config: clean" -and $sec -match "profile 'seven6moa': clean") 'matching root and seven6moa -> clean' $sec
    Check ($sec -match "profile 'mylocal': clean, 2 warning" -and $sec -notmatch 'FAIL') 'mylocal on another model -> advisory warnings only, no FAIL' $sec

    $h = New-Home 'badprofile'
    (Get-Content (Join-Path $h 'profiles/seven6moa/config.yaml') -Raw).Replace('default: nvidia/nemotron-3.5-super-vl-120b-a12b', 'default: nvidia/nemotron-3-ultra-550b-a55b') |
        Set-Content (Join-Path $h 'profiles/seven6moa/config.yaml')
    $r = Invoke-Child -ArgList @('-File', $verify, '-Stage', 'a') -Env @{ HERMES_HOME = $h }
    $sec = Get-Section $r.Output
    Check ($sec -match "FAIL\s+differs: model\.default" -and $sec -match "profile 'seven6moa' failed the routing check") 'seven6moa on another model -> FAIL naming model.default' $sec
    Check ($r.Code -eq 1) 'verify exits 1 on that FAIL' "code $($r.Code)"

    $r = Invoke-Child -ArgList @('-File', $verify, '-Stage', 'a', '-StrictProfiles', 'none') -Env @{ HERMES_HOME = $h }
    $sec = Get-Section $r.Output
    Check ($sec -match "warn\s+differs: model\.default" -and $sec -notmatch "profile 'seven6moa' failed") '-StrictProfiles none -> the same drift is only a warning' $sec

    $r = Invoke-Child -ArgList @('-File', $verify, '-Stage', 'a', '-StrictProfiles', 'mylocal,seven6moa') -Env @{ HERMES_HOME = $h }
    $sec = Get-Section $r.Output
    Check ($sec -match "FAIL\s+differs: model\.default" -and $sec -match "profile 'seven6moa' failed") '-StrictProfiles a,b via -File is split into two names' $sec

    $h = New-Home 'badroot'
    (Get-Content (Join-Path $h 'config.yaml') -Raw) -replace '(?m)(  vision:\r?\n    provider: )"?custom:nvidia-nim"?', '${1}auto' | Set-Content (Join-Path $h 'config.yaml')
    $r = Invoke-Child -ArgList @('-File', $verify, '-Stage', 'a') -Env @{ HERMES_HOME = $h }
    $sec = Get-Section $r.Output
    Check ($sec -match 'FAIL\s+auxiliary slot\(s\) on auto' -and $sec -match 'root config drifted') 'root with an auto vision slot -> FAIL' $sec

    $h = New-Home 'nopy'
    $r = Invoke-Child -ArgList @('-File', $verify, '-Stage', 'a') -Env @{ HERMES_HOME = $h; HERMES_DRIFT_PYTHON = (Join-Path $Tmp 'nope') } -PathOverride (Split-Path $Pwsh -Parent)
    $sec = Get-Section $r.Output
    Check ($sec -match 'warn\s+config drift NOT checked') 'no Python -> a visible warning, never silence' $sec

    # ------------------------------------------------------------ hermes-apply: profiles
    Write-Host "`nhermes-apply.ps1 (-Profiles)" -ForegroundColor Cyan
    $apply = Join-Path $Scripts 'hermes-apply.ps1'
    function New-ApplyHome([string]$name) {
        $h = Join-Path $Tmp $name
        New-Item -ItemType Directory -Path (Join-Path $h 'profiles/seven6moa'), (Join-Path $h 'profiles/mylocal') -Force | Out-Null
        foreach ($f in 'config.yaml', 'profiles/seven6moa/config.yaml', 'profiles/mylocal/config.yaml') { Set-Content (Join-Path $h $f) "model:`n  default: stale-$($f -replace '[/.]','-')`n" }
        return $h
    }
    function Get-Same([string]$a) { (Get-FileHash $a).Hash -eq (Get-FileHash $golden).Hash }
    $codex = Join-Path $Tmp 'codex'

    $h = New-ApplyHome 'apply1'
    $r = Invoke-Child -ArgList @('-File', $apply, '-HermesHome', $h, '-CodexHome', $codex)
    Check ($r.Code -eq 0 -and (Get-Same (Join-Path $h 'config.yaml'))) 'default: the root config is installed' $r.Output
    Check (-not (Get-Same (Join-Path $h 'profiles/seven6moa/config.yaml')) -and -not (Get-Same (Join-Path $h 'profiles/mylocal/config.yaml'))) 'default: NO profile is touched' $r.Output
    Check (@(Get-ChildItem $h -Filter 'config.yaml.bak-*').Count -eq 1) 'default: the root was backed up first'

    $h = New-ApplyHome 'apply2'
    $r = Invoke-Child -ArgList @('-File', $apply, '-HermesHome', $h, '-CodexHome', $codex, '-Profiles', 'seven6moa')
    Check ($r.Code -eq 0 -and (Get-Same (Join-Path $h 'profiles/seven6moa/config.yaml'))) '-Profiles seven6moa: that profile gets the repo config' $r.Output
    Check (-not (Get-Same (Join-Path $h 'profiles/mylocal/config.yaml'))) '-Profiles seven6moa: mylocal is left alone' $r.Output
    $bak = @(Get-ChildItem (Join-Path $h 'profiles/seven6moa') -Filter 'config.yaml.bak-*')
    Check ($bak.Count -eq 1 -and (Get-Content $bak[0].FullName -Raw) -match 'stale-profiles-seven6moa') 'the profile was backed up, and the backup holds the OLD content' $r.Output

    $h = New-ApplyHome 'apply3'
    $r = Invoke-Child -ArgList @('-File', $apply, '-HermesHome', $h, '-CodexHome', $codex, '-Profiles', 'seven6moa', '-WhatIf')
    Check ((Get-Content (Join-Path $h 'config.yaml') -Raw) -match 'stale' -and (Get-Content (Join-Path $h 'profiles/seven6moa/config.yaml') -Raw) -match 'stale' -and
           @(Get-ChildItem $h -Recurse -Filter '*.bak-*').Count -eq 0) '-WhatIf with a profile: nothing written, no backups' $r.Output

    $h = New-ApplyHome 'apply4'
    $r = Invoke-Child -ArgList @('-File', $apply, '-HermesHome', $h, '-CodexHome', $codex, '-Profiles', 'seven6moa,nope')
    Check ($r.Code -ne 0 -and $r.Output -match "no such profile 'nope'" -and $r.Output -match 'have: ') 'an unknown profile name fails and lists the real ones' $r.Output
    Check ((Get-Content (Join-Path $h 'config.yaml') -Raw) -match 'stale' -and (Get-Content (Join-Path $h 'profiles/seven6moa/config.yaml') -Raw) -match 'stale') 'an unknown profile name fails BEFORE anything is written (root too)' $r.Output

    foreach ($bad in '../escape', 'a/b', '..', '.hidden', 'x..y') {
        $r = Invoke-Child -ArgList @('-File', $apply, '-HermesHome', $h, '-CodexHome', $codex, '-Profiles', $bad)
        Check ($r.Code -ne 0 -and $r.Output -match 'invalid profile name') "profile name '$bad' is refused" $r.Output
    }

    # ------------------------------------------------------------ update wrapper
    Write-Host "`nhermes-update-safe.ps1" -ForegroundColor Cyan
    $upd = Join-Path $Scripts 'hermes-update-safe.ps1'
    $ubin = Join-Path $Tmp 'ubin'; New-Item -ItemType Directory $ubin | Out-Null
    $urec = Join-Path $Tmp 'update-calls.txt'
    $ufake = Join-Path $ubin 'hermes'
    # Records every call. FAKE_UPDATE_EXIT makes `update` fail; FAKE_UPDATE_SED edits the
    # installed root config the way a real update's migration could.
    Set-Content $ufake -Value @"
#!/bin/sh
echo "`$*" >> '$urec'
if [ "`$1" = "update" ]; then
  [ -n "`$FAKE_UPDATE_SED" ] && sed -i "`$FAKE_UPDATE_SED" "`$HERMES_HOME/config.yaml"
  exit "`${FAKE_UPDATE_EXIT:-0}"
fi
exit 0
"@
    chmod +x $ufake
    function Get-Calls { if (Test-Path $urec) { @(Get-Content $urec) } else { @() } }
    function Reset-Calls { Remove-Item $urec -Force -ErrorAction SilentlyContinue }
    function Run-Update([string]$home_, [string[]]$more = @(), [hashtable]$env_ = @{}) {
        Reset-Calls
        $e2 = @{ HERMES_HOME = $home_ } + $env_
        return Invoke-Child -ArgList (@('-File', $upd) + $more) -Env $e2 -PathPrefix $ubin
    }

    $h = New-Home 'upd-ok'
    $r = Run-Update $h @('-Force', '-WaitSeconds', '0')
    $calls = Get-Calls
    Check ($r.Code -eq 0 -and $r.Output -match 'OK\s+updated, routing intact') 'healthy update: exits 0 and says routing intact' $r.Output
    Check (($calls -join '|') -eq 'gateway stop|update|gateway restart') 'order is: gateway stop, update, gateway restart' ($calls -join '|')
    Check (@(Get-ChildItem $h -Filter 'config.yaml.bak-*').Count -eq 1 -and @(Get-ChildItem $h -Recurse -Filter 'config.yaml.bak-*').Count -eq 3) 'root AND both profile configs were backed up' (@(Get-ChildItem $h -Recurse -Filter '*.bak-*').Name -join ', ')

    $h = New-Home 'upd-whatif'
    $r = Run-Update $h @('-WhatIf')
    Check ($r.Code -eq 0 -and (Get-Calls).Count -eq 0 -and @(Get-ChildItem $h -Recurse -Filter '*.bak-*').Count -eq 0 -and $r.Output -match 'WhatIf: nothing was stopped') '-WhatIf: hermes never called, no backups, says so' $r.Output

    $h = New-Home 'upd-fail'
    $r = Run-Update $h @('-Force', '-WaitSeconds', '0') @{ FAKE_UPDATE_EXIT = '3' }
    Check ($r.Code -eq 1 -and $r.Output -match 'hermes update exited 3') 'a failed update exits 1 and names the exit code' $r.Output
    Check (-not ((Get-Calls) -contains 'gateway restart')) 'a failed update does NOT restart the gateway' ((Get-Calls) -join '|')

    $h = New-Home 'upd-drift'
    $r = Run-Update $h @('-Force', '-WaitSeconds', '0') @{ FAKE_UPDATE_SED = 's#default: nvidia/nemotron-3.5-super-vl-120b-a12b#default: nvidia/nemotron-3-ultra-550b-a55b#' }
    Check ($r.Code -eq 1 -and $r.Output -match 'differs: model\.default' -and $r.Output -match 'changed routing') 'an update that changes routing: exit 1 and names model.default' $r.Output
    Check (-not ((Get-Calls) -contains 'gateway restart')) 'drifted routing is NOT restarted into service' ((Get-Calls) -join '|')
    Check ((Get-Content (Join-Path $h 'config.yaml') -Raw) -match 'ultra-550b') 'the script does not silently put the repo config back' $r.Output

    $h = New-Home 'upd-norestart'
    $r = Run-Update $h @('-Force', '-NoRestart')
    Check ($r.Code -eq 0 -and -not ((Get-Calls) -contains 'gateway restart') -and $r.Output -match 'NoRestart') '-NoRestart: updates and checks, leaves Hermes stopped' $r.Output

    $h = New-Home 'upd-nopy'
    $noPyPath = (Split-Path $Pwsh -Parent) + [IO.Path]::PathSeparator + $ubin
    Reset-Calls
    $r = Invoke-Child -ArgList @('-File', $upd, '-Force', '-WaitSeconds', '0') -Env @{ HERMES_HOME = $h; HERMES_DRIFT_PYTHON = (Join-Path $Tmp 'nope') } -PathOverride $noPyPath
    Check ($r.Code -eq 1 -and $r.Output -match 'drift NOT checked' -and -not ((Get-Calls) -contains 'gateway restart')) 'no Python: routing is UNVERIFIED, so no restart, and it says so' $r.Output

    # A process running out of the Hermes folder holds files open -- the WinError 5 case.
    $h = New-Home 'upd-lock'
    $lockBin = Join-Path $h 'tools'; New-Item -ItemType Directory $lockBin | Out-Null
    $sleepCopy = Join-Path $lockBin 'fake-hermes-python'
    Copy-Item (Get-Command sleep -CommandType Application | Select-Object -First 1).Source $sleepCopy
    $proc = Start-Process -FilePath $sleepCopy -ArgumentList '300' -PassThru
    try {
        Start-Sleep -Milliseconds 400
        $r = Run-Update $h @('-Force', '-WaitSeconds', '0')
        $proc.Refresh()
        Check ($r.Output -match "pid $($proc.Id)\s+fake-hermes-python") 'a process running from the Hermes folder is listed up front' $r.Output
        Check ($proc.HasExited) 'it was stopped before the update ran' $r.Output
        Check ($r.Code -eq 0 -and ((Get-Calls) -join '|') -eq 'gateway stop|update|gateway restart') 'and the update still ran, after it' ((Get-Calls) -join '|')
    } finally { if (-not $proc.HasExited) { $proc.Kill() } }

    # Declining the prompt must change nothing.
    $h = New-Home 'upd-no'
    Reset-Calls
    $saved = $env:HERMES_HOME; $savedP = $env:PATH
    $env:HERMES_HOME = $h; $env:PATH = "$ubin$([IO.Path]::PathSeparator)$env:PATH"
    try { $out = ('no' | & $Pwsh -NoLogo -NoProfile -File $upd 2>&1 | Out-String); $code = $LASTEXITCODE }
    finally { $env:HERMES_HOME = $saved; $env:PATH = $savedP }
    Check ($code -eq 0 -and $out -match 'cancelled' -and (Get-Calls).Count -eq 0 -and @(Get-ChildItem $h -Recurse -Filter '*.bak-*').Count -eq 0) 'answering anything but YES: nothing stopped, nothing backed up' $out
}
finally {
    Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Fail) { Write-Host "FAILED  $($script:Fail) failed, $($script:Pass) passed" -ForegroundColor Red; exit 1 }
Write-Host "OK      $($script:Pass) passed" -ForegroundColor Green
exit 0
