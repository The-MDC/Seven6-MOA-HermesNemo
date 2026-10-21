<#
.SYNOPSIS
  Pin the dashboard session token and start `hermes dashboard` at every login.

.DESCRIPTION
  Hermes Desktop's "Connect to existing Hermes" talks to the dashboard (port 9119), and
  the dashboard mints a random session token each start. So after every reboot Desktop
  has nothing to connect to, and after every manual restart its saved token is stale.

  Install does three things, each under -WhatIf / -Confirm:
    1. Sets HERMES_DASHBOARD_SESSION_TOKEN for your USER, once. An existing token is
       KEPT (a rotate is a separate, explicit switch). The token is copied to the
       clipboard so you can paste it into Desktop; it is never printed.
    2. Registers a per-user logon task "Hermes Dashboard" that runs
       scripts/hermes-dashboard-launch.ps1 hidden, restarts it up to 3 times if it
       dies, and keeps it running on battery. No admin rights. If Windows refuses the
       task, falls back to a hidden launcher in your Startup folder.
    3. Does NOT start anything unless you pass -StartNow.

  Status (the default) changes nothing: it reports the token (set or not, never the
  value), the task, the Startup fallback, whether the port answers, and what /api/status
  says. Remove undoes step 2 and leaves the token unless -RemoveToken is given.

  WHERE THE TOKEN LIVES: your user environment (HKCU\Environment), readable by your own
  processes -- the same trust level as the keys in Hermes' .env. It is not a login
  credential: the dashboard is bound to 127.0.0.1, and the token gates its sensitive
  /api routes and the websocket Desktop uses.

.EXAMPLE
  pwsh -File scripts/hermes-dashboard-autostart.ps1                      # status
  pwsh -File scripts/hermes-dashboard-autostart.ps1 -Action Install -WhatIf
  pwsh -File scripts/hermes-dashboard-autostart.ps1 -Action Install -StartNow
  pwsh -File scripts/hermes-dashboard-autostart.ps1 -Action Remove
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Status', 'Install', 'Remove')]
    [string]$Action = 'Status',

    # Generate a NEW token even though one is set. Desktop must be given the new one.
    [switch]$RotateToken,

    # With Remove: also delete the token from the user environment.
    [switch]$RemoveToken,

    # With Install: start the dashboard now instead of waiting for the next login.
    # Close any dashboard you started by hand first; the launcher will not start a second.
    [switch]$StartNow
)

. (Join-Path $PSScriptRoot 'hermes-common.ps1')

$ErrorActionPreference = 'Stop'
$Launcher = Join-Path $PSScriptRoot 'hermes-dashboard-launch.ps1'

function Get-PwshPath {
    $p = (Get-Process -Id $PID).Path
    if ($p -and (Split-Path $p -Leaf) -match '^pwsh') { return $p }
    $c = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    throw 'pwsh (PowerShell 7) not found - the launcher needs it'
}

# The command the task / Startup file runs. One definition, used by both and by the test.
function Get-LauncherArguments {
    param([string]$LauncherPath)
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $LauncherPath
}

