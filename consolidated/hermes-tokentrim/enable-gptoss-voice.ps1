<#
Proves the gpt-oss-120b MoA voice (R6, Hugging Face router, pinned to Cerebras) through Hermes and, only if it answers,
switches it on in seven6moa's MoA panel.

  .\enable-gptoss-voice.ps1               # prove, then enable (flat list AND the default preset in config.yaml)
  .\enable-gptoss-voice.ps1 -ProveOnly    # prove, change nothing
  .\enable-gptoss-voice.ps1 -Disable      # switch it off again

Needs ONE valid HF_TOKEN line in seven6moa's .env with the "Make calls to Inference Providers" permission. If the audit
(check-api-keys.ps1) shows two HF_TOKEN lines for seven6moa, run  install-api-keys.ps1 -Only huggingface  first.
This script never reads or prints the token. Proof = a one-shot through provider custom:hf-gptoss whose usage report
names openai/gpt-oss-120b:cerebras; a Nemotron model in the report means a fallback answered, which counts as failure.
Costs a few cents of Hugging Face credit per run (about 12,500 input tokens at 0.35 per million).
#>
param([switch]$ProveOnly, [switch]$Disable)
$ErrorActionPreference = 'Stop'
$cfg   = Join-Path $env:LOCALAPPDATA 'hermes\profiles\seven6moa\config.yaml'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$rx    = '(?m)(model: openai/gpt-oss-120b:cerebras[ \t]*\r?\n[ \t]*reasoning_effort:[ \t]*\w+[ \t]*\r?\n[ \t]*enabled:)[ \t]*(true|false)'

function Set-Voice([bool]$On) {
    $t = [IO.File]::ReadAllText($cfg)
    $n = [regex]::Matches($t, $rx).Count
    if ($n -lt 1) { throw 'The gpt-oss voice entry was not found in config.yaml (expected model, reasoning_effort, enabled lines).' }
    Copy-Item -LiteralPath $cfg -Destination "$cfg.bak-gptoss-$stamp"
    $t = [regex]::Replace($t, $rx, ('$1 ' + $(if ($On) { 'true' } else { 'false' })))
    if ($On) { $t = $t.Replace('# R6 gpt-oss-120b on Cerebras via the Hugging Face router:', "# R6 gpt-oss-120b on Cerebras via the Hugging Face router [ENABLED $(Get-Date -Format yyyy-MM-dd) by enable-gptoss-voice.ps1]:") }
    [IO.File]::WriteAllText($cfg, $t, (New-Object Text.UTF8Encoding($false)))
    "R6 gpt-oss-120b is now $(if ($On) { 'ENABLED' } else { 'DISABLED' }) in $n place(s) (flat list and default preset). Backup: $cfg.bak-gptoss-$stamp"
    & hermes -p seven6moa moa list 2>&1 | Out-String -Width 200
}

if ($Disable) { Set-Voice $false; return }

$u = Join-Path $env:TEMP 'gptoss-proof.json'
Remove-Item -LiteralPath $u -Force -ErrorAction SilentlyContinue
# Hermes remembers a 401 on the pooled HF_TOKEN ("auth failed (401)" in `hermes auth list`) and may skip it afterwards;
# clearing that mark is harmless and lets the proof use the token as it is now.
& hermes -p seven6moa auth reset huggingface 2>&1 | Out-Null
$args1 = @('-p', 'seven6moa', '--provider', 'custom:hf-gptoss', '-m', 'openai/gpt-oss-120b:cerebras', '--usage-file', $u, '-z', '"Reply with exactly the single word PONG"')
'Proving the route: seven6moa -> custom:hf-gptoss -> openai/gpt-oss-120b:cerebras (up to 2 minutes)...'
$outF = Join-Path $env:TEMP 'gptoss-proof.out'
$p = Start-Process hermes -ArgumentList $args1 -RedirectStandardOutput $outF -RedirectStandardError (Join-Path $env:TEMP 'gptoss-proof.err') -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit(120000)) { & taskkill /T /F /PID $p.Id 2>&1 | Out-Null; 'The proof timed out after 120 s.' }
$answer = if (Test-Path -LiteralPath $outF) { (Get-Content -LiteralPath $outF -Raw) } else { '' }
$j = $null; if (Test-Path -LiteralPath $u) { try { $j = Get-Content -LiteralPath $u -Raw | ConvertFrom-Json } catch { } }
Remove-Item -LiteralPath $u, $outF, (Join-Path $env:TEMP 'gptoss-proof.err') -Force -ErrorAction SilentlyContinue

$ok = $j -and $j.completed -and -not $j.failed -and ($j.model -like 'openai/gpt-oss-120b*') -and ("$answer" -match 'PONG')
if ($j) { "Hermes reports: provider $($j.provider), model $($j.model), completed $($j.completed), input tokens $($j.input_tokens), output tokens $($j.output_tokens)" } else { 'No usage report was written.' }
if (-not $ok) {
    'NOT PROVEN. gpt-oss-120b did not answer through Hermes, so nothing was changed.'
    if ($j -and $j.model -notlike 'openai/gpt-oss-120b*') { "A fallback ($($j.model)) answered instead. The usual cause is HTTP 401: two HF_TOKEN lines in seven6moa's .env (Hermes reads the first), or a token without the inference permission. Run check-api-keys.ps1, then install-api-keys.ps1 -Only huggingface." }
    'To see the real error:  hermes -p seven6moa chat -q "Reply PONG" -Q -v --provider custom:hf-gptoss -m openai/gpt-oss-120b:cerebras'
    'Other causes: no Hugging Face credit left (HTTP 402), or Cerebras is down (HTTP 5xx; try again later).'
    exit 1
}
'PROVEN: gpt-oss-120b answered through the Hugging Face router.'
if ($ProveOnly) { 'ProveOnly: config.yaml was not changed.'; return }
Set-Voice $true
'Next:  .\seven6-smoke.ps1 -Checks moa     (a MoA turn must show gpt-oss-120b among the answering references)'
