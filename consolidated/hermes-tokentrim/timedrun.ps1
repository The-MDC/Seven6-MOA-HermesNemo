param([Parameter(Mandatory)][string]$ProfileName, [Parameter(Mandatory)][string]$Prompt, [int]$TimeoutSec = 180, [string[]]$Extra = @())
# One-shot Hermes call with a hard time limit (kills the whole process tree on timeout). Prints elapsed seconds, exit state and the answer.
$out = Join-Path $env:TEMP "timedrun-$ProfileName.out"; $err = Join-Path $env:TEMP "timedrun-$ProfileName.err"
$p = Start-Process hermes -ArgumentList (@('-p', $ProfileName) + $Extra + @('-z', ('"' + $Prompt + '"'))) -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
$sw = [Diagnostics.Stopwatch]::StartNew()
while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) { Start-Sleep -Milliseconds 500 }
$timedOut = -not $p.HasExited
if ($timedOut) { taskkill /T /F /PID $p.Id 2>&1 | Out-Null }
'{0,-10} elapsed {1,5:N0} s  {2}' -f $ProfileName, $sw.Elapsed.TotalSeconds, $(if ($timedOut) { 'TIMED OUT (killed)' } else { 'finished' })
$a = (Get-Content $out -Raw -ErrorAction SilentlyContinue); if ($a) { 'answer: ' + $a.Trim() }
$e = (Get-Content $err -Raw -ErrorAction SilentlyContinue); if ($e -and $e.Trim()) { 'stderr: ' + $e.Trim().Substring(0, [Math]::Min(300, $e.Trim().Length)) }
Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
