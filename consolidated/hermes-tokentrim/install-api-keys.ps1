param(
    [string]$KeysFile = (Join-Path $env:USERPROFILE 'Desktop\List of API keys.txt'),
    [string[]]$Only = @('huggingface', 'supermemory', 'openai', 'openrouter'),   # add 'whatsapp' only for Meta's Cloud API; the phone-linked bridge needs no key
    [string[]]$Profiles = @('default', 'seven6moa'),         # where Hugging Face, Supermemory, OpenAI and OpenRouter go
    [string[]]$WhatsAppProfiles = @('seven6moa'),            # where the WhatsApp Cloud API credentials go
    [string[]]$PromptFor = @(),  # providers whose key you want to PASTE at a hidden prompt instead of reading it from the list, e.g. -PromptFor huggingface
    [switch]$Inventory,          # redacted listing of what the file holds; no network, no writes
    [switch]$SkipValidation,     # skip the live checks against Hugging Face, OpenAI, Supermemory and Meta
    [switch]$AssumeYes,          # do not ask before each write and never prompt for pasted keys (used for testing)
    [string]$HermesRoot = (Join-Path $env:LOCALAPPDATA 'hermes')   # only changed for testing against a copy
)
# Installs Hugging Face, Supermemory, OpenAI and WhatsApp (Cloud API) keys, and OpenRouter via its own script,
# from your key list (or a hidden prompt) into Hermes' .env files. You run this yourself: key values go from your
# file straight into .env and are never printed or logged; they are sent only to the provider's own API for a
# validity check. Output shows line numbers, the key FORMAT class (for example "sm_") and lengths.
#
#   First look:   .\install-api-keys.ps1 -Inventory
#   Install:      .\install-api-keys.ps1      (add -PromptFor huggingface to paste a different Hugging Face token instead of the list's)
#   Run it with:  powershell -NoProfile -ExecutionPolicy Bypass -File .\install-api-keys.ps1
#
# What lands where (variable names are Hermes' own):
#   Hugging Face -> HF_TOKEN (one line; duplicates removed)             (default, seven6moa)
#   Supermemory  -> SUPERMEMORY_API_KEY                                 (default, seven6moa)
#   OpenAI       -> OPENAI_API_KEY                                      (default, seven6moa)
#   WhatsApp     -> ONLY with -Only whatsapp, and only for Meta's official Cloud API (a business token starting EAA):
#                   WHATSAPP_CLOUD_ACCESS_TOKEN + WHATSAPP_CLOUD_PHONE_NUMBER_ID, and when the list has them
#                   WHATSAPP_CLOUD_APP_SECRET / WHATSAPP_CLOUD_VERIFY_TOKEN  (seven6moa).
#                   Hermes' normal WhatsApp, linked from the phone, uses no key at all: run  hermes -p seven6moa whatsapp
#   OpenRouter   -> handed to set-openrouter-key.ps1 -FromFile (tries each key, proves it through Hermes, rolls back failures)
# A key that its provider rejects is never written. Every .env is backed up first as .env.bak-keys-<stamp>.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Only = @($Only | ForEach-Object { $_.ToLowerInvariant() })
$PromptFor = @($PromptFor | ForEach-Object { $_.ToLowerInvariant() })

function Get-HomeDir([string]$p) { if ($p -eq 'default') { $HermesRoot } else { Join-Path $HermesRoot "profiles\$p" } }

