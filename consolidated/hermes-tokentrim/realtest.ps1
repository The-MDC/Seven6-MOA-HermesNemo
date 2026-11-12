param([Parameter(Mandatory)][string]$ProfileName, [Parameter(Mandatory)][string]$Prompt, [switch]$Flow, [string]$Provider, [string]$Model)
# One real one-shot call through a Hermes profile: elapsed time, answer, token usage and (with -Flow) the tool-call flow.
# Optional -Provider/-Model override the profile's model for this call only (nothing is saved).
$uf = Join-Path $env:TEMP "hermes-usage-$ProfileName.json"
if (Test-Path $uf) { Remove-Item $uf -Force }
$cli = @('-p', $ProfileName, '--usage-file', $uf)
if ($Provider) { $cli += @('--provider', $Provider) }
if ($Model)    { $cli += @('-m', $Model) }
$sw = [Diagnostics.Stopwatch]::StartNew()
$out = hermes @cli -z $Prompt 2>&1 | Out-String
$sw.Stop()
"elapsed: {0:N0} s" -f $sw.Elapsed.TotalSeconds
"answer : " + $out.Trim()
if (Test-Path $uf) {
    $u = Get-Content $uf -Raw | ConvertFrom-Json
    "usage  : api_calls {0} | input {1:N0} + cache_read {2:N0} + output {3:N0} (reasoning {4:N0}) = {5:N0} tokens | model {6} | completed {7}" -f $u.api_calls, $u.input_tokens, $u.cache_read_tokens, $u.output_tokens, $u.reasoning_tokens, $u.total_tokens, $u.model, $u.completed
    Remove-Item $uf -Force
}
if ($Flow) {
    $h = if ($ProfileName -eq 'default') { Join-Path $env:LOCALAPPDATA 'hermes' } else { Join-Path $env:LOCALAPPDATA "hermes\profiles\$ProfileName" }
    python -I (Join-Path $PSScriptRoot 'sessflow.py') (Join-Path $h 'state.db') 2>&1 | ForEach-Object { $_ }
}
