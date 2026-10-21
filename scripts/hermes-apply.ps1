<#
.SYNOPSIS
  Install this repo's Hermes and Codex configs onto the machine, with backups.

.DESCRIPTION
  Copies configs/hermes/config.yaml  -> $HERMES_HOME\config.yaml
         configs/codex/config.toml   -> ~\.codex\config.toml

  Every existing file is backed up to <name>.bak-<timestamp> FIRST. Nothing is
  overwritten without a copy surviving, because the deployed config has drifted
  from this repo before (docs/models/HANDOFF-NEXT-SESSION.md) and the deployed side
  may hold changes nobody wrote down.

  Profiles are OPT-IN. By default only the root config is written. A profile's config
  may differ from the root on purpose, and this script has no way to know which
  differences are deliberate, so -Profiles <name,...> replaces the NAMED profile's
  config.yaml with the repo copy (backed up first), and nothing else is touched.
  Names are checked against the profiles that exist; an unknown name stops the run
  before any file is written.

  Touches no .env and no credential. Keys are read by Hermes from
  $HERMES_HOME\.env at runtime and are none of this script's business.

.EXAMPLE
  pwsh -File scripts/hermes-apply.ps1 -WhatIf   # show what would change
  pwsh -File scripts/hermes-apply.ps1
  pwsh -File scripts/hermes-apply.ps1 -Profiles seven6moa -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$HermesHome,
    [string]$CodexHome  = $(Join-Path $HOME '.codex'),

    # Named profiles (under <HermesHome>/profiles) to overwrite with the repo config.
    # Default: none. Names are letters, digits, '.', '_' and '-' only.
    [string[]]$Profiles = @()
)

. (Join-Path $PSScriptRoot 'hermes-common.ps1')
if (-not $HermesHome) { $HermesHome = Get-HermesHomePath }
$Profiles = @(Split-NameList $Profiles)   # -File delivers "a,b" as one string

$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$repo  = Split-Path $PSScriptRoot -Parent

function Install-One {
    param([string]$Source, [string]$Target)

    if (-not (Test-Path $Source)) { throw "source missing: $Source" }

    $dir = Split-Path $Target -Parent
    if (-not (Test-Path $dir)) {
        if ($PSCmdlet.ShouldProcess($dir, 'create directory')) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    if (Test-Path $Target) {
        # Identical content is not worth a backup file; drift is.
        if ((Get-FileHash $Source).Hash -eq (Get-FileHash $Target).Hash) {
            Write-Host "  unchanged  $Target" -ForegroundColor DarkGray
            return
        }
        $backup = "$Target.bak-$stamp"
        if ($PSCmdlet.ShouldProcess($Target, "back up to $(Split-Path $backup -Leaf)")) {
            Copy-Item $Target $backup -Force
            Write-Host "  backed up  $(Split-Path $backup -Leaf)" -ForegroundColor Yellow
        }
    }

    if ($PSCmdlet.ShouldProcess($Target, 'install')) {
        Copy-Item $Source $Target -Force
        Write-Host "  installed  $Target" -ForegroundColor Green
    }
}

# Validate every requested profile BEFORE writing anything, so a typo cannot leave
# the root installed and the profile skipped.
$profileDirs = @()
foreach ($name in $Profiles) {
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $name -match '\.\.') {
        throw "invalid profile name '$name' (letters, digits, '.', '_', '-' only)"
    }
    $dir = Join-Path (Join-Path $HermesHome 'profiles') $name
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        $have = @(Get-ChildItem (Join-Path $HermesHome 'profiles') -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
        throw "no such profile '$name' under $HermesHome\profiles (have: $(if ($have) { $have -join ', ' } else { 'none' }))"
    }
    $profileDirs += $dir
}

Write-Host "hermes home: $HermesHome"
Write-Host "codex home:  $CodexHome"
Write-Host "profiles:    $(if ($Profiles) { $Profiles -join ', ' } else { 'none (root config only)' })`n"

$hermesCfg = Join-Path (Join-Path (Join-Path $repo 'configs') 'hermes') 'config.yaml'
$codexCfg  = Join-Path (Join-Path (Join-Path $repo 'configs') 'codex')  'config.toml'

Install-One $hermesCfg (Join-Path $HermesHome 'config.yaml')
foreach ($dir in $profileDirs) { Install-One $hermesCfg (Join-Path $dir 'config.yaml') }
Install-One $codexCfg (Join-Path $CodexHome 'config.toml')

Write-Host @"

Five environment variables the config references by name, not value:

  HERMES_SKILLS_SERVER     full path to skills-mcp-server\dist\index.js
  HERMES_COUNCIL_LAUNCHER  full path to scripts\hermes-council-launch.cmd
  HERMES_COUNCIL_PYTHON    the interpreter that HAS hermes_council installed
  HERMES_CODEX_LAUNCHER    full path to scripts\codex-mcp-launch.cmd
  HERMES_CODEX_NODE        the node.exe the Codex shim should pin

Set them for your user so Hermes resolves the local MCP subprocesses:

  [Environment]::SetEnvironmentVariable('HERMES_SKILLS_SERVER','<path>','User')
  [Environment]::SetEnvironmentVariable('HERMES_COUNCIL_LAUNCHER','<repo>\scripts\hermes-council-launch.cmd','User')
  [Environment]::SetEnvironmentVariable('HERMES_COUNCIL_PYTHON',(Get-Command python).Source,'User')
  [Environment]::SetEnvironmentVariable('HERMES_CODEX_LAUNCHER','<repo>\scripts\codex-mcp-launch.cmd','User')
  [Environment]::SetEnvironmentVariable('HERMES_CODEX_NODE',(Get-Command node).Source,'User')

NOT HERMES_VENV_PYTHON. This block used to name it, and pointing at the venv was
the bug: the supervisor substitutes its own Python for a bare `command`, so the
import ran where the packages were not. The launcher is indirection the
supervisor cannot reach through, and HERMES_COUNCIL_PYTHON is what the launcher
itself pins. hermes-verify.ps1 checks the launcher; nothing reads VENV_PYTHON.

Open a new shell afterwards -- 'User' scope does not affect the current one.
Then verify before routing any real work through it:

  pwsh -File scripts/hermes-verify.ps1
"@
