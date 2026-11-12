param(
    [string]$KeysFile = (Join-Path $env:USERPROFILE 'Desktop\List of API keys.txt'),
    [string[]]$Profiles = @('default', 'seven6moa', 'mylocal'),
    [string]$HermesRoot = (Join-Path $env:LOCALAPPDATA 'hermes'),
    [switch]$NoFile,        # skip the key list, check only the keys Hermes holds
    [switch]$NoEnv,         # skip the Hermes .env files, check only the key list
    [switch]$ShowWords      # for entries whose provider is not recognised, also print the plain-letter words around them (service names)
)
# Audits every API key in the Hermes .env files and in your key list. Each key is sent ONLY to its own provider's
# read-only "who am I / list models" endpoint, in an Authorization header (never in a URL). The report shows the
# source (file + line or variable name), the provider, the length and a verdict. No key character is printed,
# logged or written anywhere; exception text is never shown.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$prefixTable = @(
    @{ p = 'sk-or-'; prov = 'openrouter' }, @{ p = 'sk-ant-'; prov = 'anthropic' }, @{ p = 'sk-proj-'; prov = 'openai' },
    @{ p = 'sk-svcacct-'; prov = 'openai' }, @{ p = 'sk-admin-'; prov = 'openai' }, @{ p = 'sm_'; prov = 'supermemory' },
    @{ p = 'EAA'; prov = 'whatsapp' }, @{ p = 'nvapi-'; prov = 'nvidia' }, @{ p = 'hf_'; prov = 'huggingface' },
    @{ p = 'ghp_'; prov = 'github' }, @{ p = 'github_pat_'; prov = 'github' }, @{ p = 'gsk_'; prov = 'groq' },
    @{ p = 'AIza'; prov = 'google' }, @{ p = 'pplx-'; prov = 'perplexity' }, @{ p = 'fc-'; prov = 'firecrawl' },
    @{ p = 'tvly-'; prov = 'tavily' }, @{ p = 'sk-'; prov = 'openai?' }
)
function Get-FormatClass([string]$t) { foreach ($e in $prefixTable) { if ($t.StartsWith($e.p)) { return [pscustomobject]@{ Class = $e.p; Prov = $e.prov } } }; [pscustomobject]@{ Class = 'unknown'; Prov = $null } }
function Get-LabelProvider([string]$s) {
    $l = $s.ToLowerInvariant()
    if ($l -match 'super\s*-?\s*memory') { return 'supermemory' }
    if ($l -match 'open\s*-?\s*router') { return 'openrouter' }
    if ($l -match 'open\s*-?\s*ai|chat\s*-?\s*gpt') { return 'openai' }
    if ($l -match 'whats\s*-?\s*app|\bwa\b|\bwaba\b|\bmeta\b|facebook') { return 'whatsapp' }
    if ($l -match 'hugging\s*-?\s*face|\bhf\b') { return 'huggingface' }
    if ($l -match 'nvidia|\bnim\b') { return 'nvidia' }
    if ($l -match 'anthropic|claude') { return 'anthropic' }
    if ($l -match 'github') { return 'github' }
    $null
}
function Get-NameProvider([string]$n) {
    switch -Regex ($n) {
        '^NVIDIA_API_KEY$' { 'nvidia'; break }
        '^OPENROUTER_API_KEY$' { 'openrouter'; break }
        '^OPENAI_API_KEY$' { 'openai'; break }
        '^ANTHROPIC_API_KEY$' { 'anthropic'; break }
        '^(HF_TOKEN|HUGGINGFACE_API_KEY|HUGGING_FACE_HUB_TOKEN)$' { 'huggingface'; break }
        '^(GITHUB_TOKEN|GH_TOKEN)$' { 'github'; break }
        '^GROQ_API_KEY$' { 'groq'; break }
        '^XAI_API_KEY$' { 'xai'; break }
        '^(GEMINI_API_KEY|GOOGLE_API_KEY)$' { 'google'; break }
        '^SUPERMEMORY_API_KEY$' { 'supermemory'; break }
        '^WHATSAPP_CLOUD_ACCESS_TOKEN$' { 'whatsapp'; break }
        default { $null }
    }
}