# ---- recognising keys without ever showing them ---------------------------------------------------------
$prefixTable = @(   # first match wins, so the specific sk-* prefixes come before the generic one
    @{ p = 'sk-or-';      prov = 'openrouter' },  @{ p = 'sk-ant-';     prov = 'anthropic' },
    @{ p = 'sk-proj-';    prov = 'openai' },      @{ p = 'sk-svcacct-'; prov = 'openai' },
    @{ p = 'sk-admin-';   prov = 'openai' },      @{ p = 'sm_';         prov = 'supermemory' },
    @{ p = 'EAA';         prov = 'whatsapp' },    @{ p = 'nvapi-';      prov = 'nvidia' },
    @{ p = 'hf_';         prov = 'huggingface' }, @{ p = 'ghp_';        prov = 'github' },
    @{ p = 'github_pat_'; prov = 'github' },      @{ p = 'gsk_';        prov = 'groq' },
    @{ p = 'AIza';        prov = 'google' },      @{ p = 'pplx-';       prov = 'perplexity' },
    @{ p = 'fc-';         prov = 'firecrawl' },   @{ p = 'tvly-';       prov = 'tavily' },
    @{ p = 'sk-';         prov = 'openai?' }
)
function Get-FormatClass([string]$token) {
    foreach ($e in $prefixTable) { if ($token.StartsWith($e.p)) { return [pscustomobject]@{ Class = $e.p; Prov = $e.prov } } }
    [pscustomobject]@{ Class = 'unknown'; Prov = $null }
}
function Get-LabelProvider([string]$text) {
    $l = $text.ToLowerInvariant()
    if ($l -match 'super\s*-?\s*memory') { return 'supermemory' }
    if ($l -match 'open\s*-?\s*router')  { return 'openrouter' }
    if ($l -match 'open\s*-?\s*ai|chat\s*-?\s*gpt') { return 'openai' }
    if ($l -match 'whats\s*-?\s*app|\bwa\b|\bwaba\b|\bmeta\b|facebook') { return 'whatsapp' }
    if ($l -match 'hugging\s*-?\s*face|\bhf\b') { return 'huggingface' }
    $null
}
function Get-LabelKind([string]$text) {
    $l = $text.ToLowerInvariant()
    if ($l -match 'phone') { return 'phone-id' }
    if ($l -match 'secret') { return 'app-secret' }
    if ($l -match 'verify') { return 'verify-token' }
    'key'
}

if (-not (Test-Path $KeysFile)) { throw "Key file not found: $KeysFile" }
$fileLines = [IO.File]::ReadAllLines($KeysFile)
$items = New-Object System.Collections.Generic.List[object]
$seen = @{}
$pendingProv = $null; $pendingKind = 'key'
for ($i = 0; $i -lt $fileLines.Count; $i++) {
    $line = $fileLines[$i]
    if (-not $line.Trim()) { continue }
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($line, '[A-Za-z0-9][A-Za-z0-9_\-]{19,}')) {
        $f = Get-FormatClass $m.Value
        $mixed = ($m.Value -match '[A-Za-z]') -and ($m.Value -match '\d')
        if ($f.Prov -or $mixed) { $tokens.Add($m.Value) }
    }
    $phoneIds = @([regex]::Matches($line, '(?<![0-9])[0-9]{10,20}(?![0-9])') | ForEach-Object { $_.Value })
    $labelText = [regex]::Replace($line, '[A-Za-z0-9][A-Za-z0-9_\-]{19,}', ' ')
    $labelProv = Get-LabelProvider $labelText
    $labelKind = Get-LabelKind $labelText
    if ($tokens.Count -eq 0 -and $phoneIds.Count -eq 0) {
        if ($labelProv) { $pendingProv = $labelProv; $pendingKind = $labelKind } else { $pendingProv = $null }   # a label on its own line applies to the next value
        continue
    }
    $effProv = $labelProv; $effKind = $labelKind; $by = 'label'
    if (-not $effProv -and $pendingProv) { $effProv = $pendingProv; $effKind = $pendingKind; $by = 'previous line' }
    $pendingProv = $null
    foreach ($t in $tokens) {
        if ($seen.ContainsKey($t)) { continue }
        $seen[$t] = $true
        $f = Get-FormatClass $t
        $prov = $effProv; $how = $by
        if (-not $prov) { $prov = $f.Prov; $how = 'format' }
        # a label that says OpenAI on a value in another vendor's format is not trusted
        if ($prov -eq 'openai' -and $f.Prov -in @('openrouter', 'anthropic', 'supermemory', 'nvidia', 'huggingface', 'github', 'groq', 'google')) { $prov = $f.Prov; $how = 'format (label disagreed)' }
        $kind = $(if ($prov -eq 'whatsapp') { $effKind } else { 'key' })
        if ($prov -eq 'whatsapp' -and $f.Class -eq 'EAA') { $kind = 'key' }
        $items.Add([pscustomobject]@{ Prov = $prov; Kind = $kind; Value = $t; Line = $i + 1; Class = $f.Class; Len = $t.Length; How = $how })
    }
    if ($effProv -eq 'whatsapp' -and $effKind -eq 'phone-id') {
        foreach ($p in $phoneIds) { if (-not $seen.ContainsKey($p)) { $seen[$p] = $true; $items.Add([pscustomobject]@{ Prov = 'whatsapp'; Kind = 'phone-id'; Value = $p; Line = $i + 1; Class = 'digits'; Len = $p.Length; How = $by }) } }
    }
}
function Pick([string]$prov, [string]$kind) { @($items | Where-Object { $_.Prov -eq $prov -and $_.Kind -eq $kind }) }

