<#
.SYNOPSIS
  Start `hermes dashboard` with the pinned session token. What the login task runs.

.DESCRIPTION
  Reads HERMES_DASHBOARD_SESSION_TOKEN from the USER environment (so it works from a
  scheduled task, which does not inherit an interactive shell), exports it into this
  process only, and runs the dashboard in the foreground. Bound to loopback: the token
  travels over plain HTTP, which is only acceptable on 127.0.0.1.

  Exits at once if something already answers on the port, so a manual dashboard
  window and the login task cannot fight over it. Logs to $HERMES_HOME\dashboard-launch.log;
  the token is never logged.

  Install the login task with scripts/hermes-dashboard-autostart.ps1.
#>
[CmdletBinding()]
param(
    [int]$Port = 9119,
    [ValidateSet('127.0.0.1', 'localhost', '::1')]
    [string]$BindHost = '127.0.0.1'
)

. (Join-Path $PSScriptRoot 'hermes-common.ps1')

$log = Join-Path (Get-HermesHomePath) 'dashboard-launch.log'
function Write-Log([string]$m) {
    try { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format s), $m) } catch { }
}

if (Test-LocalPort -HostName $BindHost -Port $Port) {
    Write-Log "port $Port already answering; not starting a second dashboard"
    exit 0
}

$token = Get-UserEnvVar $script:DashboardTokenVar
if (-not $token) {
    Write-Log "no $($script:DashboardTokenVar) in the User environment; run scripts/hermes-dashboard-autostart.ps1 -Action Install"
    exit 78
}

$hermes = Get-Command hermes -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $hermes) { Write-Log 'hermes is not on PATH for this logon session'; exit 127 }

$env:HERMES_DASHBOARD_SESSION_TOKEN = $token
Write-Log "starting dashboard on ${BindHost}:$Port"
& $hermes.Source dashboard --no-open --host $BindHost --port $Port
$code = $LASTEXITCODE
Write-Log "dashboard exited with code $code"
exit $code