# ---- collect ------------------------------------------------------------------------------------------------
$items = New-Object System.Collections.Generic.List[object]
if (-not $NoEnv) {
    foreach ($p in $Profiles) {
        $envFile = if ($p -eq 'default') { Join-Path $HermesRoot '.env' } else { Join-Path $HermesRoot "profiles\$p\.env" }
        if (-not (Test-Path $envFile)) { continue }
        $n = 0
        foreach ($line in [IO.File]::ReadAllLines($envFile)) {
            $n++
            if ($line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') { continue }
            $name = $Matches[1]; $val = $Matches[2].Trim().Trim('"').Trim("'")
            if ($name -notmatch 'KEY|TOKEN|SECRET' -or $val.Length -lt 16 -or $val.StartsWith('{') -or $val -match 'no-key|placeholder') { continue }
            $prov = Get-NameProvider $name
            if (-not $prov) { $prov = (Get-FormatClass $val).Prov }
            $items.Add([pscustomobject]@{ Source = "$p .env $name"; Prov = $prov; Value = $val; Len = $val.Length; Class = (Get-FormatClass $val).Class })
        }
    }
}
if (-not $NoFile -and (Test-Path $KeysFile)) {
    $lines = [IO.File]::ReadAllLines($KeysFile)
    $pendingProv = $null; $pendingWords = ''
    # only plain-letter words (3+ letters, no digits, no symbols) are ever shown, so a password or id near a key cannot leak
    function Get-Words([string]$s) { (([regex]::Matches($s, '(?<![A-Za-z0-9_\-])[A-Za-z]{3,14}(?![A-Za-z0-9_\-])') | Select-Object -First 7 | ForEach-Object { $_.Value }) -join ' ') }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]; if (-not $line.Trim()) { continue }
        $tokens = @(); foreach ($m in [regex]::Matches($line, '[A-Za-z0-9][A-Za-z0-9_\-]{19,}')) { $f = Get-FormatClass $m.Value; if ($f.Prov -or (($m.Value -match '[A-Za-z]') -and ($m.Value -match '\d'))) { $tokens += $m.Value } }
        $labelText = [regex]::Replace($line, '[A-Za-z0-9][A-Za-z0-9_\-]{19,}', ' ')
        $labelProv = Get-LabelProvider $labelText
        if ($tokens.Count -eq 0) { $pendingProv = $labelProv; $pendingWords = Get-Words $labelText; continue }
        $eff = $labelProv; if (-not $eff) { $eff = $pendingProv }
        $words = Get-Words $labelText; if (-not $words) { $words = $pendingWords }
        $pendingProv = $null; $pendingWords = ''
        foreach ($t in $tokens) {
            $f = Get-FormatClass $t; $prov = $eff
            if (-not $prov -or ($prov -in @('openai') -and $f.Prov -in @('openrouter', 'anthropic', 'supermemory', 'nvidia', 'huggingface', 'github', 'groq', 'google'))) { $prov = $f.Prov }
            $items.Add([pscustomobject]@{ Source = "key list line $($i + 1)"; Prov = $prov; Value = $t; Len = $t.Length; Class = $f.Class; Words = $words })
        }
    }
} elseif (-not $NoFile) { "Key list not found at: $KeysFile (checking Hermes .env files only)" }

