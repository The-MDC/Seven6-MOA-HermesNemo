# MoA Advisor Probe — DeepSeek-V2 Q8 Usage Verification
# Per user constraint: prove the answering model with --usage-file
# Usage: powershell -ExecutionPolicy Bypass -File scripts/moa-advisor-probe.ps1

$ErrorActionPreference = "Stop"

$PROFILE = "seven6moa"
$ADVISOR_MODEL = "local:deepseek-v2:236b-chat-q8_0"
$USAGE_FILE = "$PSScriptRoot/../scratch/deepseek-v2-usage.json"
$TEST_PROMPT = "Explain chain-of-thought reasoning in one paragraph."

Write-Host "=== MoA Advisor Probe: DeepSeek-V2 Q8 ===" -ForegroundColor Cyan
Write-Host "Profile: $PROFILE"
Write-Host "Advisor: $ADVISOR_MODEL"
Write-Host "Usage file: $USAGE_FILE"
Write-Host ""

# Verify advisor is listed in MoA
Write-Host "Checking MoA listing for advisor..."
$moaOutput = hermes -p $PROFILE moa list 2>&1
if ($moaOutput -notmatch "deepseek-v2:236b-chat-q8_0") {
    Write-Host "ERROR: DeepSeek-V2 Q8 advisor not found in MoA listing!" -ForegroundColor Red
    exit 1
}
Write-Host "Advisor found in MoA listing.`n" -ForegroundColor Green

# Test call with --usage-file
Write-Host "Sending test prompt to DeepSeek-V2 Q8 advisor..."
Write-Host "Prompt: $TEST_PROMPT`n"

try {
    $result = hermes -p $PROFILE moa ask --model $ADVISOR_MODEL --prompt $TEST_PROMPT --usage-file $USAGE_FILE 2>&1
    Write-Host "=== Advisor Response ===" -ForegroundColor Cyan
    Write-Host $result
    Write-Host ""
} catch {
    Write-Host "ERROR calling advisor: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Verify usage file was written
if (-not (Test-Path $USAGE_FILE)) {
    Write-Host "ERROR: Usage file was not created at $USAGE_FILE" -ForegroundColor Red
    exit 1
}

$usageContent = Get-Content $USAGE_FILE -Raw
Write-Host "=== Usage File Contents ===" -ForegroundColor Cyan
Write-Host $usageContent
Write-Host ""

# Validate JSON
try {
    $usageJson = $usageContent | ConvertFrom-Json
    Write-Host "PASS: Usage file is valid JSON" -ForegroundColor Green
    Write-Host "Tokens used: $($usageJson.total_tokens | Select-Object -First 1)"
    Write-Host "Model: $($usageJson.model | Select-Object -First 1)"
} catch {
    Write-Host "WARNING: Usage file is not valid JSON (raw content shown above)" -ForegroundColor Yellow
}

Write-Host "`n=== Probe Complete ===" -ForegroundColor Cyan