# ---- inventory -------------------------------------------------------------------------------------------
"Key file: $KeysFile  ($($fileLines.Count) lines). No key characters are printed anywhere below."
'{0,5}  {1,-34} {2,-13} {3,6}  {4}' -f 'line', 'recognised as', 'format', 'length', 'found by'
foreach ($it in $items) {
    $what = $(if ($it.Prov) { "$($it.Prov) $($it.Kind)" } else { 'unrecognised' })
    '{0,5}  {1,-34} {2,-13} {3,6}  {4}' -f $it.Line, $what, $it.Class, $it.Len, $it.How
}
if ($Inventory) { return }

# ---- helpers ---------------------------------------------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backedUp = @{}
function Set-EnvVar([string]$profile, [string]$name, [string]$value) {
    $envFile = Join-Path (Get-HomeDir $profile) '.env'
    if (-not (Test-Path $envFile)) { throw "No .env for profile '$profile' at $envFile" }
    if (-not $backedUp.ContainsKey($envFile)) { Copy-Item $envFile "$envFile.bak-keys-$stamp"; $backedUp[$envFile] = $true }
    $out = New-Object System.Collections.Generic.List[string]; $placed = $false
    foreach ($l in [IO.File]::ReadAllLines($envFile)) {
        if ($l -match ('^\s*' + [regex]::Escape($name) + '\s*=')) {        # first occurrence is replaced, duplicates are dropped
            if (-not $placed) { $out.Add($name + '=' + $value); $placed = $true }
        } else { $out.Add($l) }
    }
    if (-not $placed) { $out.Add($name + '=' + $value) }
    [IO.File]::WriteAllLines($envFile, $out, (New-Object Text.UTF8Encoding($false)))
}
function Ask-Yes([string]$q) { if ($AssumeYes) { return $true }; $a = Read-Host "$q [Y/n]"; return ($a -eq '' -or $a -match '^[yY]') }
function Get-HttpCode($err) { try { [int]$err.Exception.Response.StatusCode } catch { 0 } }
function Read-Secret([string]$what) {
    $sec = Read-Host "Paste $what (input is hidden; press Enter to skip)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { $v = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    if ($v) { $v.Trim().Trim('"').Trim("'") } else { '' }
}
function Invoke-Web([string]$method, [string]$uri, [hashtable]$headers, [string]$body) {
    try {
        $a = @{ Method = $method; Uri = $uri; Headers = $headers; TimeoutSec = 30; UseBasicParsing = $true }
        if ($body) { $a['Body'] = $body; $a['ContentType'] = 'application/json' }
        $r = Invoke-WebRequest @a
        [pscustomobject]@{ Code = [int]$r.StatusCode; Body = $r.Content }
    } catch { [pscustomobject]@{ Code = (Get-HttpCode $_); Body = '' } }
}
# Each validator returns Ok + a note that never contains the key.
function Test-HuggingFaceKey([string]$v) {
    $r = Invoke-Web 'GET' 'https://huggingface.co/api/whoami-v2' @{ Authorization = "Bearer $v" } $null
    if ($r.Code -ne 200) { return [pscustomobject]@{ Ok = $false; Note = "rejected by Hugging Face (HTTP $($r.Code))" } }
    $role = ''; $inf = $true
    try {
        $j = $r.Body | ConvertFrom-Json; $role = $j.auth.accessToken.role
        if ($role -eq 'fineGrained') { $inf = [bool](($j.auth.accessToken.fineGrained.scoped | ForEach-Object { $_.permissions } | Where-Object { $_ -like '*inference*' }) | Select-Object -First 1) }
    } catch {}
    if (-not $inf) { return [pscustomobject]@{ Ok = $false; Note = "accepted (role $role) but it lacks the 'Make calls to Inference Providers' permission, so Hermes could not use it" } }
    [pscustomobject]@{ Ok = $true; Note = "accepted by Hugging Face (role $role, inference permission present)" }
}
function Test-OpenAiKey([string]$v) {
    $r = Invoke-Web 'GET' 'https://api.openai.com/v1/models' @{ Authorization = "Bearer $v" } $null
    [pscustomobject]@{ Ok = ($r.Code -ge 200 -and $r.Code -lt 300); Note = $(if ($r.Code -ge 200 -and $r.Code -lt 300) { 'accepted by OpenAI' } else { "rejected by OpenAI (HTTP $($r.Code))" }) }
}
function Test-SupermemoryKey([string]$v) {
    $r = Invoke-Web 'POST' 'https://api.supermemory.ai/v3/documents/list' @{ Authorization = "Bearer $v" } '{"limit":1}'
    $ok = ($r.Code -ge 200 -and $r.Code -lt 300)
    [pscustomobject]@{ Ok = $ok; Note = $(if ($ok) { 'accepted by Supermemory' } else { "rejected by Supermemory (HTTP $($r.Code))" }) }
}
function Select-Key([string]$prov, [string]$provLabel, [scriptblock]$validator, [string[]]$provAliases = @()) {
    # returns the first candidate the provider accepts; when none, offers a hidden prompt (unless -AssumeYes)
    # Messages use Write-Host on purpose: anything written to the output stream here would be returned to the caller.
    $cands = @()
    if ($PromptFor -notcontains $prov) { $cands = @(Pick $prov 'key'); foreach ($al in $provAliases) { $cands += @(Pick $al 'key') } }
    elseif ($AssumeYes) { Write-Host 'Prompt requested but -AssumeYes is set; skipping.'; return $null }
    foreach ($c in $cands) {
        if ($SkipValidation -or -not $validator) { return $c }
        $res = & $validator $c.Value
        Write-Host "line $($c.Line) ($($c.Len) characters): $($res.Note)"
        if ($res.Ok) { return $c }
    }
    if ($cands.Count -eq 0 -and $PromptFor -notcontains $prov) { Write-Host "No $provLabel key found in the list." }
    if (-not $AssumeYes) {
        $v = Read-Secret "a $provLabel key"
        if ($v) {
            if (-not $SkipValidation -and $validator) { $res = & $validator $v; Write-Host $res.Note; if (-not $res.Ok) { return $null } }
            return [pscustomobject]@{ Value = $v; Line = 0; Len = $v.Length }
        }
    }
    return $null
}
$done = New-Object System.Collections.Generic.List[string]
function Install-Simple([string]$title, [string]$prov, [string]$envName, [scriptblock]$validator, [string[]]$provAliases = @()) {
    ''; "== $title"
    $use = Select-Key $prov $title $validator $provAliases
    if (-not $use) { "Nothing written for $title."; return }
    $where = $(if ($use.Line) { "line $($use.Line), " } else { 'pasted, ' })
    if (Ask-Yes "Install $envName ($where$($use.Len) characters) into: $($Profiles -join ', ')?") {
        foreach ($p in $Profiles) { Set-EnvVar $p $envName $use.Value }
        $done.Add("$envName -> $($Profiles -join ', ')")
    } else { 'Skipped.' }
}