function Show-Status {
    $s = Get-DashboardAutostart
    Write-Host 'dashboard autostart' -ForegroundColor Cyan
    if ($s.TokenSet) { Write-Host "  ok    $($script:DashboardTokenVar) is set for your user ($($s.TokenLength) chars; value not shown)" -ForegroundColor Green }
    else             { Write-Host "  warn  $($script:DashboardTokenVar) is NOT set - the dashboard mints a new random token every start" -ForegroundColor Yellow }

    if ($s.Task) {
        $info = Get-ScheduledTaskInfo -TaskName $script:DashboardTaskName -ErrorAction SilentlyContinue
        Write-Host "  ok    scheduled task '$($script:DashboardTaskName)': state $($s.Task.State), last result $($info.LastTaskResult)" -ForegroundColor Green
        $exe = ($s.Task.Actions | Select-Object -First 1).Arguments
        if ($exe -match '-File "([^"]+)"' -and -not (Test-Path $Matches[1])) {
            Write-Host "  FAIL  the task points at a launcher that no longer exists: $($Matches[1]) - rerun -Action Install from the current checkout" -ForegroundColor Red
        }
    } elseif ($s.StartupFile) {
        Write-Host "  ok    Startup-folder launcher present: $($s.StartupFile)" -ForegroundColor Green
    } else {
        Write-Host "  warn  nothing starts the dashboard at login - Desktop cannot connect after a reboot until you start it by hand" -ForegroundColor Yellow
    }

    if ($s.Listening) {
        Write-Host "  ok    something answers on 127.0.0.1:$($script:DashboardPort)" -ForegroundColor Green
        try {
            $st = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:DashboardPort)/api/status" -TimeoutSec 5
            Write-Host "  ..    dashboard $($st.version), overall '$($st.overall)', gateway '$($st.gateway_state)'" -ForegroundColor DarkGray
        } catch { Write-Host "  warn  port answers but /api/status did not: $($_.Exception.Message)" -ForegroundColor Yellow }
    } else {
        Write-Host "  ..    nothing listening on 127.0.0.1:$($script:DashboardPort) right now" -ForegroundColor DarkGray
    }

    # Other things that already start Hermes at login, so a second mechanism is never
    # added blind. Names only.
    if ($IsWindows) {
        $others = @()
        if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
            $others += @(Get-ScheduledTask -ErrorAction SilentlyContinue |
                Where-Object { $_.TaskName -match 'hermes' -and $_.TaskName -ne $script:DashboardTaskName } |
                ForEach-Object { "task: $($_.TaskName)" })
        }
        $startupDir = [Environment]::GetFolderPath('Startup')
        $others += @(Get-ChildItem $startupDir -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'hermes' -and $_.Name -ne 'Hermes Dashboard.vbs' } |
            ForEach-Object { "startup file: $($_.Name)" })
        if ($others) { Write-Host "  ..    other Hermes autostarts: $($others -join '; ')" -ForegroundColor DarkGray }
    }
}

