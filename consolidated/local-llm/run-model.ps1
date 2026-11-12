# Usage: .\run-model.ps1 spark|gemma [-Ctx 8192]   (single model, no router)
param([Parameter(Mandatory)][ValidateSet('spark','gemma')]$Name,[int]$Ctx=8192)
$pat = @{spark='Spark-X2.5-4B-Q4_K_M.gguf'; gemma='gemma-4-E4B-it-Q4_0.gguf'}[$Name]
$f = Get-ChildItem "$env:USERPROFILE\.cache\huggingface\hub" -Recurse -Filter $pat -ErrorAction SilentlyContinue | Select -First 1
if(-not $f){ Write-Error "Model file $pat not found in HF cache"; exit 1 }
Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force
$extra = if($Name -eq 'spark'){ @('--reasoning','off') } else { @() }
Write-Host "Starting $Name ($($f.Name)) ctx=$Ctx on http://127.0.0.1:8080/v1 ..."
llama-server -m $f.FullName -c $Ctx -t 2 -ngl 0 --host 127.0.0.1 --port 8080 --parallel 1 --jinja --alias local @extra