# ---- the providers ---------------------------------------------------------------------------------------
if ($Only -contains 'huggingface') { Install-Simple 'Hugging Face' 'huggingface' 'HF_TOKEN' ${function:Test-HuggingFaceKey} }
if ($Only -contains 'supermemory') { Install-Simple 'Supermemory' 'supermemory' 'SUPERMEMORY_API_KEY' ${function:Test-SupermemoryKey} }
if ($Only -contains 'openai')      { Install-Simple 'OpenAI' 'openai' 'OPENAI_API_KEY' ${function:Test-OpenAiKey} @('openai?') }

if ($Only -contains 'whatsapp') {
    ''; '== WhatsApp (Cloud API)'
    $tok = @(Pick 'whatsapp' 'key') | Sort-Object { if ($_.Class -eq 'EAA') { 0 } else { 1 } }
    $t = $null
    if ($PromptFor -notcontains 'whatsapp') { $t = $tok | Select-Object -First 1 }
    $ph = @(Pick 'whatsapp' 'phone-id')
    $phoneId = $(if ($ph.Count -gt 0) { $ph[0].Value } else { '' })
    if ($t) { "token candidate: line $($t.Line), $($t.Len) characters, format $($t.Class)" } elseif ($PromptFor -notcontains 'whatsapp') { 'No WhatsApp token found in the list.' }
    if (-not $AssumeYes) {
        if (-not $phoneId) {
            'The adapter needs the numeric "Phone number ID" from Meta > WhatsApp > API setup (an ID, not a secret).'
            $phoneId = (Read-Host 'Type the Phone number ID (press Enter to skip WhatsApp)').Trim()
        }
    }
    $tokenValue = $(if ($t) { $t.Value } else { '' }); $tokenLen = $(if ($t) { $t.Len } else { 0 })
    $ok = $false
    if ($phoneId -and $tokenValue) {
        if ($SkipValidation) { $ok = $true } else {
            $r = Invoke-Web 'GET' "https://graph.facebook.com/v20.0/$phoneId" @{ Authorization = "Bearer $tokenValue" } $null
            if ($r.Code -ge 200 -and $r.Code -lt 300) { $ok = $true; 'Meta accepted the token and the phone number ID.' } else { "Meta rejected the list's token with that phone number ID (HTTP $($r.Code))." }
        }
    }
    if (-not $ok -and -not $AssumeYes) {
        if (-not $phoneId) { 'Skipped WhatsApp (needs the phone number ID).' } else {
            $v = Read-Secret 'the WhatsApp Cloud API access token (starts with EAA)'
            if ($v) {
                $r = $(if ($SkipValidation) { [pscustomobject]@{ Code = 200 } } else { Invoke-Web 'GET' "https://graph.facebook.com/v20.0/$phoneId" @{ Authorization = "Bearer $v" } $null })
                if ($r.Code -ge 200 -and $r.Code -lt 300) { $tokenValue = $v; $tokenLen = $v.Length; $ok = $true; 'Meta accepted the pasted token and the phone number ID.' } else { "Meta rejected the pasted token (HTTP $($r.Code))." }
            }
        }
    }
    if ($ok -and (Ask-Yes "Install the WhatsApp Cloud API token ($tokenLen characters) and phone number ID into: $($WhatsAppProfiles -join ', ')?")) {
        $sec = @(Pick 'whatsapp' 'app-secret'); $vt = @(Pick 'whatsapp' 'verify-token')
        foreach ($p in $WhatsAppProfiles) {
            Set-EnvVar $p 'WHATSAPP_CLOUD_ACCESS_TOKEN' $tokenValue
            Set-EnvVar $p 'WHATSAPP_CLOUD_PHONE_NUMBER_ID' $phoneId
            if ($sec.Count -gt 0) { Set-EnvVar $p 'WHATSAPP_CLOUD_APP_SECRET' $sec[0].Value }
            if ($vt.Count -gt 0) { Set-EnvVar $p 'WHATSAPP_CLOUD_VERIFY_TOKEN' $vt[0].Value }
        }
        $done.Add("WHATSAPP_CLOUD_ACCESS_TOKEN + WHATSAPP_CLOUD_PHONE_NUMBER_ID$(if ($sec.Count) { ' + APP_SECRET' })$(if ($vt.Count) { ' + VERIFY_TOKEN' }) -> $($WhatsAppProfiles -join ', ')")
    } elseif (-not $ok) { 'Nothing written for WhatsApp.' }
    $tokenValue = $null
}

