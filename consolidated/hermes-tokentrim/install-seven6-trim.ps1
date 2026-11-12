<#
Installs the seven6-trim plugin into one Hermes profile and enables it in OBSERVE mode: nothing is trimmed,
sizes are logged to <profile>\seven6-trim.jsonl so the saving can be measured first.

  .\install-seven6-trim.ps1                  # profile seven6moa
  .\install-seven6-trim.ps1 -Profile default
  .\install-seven6-trim.ps1 -DryRun          # show what would happen, change nothing
  .\install-seven6-trim.ps1 -Remove          # disable the plugin and delete its folder (the log stays)

Afterwards:
  .\seven6-trim-report.ps1                   # per-tool sizes and the saving a trim would give
  hermes -p seven6moa config set plugins.entries.seven6-trim.settings.mode trim    # switch trimming on (restart Hermes)
  hermes -p seven6moa config set plugins.entries.seven6-trim.settings.mode observe # and back

config.yaml is copied to config.yaml.bak-trim-<stamp> before anything is enabled. Hermes needs a restart to load it.
#>
param([string]$Profile = 'seven6moa', [switch]$Remove, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$src  = Join-Path $PSScriptRoot 'plugins\seven6-trim'
$hh   = Join-Path $env:LOCALAPPDATA 'hermes'
$pdir = if ($Profile -eq 'default') { $hh } else { Join-Path $hh "profiles\$Profile" }
if (-not (Test-Path -LiteralPath $pdir)) { throw "Profile folder not found: $pdir" }
$dest = Join-Path $pdir 'plugins\seven6-trim'
$cfg  = Join-Path $pdir 'config.yaml'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$hp = if ($Profile -eq 'default') { @() } else { @('-p', $Profile) }

function Invoke-Hermes([string[]]$Rest) { & hermes @hp @Rest 2>&1 | Out-String -Width 200 }

if ($Remove) {
    "Removing seven6-trim from profile '$Profile'"
    if ($DryRun) { "dry run: would run 'hermes plugins disable seven6-trim' and delete $dest"; return }
    Invoke-Hermes @('plugins', 'disable', 'seven6-trim') | Write-Host
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -Confirm:$false; "deleted $dest" }
    "Done. The log (seven6-trim.jsonl) was left in place."
    return
}

if (-not (Test-Path -LiteralPath (Join-Path $src 'plugin.yaml'))) { throw "Plugin source not found: $src" }
"Installing seven6-trim into profile '$Profile' (observe mode)"
"  source: $src"
"  target: $dest"
if ($DryRun) { "dry run: would back up config.yaml, copy the plugin, run 'hermes plugins enable seven6-trim'"; return }

Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-trim-$stamp"
"  backup: $cfg.bak-trim-$stamp"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -LiteralPath (Join-Path $src 'plugin.yaml'), (Join-Path $src '__init__.py') -Destination $dest -Force

$v = Invoke-Hermes @('plugins', 'validate', $dest)
"  validate: " + (($v -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 3) -join ' | ')
Invoke-Hermes @('plugins', 'enable', 'seven6-trim') | Write-Host

$row = (Invoke-Hermes @('plugins', 'list')) -split "`r?`n" | Where-Object { $_ -match 'seven6-trim' } | Select-Object -First 1
if ($row -and $row -match 'enabled') { "OK: $($row.Trim())" } else { "CHECK: the plugin list did not show seven6-trim as enabled. Row: $row" }
""
"Restart Hermes to load it. Then use it normally for a while and run:  .\seven6-trim-report.ps1 -Profile $Profile"
"Undo:  .\install-seven6-trim.ps1 -Profile $Profile -Remove      (config backup: $cfg.bak-trim-$stamp)"