# ---- live checks (read-only endpoints, header auth, no URL secrets) ------------------------------------------
function Call([string]$method, [string]$uri, [hashtable]$headers, [string]$body, [int]$timeout = 25) {
    try {
        $args_ = @{ Method = $method; Uri = $uri; Headers = $headers; TimeoutSec = $timeout; UseBasicParsing = $true }
        if ($body) { $args_['Body'] = $body; $args_['ContentType'] = 'application/json' }
        $r = Invoke-WebRequest @args_
        [pscustomobject]@{ Code = [int]$r.StatusCode; Body = $r.Content }
    } catch {
        $c = 0; try { $c = [int]$_.Exception.Response.StatusCode } catch {}
        [pscustomobject]@{ Code = $c; Body = '' }
    }
}
function Test-Key([string]$prov, [string]$v) {
    $bearer = @{ Authorization = "Bearer $v" }
    switch ($prov) {
        # NVIDIA's /v1/models is PUBLIC (a fake key got HTTP 200 in testing), so it proves nothing. A one-token
        # chat call is the cheapest request that actually requires a valid key.
        'nvidia'      { $r = Call 'POST' 'https://integrate.api.nvidia.com/v1/chat/completions' $bearer '{"model":"nvidia/nemotron-3-super-120b-a12b","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' 90 }
        'openrouter'  { $r = Call 'GET' 'https://openrouter.ai/api/v1/auth/key' $bearer $null }
        { $_ -in 'openai', 'openai?' } { $r = Call 'GET' 'https://api.openai.com/v1/models' $bearer $null }
        'anthropic'   { $r = Call 'GET' 'https://api.anthropic.com/v1/models?limit=1' @{ 'x-api-key' = $v; 'anthropic-version' = '2023-06-01' } $null }
        'groq'        { $r = Call 'GET' 'https://api.groq.com/openai/v1/models' $bearer $null }
        'xai'         { $r = Call 'GET' 'https://api.x.ai/v1/models' $bearer $null }
        'google'      { $r = Call 'GET' 'https://generativelanguage.googleapis.com/v1beta/models?pageSize=1' @{ 'x-goog-api-key' = $v } $null }
        'github'      { $r = Call 'GET' 'https://api.github.com/user' @{ Authorization = "Bearer $v"; 'User-Agent' = 'key-audit' } $null }
        'huggingface' {
            $r = Call 'GET' 'https://huggingface.co/api/whoami-v2' $bearer $null
            if ($r.Code -eq 200) {
                $detail = 'token accepted'
                try {
                    $j = $r.Body | ConvertFrom-Json; $role = $j.auth.accessToken.role
                    $inf = $true
                    if ($role -eq 'fineGrained') { $inf = [bool](($j.auth.accessToken.fineGrained.scoped | ForEach-Object { $_.permissions } | Where-Object { $_ -like '*inference*' }) | Select-Object -First 1) }
                    $detail = "role=$role, inference-provider permission: $inf"
                } catch {}
                return [pscustomobject]@{ Verdict = 'VALID'; Detail = $detail }
            }
        }
        'supermemory' { $r = Call 'POST' 'https://api.supermemory.ai/v3/documents/list' $bearer '{"limit":1}' }
        'whatsapp'    { $r = Call 'GET' 'https://graph.facebook.com/v20.0/me' $bearer $null }
        default       { return [pscustomobject]@{ Verdict = 'not checked'; Detail = 'no live check for this provider' } }
    }
    if ($r.Code -ge 200 -and $r.Code -lt 300) { return [pscustomobject]@{ Verdict = 'VALID'; Detail = "HTTP $($r.Code)" } }
    if ($r.Code -in 401, 403) { return [pscustomobject]@{ Verdict = 'REJECTED'; Detail = "HTTP $($r.Code)" } }
    if ($prov -in 'whatsapp', 'xai' -and $r.Code -eq 400) { return [pscustomobject]@{ Verdict = 'REJECTED'; Detail = 'HTTP 400 (key rejected)' } }
    if ($r.Code -eq 0) { return [pscustomobject]@{ Verdict = 'no answer'; Detail = 'network error or timeout' } }
    [pscustomobject]@{ Verdict = 'inconclusive'; Detail = "HTTP $($r.Code)" }
}

# duplicates (by value, never shown)
$groups = $items | Group-Object { [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($_.Value))) }
$dupOf = @{}; foreach ($g in $groups) { if ($g.Count -gt 1) { foreach ($m in $g.Group) { $dupOf[$m.Source] = ($g.Group | Where-Object { $_.Source -ne $m.Source } | ForEach-Object { $_.Source }) -join '; ' } } }
$cache = @{}
$rows = foreach ($it in ($items | Sort-Object Prov, Source)) {
    $ck = "$($it.Prov)|" + [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($it.Value)))
    if (-not $cache.ContainsKey($ck)) { $cache[$ck] = if ($it.Prov) { Test-Key $it.Prov $it.Value } else { [pscustomobject]@{ Verdict = 'not checked'; Detail = 'format not recognised' } } }
    $res = $cache[$ck]
    [pscustomobject]@{ Provider = $(if ($it.Prov) { $it.Prov } else { '?' }); Source = $it.Source; Format = $it.Class; Length = $it.Len; Verdict = $res.Verdict; Detail = $res.Detail; SameValueAs = $(if ($dupOf.ContainsKey($it.Source)) { $dupOf[$it.Source] } else { '' }) }
}
foreach ($it in $items) { $it.Value = $null }
"Checked $($rows.Count) key entries ($(@($rows | Where-Object { $_.Verdict -eq 'VALID' }).Count) valid, $(@($rows | Where-Object { $_.Verdict -eq 'REJECTED' }).Count) rejected). No key characters are printed."
''
$rows | Format-Table Provider, Source, Format, Length, Verdict, Detail -AutoSize -Wrap | Out-String -Width 220
if ($ShowWords) {
    ''; 'Entries whose provider was not recognised, with the plain-letter words found around them:'
    $items | Where-Object { -not $_.Prov } | ForEach-Object { '  {0,-22} len {1,3}   words: {2}' -f $_.Source, $_.Len, $_.Words }
}
$d = @($rows | Where-Object { $_.SameValueAs })
if ($d.Count) { 'Entries that hold the same value as another entry:'; $d | ForEach-Object { "  $($_.Source)  =  $($_.SameValueAs)" } }
