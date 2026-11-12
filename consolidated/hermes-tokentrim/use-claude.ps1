param(
    [string]$ProfileName = 'default',
    [string]$Model = 'claude-sonnet-5-5',
    [string]$Reasoning = 'medium',
    [string]$Key,                 # optional; normally leave it out and paste at the hidden prompt (keeps the key out of shell history)
    [switch]$NoFallback
)
# Makes Claude the model of one Hermes profile, using a real Anthropic API key (pay-per-token on console.anthropic.com).
# Never touches Claude Code's login and never reads ~/.claude. The key is validated before anything is written.
$ErrorActionPreference = 'Stop'
$homeDir = if ($ProfileName -eq 'default') { Join-Path $env:LOCALAPPDATA 'hermes' } else { Join-Path $env:LOCALAPPDATA "hermes\profiles\$ProfileName" }
$envFile = Join-Path $homeDir '.env'
$cfgFile = Join-Path $homeDir 'config.yaml'
if (-not (Test-Path $envFile) -or -not (Test-Path $cfgFile)) { throw "Hermes profile '$ProfileName' not found at $homeDir" }

if (-not $Key) {
    $sec = Read-Host 'Paste your Anthropic API key (starts with sk-ant-api...; input is hidden)' -AsSecureString
    $Key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$Key = $Key.Trim().Trim('"').Trim("'")
if ($Key -notlike 'sk-ant-api*') {
    'That is not an Anthropic API key (it must start with sk-ant-api). Subscription/OAuth tokens (sk-ant-oat...) cannot be used here. Nothing was changed.'
    return
}
try {
    $r = Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/models?limit=100' -Headers @{ 'x-api-key' = $Key; 'anthropic-version' = '2023-06-01' } -TimeoutSec 30
} catch {
    $code = $null; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
    "Anthropic rejected the key (HTTP $code). Nothing was changed."
    return
}
$ids = @($r.data | ForEach-Object { $_.id })
"Key accepted. Claude models on this key: " + (($ids | Where-Object { $_ -match 'sonnet|opus|haiku|fable' } | Sort-Object) -join ', ')
if ($ids -notcontains $Model) { "Model '$Model' is not available on this key. Re-run with -Model <one of the ids above>. Nothing was changed."; return }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item $envFile "$envFile.bak-claude-$stamp"
Copy-Item $cfgFile "$cfgFile.bak-claude-$stamp"
$t = [IO.File]::ReadAllText($envFile)
if ($t -match '(?m)^\s*ANTHROPIC_API_KEY\s*=') { $t = [regex]::Replace($t, '(?m)^\s*ANTHROPIC_API_KEY\s*=.*$', { param($m) 'ANTHROPIC_API_KEY=' + $Key }) }
else { $t = $t.TrimEnd() + "`nANTHROPIC_API_KEY=" + $Key + "`n" }
[IO.File]::WriteAllText($envFile, $t, (New-Object Text.UTF8Encoding($false)))
$Key = $null

hermes -p $ProfileName config set model.provider anthropic --force | Out-Null      # also clears the old NVIDIA base_url / api_mode
hermes -p $ProfileName config set model.default $Model --force | Out-Null
foreach ($k in 'model.top_p', 'model.temperature') { hermes -p $ProfileName config unset $k 2>$null | Out-Null }
hermes -p $ProfileName config set auth.adopt_external_logins false --force | Out-Null   # use only Hermes' own logins; never borrow Claude Code's
hermes -p $ProfileName config set agent.reasoning_effort $Reasoning --force | Out-Null
if (-not $NoFallback) {
    $cfg = [IO.File]::ReadAllText($cfgFile)
    if ($cfg -notmatch '(?m)^fallback_providers:') {
        $blk = "`nfallback_providers:`n  - provider: nvidia`n    model: nvidia/nemotron-3.5-super-vl-120b-a12b`n"
        [IO.File]::AppendAllText($cfgFile, $blk, (New-Object Text.UTF8Encoding($false)))
        'Fallback if Claude is rate-limited/unavailable: NVIDIA Nemotron 3.5 Super VL.'
    }
}
"Profile '$ProfileName' now uses $Model (reasoning: $Reasoning). Backups: .env.bak-claude-$stamp, config.yaml.bak-claude-$stamp"
"Smoke test..."
hermes -p $ProfileName -z 'Reply with the single word: ready'
"Undo: restore the two .bak-claude-$stamp files over .env and config.yaml in $homeDir"