function Install-Autostart {
    if (-not (Test-Path $Launcher)) { throw "launcher missing: $Launcher" }
    $pwsh = Get-PwshPath

    # 1. token
    $existing = Get-UserEnvVar $script:DashboardTokenVar
    if ($existing -and -not $RotateToken) {
        Write-Host "  kept  existing $($script:DashboardTokenVar) (use -RotateToken to replace it; Desktop would need the new one)" -ForegroundColor DarkGray
    } else {
        $verb = if ($existing) { 'rotate' } else { 'create' }
        if ($PSCmdlet.ShouldProcess("$($script:DashboardTokenVar) (user environment)", "$verb the pinned dashboard token")) {
            $new = New-DashboardToken
            Set-UserEnvVar $script:DashboardTokenVar $new
            try { Set-Clipboard -Value $new; $clip = 'copied to your clipboard' } catch { $clip = 'NOT copied (no clipboard) - read it with: [Environment]::GetEnvironmentVariable(''HERMES_DASHBOARD_SESSION_TOKEN'',''User'')' }
            Remove-Variable new
            Write-Host "  done  token $($verb)d; $clip. Paste it into Desktop > Connect to existing Hermes > Session token." -ForegroundColor Green
        }
    }

    # 2. task, with a Startup-folder fallback. Windows only: off Windows there is no
    # Task Scheduler and no Startup folder, so say so instead of pretending.
    if (-not $IsWindows) {
        Write-Host '  skip  the logon task is Windows-only; only the token step ran here' -ForegroundColor Yellow
        return
    }
    $taskArgs = Get-LauncherArguments -LauncherPath $Launcher
    $registered = $false
    if (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess("scheduled task '$($script:DashboardTaskName)'", "register (at logon, hidden, restart on failure)")) {
            try {
                $user      = "$env:USERDOMAIN\$env:USERNAME"
                $action    = New-ScheduledTaskAction -Execute $pwsh -Argument $taskArgs
                $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
                $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
                $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                                -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 3 `
                                -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
                Register-ScheduledTask -TaskName $script:DashboardTaskName -Action $action -Trigger $trigger `
                    -Principal $principal -Settings $settings -Force `
                    -Description 'Starts hermes dashboard on 127.0.0.1 for Hermes Desktop, with the pinned session token.' | Out-Null
                $registered = $true
                Write-Host "  done  registered task '$($script:DashboardTaskName)'" -ForegroundColor Green
            } catch {
                Write-Host "  warn  Windows refused the task ($($_.Exception.Message.Trim())); using the Startup folder instead" -ForegroundColor Yellow
            }
        }
    }
    if (-not $registered -and $PSCmdlet.ShouldProcess((Join-Path ([Environment]::GetFolderPath('Startup')) 'Hermes Dashboard.vbs'), 'write hidden Startup launcher')) {
        $vbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'Hermes Dashboard.vbs'
        $cmd = ('"{0}" {1}' -f $pwsh, $taskArgs) -replace '"', '""'
        Set-Content -Path $vbs -Encoding ASCII -Value "CreateObject(""WScript.Shell"").Run ""$cmd"", 0, False"
        Write-Host "  done  wrote $vbs" -ForegroundColor Green
    }

    # 3. optional start
    if ($StartNow) {
        if ($PSCmdlet.ShouldProcess('hermes dashboard', 'start now')) {
            if (Test-LocalPort -Port $script:DashboardPort) {
                Write-Host "  skip  something already answers on 127.0.0.1:$($script:DashboardPort). Close it first if it is a hand-started dashboard: it holds an older random token." -ForegroundColor Yellow
            } elseif ($registered) {
                Start-ScheduledTask -TaskName $script:DashboardTaskName
                Write-Host '  done  started; give it up to a minute, then run this script with no arguments' -ForegroundColor Green
            } else {
                Start-Process -FilePath $pwsh -ArgumentList $taskArgs -WindowStyle Hidden
                Write-Host '  done  started; give it up to a minute, then run this script with no arguments' -ForegroundColor Green
            }
        }
    } else {
        Write-Host '  ..    not started now. It starts at your next login, or rerun with -StartNow.' -ForegroundColor DarkGray
    }
}

function Remove-Autostart {
    if (-not $IsWindows) { throw 'Remove undoes a Windows logon task; run it on the Windows box.' }
    if ((Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) -and
        (Get-ScheduledTask -TaskName $script:DashboardTaskName -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess("scheduled task '$($script:DashboardTaskName)'", 'remove')) {
            Unregister-ScheduledTask -TaskName $script:DashboardTaskName -Confirm:$false
            Write-Host "  done  removed task '$($script:DashboardTaskName)'" -ForegroundColor Green
        }
    }
    $vbs = Join-Path ([Environment]::GetFolderPath('Startup')) 'Hermes Dashboard.vbs'
    if ((Test-Path $vbs) -and $PSCmdlet.ShouldProcess($vbs, 'remove')) {
        Remove-Item $vbs -Force
        Write-Host "  done  removed $vbs" -ForegroundColor Green
    }
    if ($RemoveToken) {
        if ($PSCmdlet.ShouldProcess("$($script:DashboardTokenVar) (user environment)", 'delete')) {
            Set-UserEnvVar $script:DashboardTokenVar $null
            Write-Host '  done  token deleted from your user environment' -ForegroundColor Green
        }
    } else {
        Write-Host "  kept  $($script:DashboardTokenVar) (add -RemoveToken to delete it)" -ForegroundColor DarkGray
    }
    Write-Host '  ..    a dashboard that is already running keeps running until it exits' -ForegroundColor DarkGray
}

# Dot-sourcing (the tests do) must define the functions and run nothing.
if ($MyInvocation.InvocationName -ne '.') {
    switch ($Action) {
        'Status'  { Show-Status }
        'Install' { Install-Autostart; Write-Host ''; Show-Status }
        'Remove'  { Remove-Autostart;  Write-Host ''; Show-Status }
    }
}