if ($Only -contains 'openrouter') {
    ''; '== OpenRouter'
    $orScript = Join-Path $PSScriptRoot 'set-openrouter-key.ps1'
    if (Test-Path $orScript) { & $orScript -FromFile $KeysFile -Profiles $Profiles } else { 'set-openrouter-key.ps1 not found next to this script; skipped.' }
}

foreach ($it in $items) { $it.Value = $null }
''; '== Summary'
if ($done.Count -eq 0) { 'Nothing was written by this script (OpenRouter, if selected, reports above).' } else { $done | ForEach-Object { "written: $_" }; "Backups: .env.bak-keys-$stamp next to each changed .env" }
@'

Next steps (no secrets involved):
  Hugging Face  once HF_TOKEN is valid: hermes -p seven6moa --provider huggingface -m nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4 -z "say ok" --usage-file out.json
                (out.json must name that model; seven6moa's fallback chain already lists it as backup 2)
  Supermemory   hermes -p seven6moa plugins install supermemory      (third-party code: read the audit it prints)
                hermes -p seven6moa memory setup                      (or: hermes -p seven6moa config set memory.provider supermemory)
                hermes -p seven6moa memory status
                It stores each conversation turn in Supermemory's cloud and injects recalled items into every prompt,
                so it adds tokens; supermemory.json in the profile folder has max_recall_results and auto_capture to tune that.
  OpenAI        the key alone adds speech-to-text/text-to-speech and voice features; the openai provider is excluded in seven6moa on purpose.
  WhatsApp      phone-linked (what seven6moa is set up for, no key needed):
                  hermes -p seven6moa whatsapp          (shows a QR code; scan it in WhatsApp > Settings > Linked devices > Link a device)
                  hermes -p seven6moa gateway run       (starts the bridge; "gateway install" makes it start at login)
                Meta Cloud API (official, needs a business token and a public webhook): re-run with -Only whatsapp.
'@
