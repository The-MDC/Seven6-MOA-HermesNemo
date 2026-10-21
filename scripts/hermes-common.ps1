<#
.SYNOPSIS
  Shared helpers for the Hermes box scripts. Dot-source it; it runs nothing itself.

    . (Join-Path $PSScriptRoot 'hermes-common.ps1')

  Kept as one file in scripts/ rather than a subfolder because the CI PowerShell
  syntax step parses scripts/*.ps1 only: a helper nobody parses is how a typo ships.
#>

function Get-HermesHomePath {
    if ($env:HERMES_HOME) { return $env:HERMES_HOME }
    # Windows: %LOCALAPPDATA%\hermes. Elsewhere Hermes keeps ~/.hermes.
    if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'hermes') }
    return (Join-Path $HOME '.hermes')
}

# `pwsh -File script.ps1 -Names a,b` hands a [string[]] parameter ONE string, "a,b" --
# the comma list only becomes an array when the call is made from inside PowerShell.
# Scripts run both ways, so every list parameter goes through this.
function Split-NameList([string[]]$Value) {
    @($Value | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# An interpreter that can `import yaml`. Tried in this order, and each candidate is
# PROVEN rather than assumed:
#   1. $env:HERMES_DRIFT_PYTHON      an explicit choice always wins
#   2. Hermes' own venv(s)           Hermes parses this very file, so PyYAML is there
#   3. python / python3 / py -3      whatever is on PATH, which on a stock Windows box
#                                    is often the Microsoft Store stub that only opens
#                                    the Store -- the import test is what rejects it
# Returns $null when none can, and the caller must SAY so: a check that silently does
# not run reads as a check that passed.
function Find-YamlPython {
    $cands = New-Object System.Collections.Generic.List[object]
    if ($env:HERMES_DRIFT_PYTHON) { $cands.Add(@($env:HERMES_DRIFT_PYTHON)) }

    $pattern = Join-Path (Get-HermesHomePath) 'installs/*/environments/*/venv/Scripts/python.exe'
    foreach ($f in @(Get-ChildItem $pattern -ErrorAction SilentlyContinue)) { $cands.Add(@($f.FullName)) }

    foreach ($n in 'python', 'python3') {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { $cands.Add(@($c.Source)) }
    }
    $py = Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($py) { $cands.Add(@($py.Source, '-3')) }

    foreach ($c in $cands) {
        try {
            $exe = $c[0]; $pre = @($c | Select-Object -Skip 1)
            & $exe @pre -I -c 'import yaml' 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { return ,$c }
        } catch { }
    }
    return $null
}

# Run scripts/check-config-drift.py on one file. Returns Code (0 clean, 1 failure,
# 2 unreadable) and the text it printed. The tool prints ids and paths only.
function Invoke-DriftCheck {
    param(
        [Parameter(Mandatory)] $Python,        # the array Find-YamlPython returned
        [Parameter(Mandatory)] [string]$Tool,
        [Parameter(Mandatory)] [string]$Golden,
        [Parameter(Mandatory)] [string]$Installed,
        [Parameter(Mandatory)] [string]$Label,
        [switch]$Profile,
        [switch]$Strict
    )
    $exe = $Python[0]; $pre = @($Python | Select-Object -Skip 1)
    $a = @('-I', $Tool, '--golden', $Golden, '--installed', $Installed, '--label', $Label)
    if ($Profile) { $a += '--profile' }
    if ($Strict)  { $a += '--strict' }
    $out = (& $exe @pre @a 2>&1 | Out-String)
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
}

# Every process whose image lives under the Hermes home: the gateway, the dashboard,
# Desktop's backend, the installer's Python. These are the files the installer wants
# to rename, and an open handle on any of them is `[WinError 5] Access is denied`.
function Get-HermesProcess {
    $root = (Get-HermesHomePath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -ne $PID -and $_.Path -and $_.Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) } |
        Select-Object Id, ProcessName, Path
}

# ---------------------------------------------------------------- dashboard autostart
# Hermes Desktop's "connect to existing Hermes" talks to `hermes dashboard`, not to the
# gateway's API port. The dashboard mints a RANDOM session token on every start unless
# HERMES_DASHBOARD_SESSION_TOKEN is set, so without a pinned token and something that
# starts it at login, Desktop has nothing to connect to after every reboot.
$script:DashboardTaskName = 'Hermes Dashboard'
$script:DashboardTokenVar = 'HERMES_DASHBOARD_SESSION_TOKEN'
$script:DashboardPort     = 9119

# 'User' scope is a Windows registry concept. Elsewhere it is a silent no-op, which would
# make every read return nothing -- so off Windows these fall back to the process scope.
# That fallback exists so the logic can be exercised in CI; the box is Windows.
function Get-UserEnvVar([string]$Name) {
    if ($IsWindows) { return [Environment]::GetEnvironmentVariable($Name, 'User') }
    return [Environment]::GetEnvironmentVariable($Name)
}
function Set-UserEnvVar([string]$Name, [string]$Value) {
    if ($IsWindows) { [Environment]::SetEnvironmentVariable($Name, $Value, 'User') }
    else            { [Environment]::SetEnvironmentVariable($Name, $Value) }
}

function New-DashboardToken {
    # 32 bytes from the OS CSPRNG, hex. Never Get-Random: that one is not.
    [Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
}

function Test-LocalPort {
    param([string]$HostName = '127.0.0.1', [int]$Port, [int]$TimeoutMs = 2000)
    $client = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $async  = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        try { $client.EndConnect($async); return $true } catch { return $false }
    } catch { return $false }
    finally { if ($client) { $client.Close() } }
}

# Read-only. Reports facts about the autostart; never returns or prints the token.
function Get-DashboardAutostart {
    $tok = Get-UserEnvVar $script:DashboardTokenVar
    $task = $null
    if ($IsWindows -and (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        $task = Get-ScheduledTask -TaskName $script:DashboardTaskName -ErrorAction SilentlyContinue
    }
    $startup = $null
    if ($IsWindows) {
        $f = Join-Path ([Environment]::GetFolderPath('Startup')) 'Hermes Dashboard.vbs'
        if (Test-Path $f) { $startup = $f }
    }
    [pscustomobject]@{
        TokenSet    = [bool]$tok
        TokenLength = if ($tok) { $tok.Length } else { 0 }
        Task        = $task
        StartupFile = $startup
        Listening   = (Test-LocalPort -Port $script:DashboardPort)
    }
}
