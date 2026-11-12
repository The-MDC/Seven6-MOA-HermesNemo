param([Parameter(Mandatory)][string]$ProfileName, [Parameter(Mandatory)][string]$TopKey, [Parameter(Mandatory)][string]$BlockFile)
# Replaces (or appends) one TOP-LEVEL block of a profile's config.yaml with the contents of $BlockFile (which must start with "<TopKey>:").
# Block extent = from the "<TopKey>:" line to just before the next line starting with a letter/underscore at column 0 (comments/blank lines
# right before that next key are kept). Backs the file up first; UTF-8 without BOM.
$cfg = if ($ProfileName -eq 'default') { Join-Path $env:LOCALAPPDATA 'hermes\config.yaml' } else { Join-Path $env:LOCALAPPDATA "hermes\profiles\$ProfileName\config.yaml" }
$new = [IO.File]::ReadAllLines($BlockFile)
if ($new.Count -eq 0 -or $new[0] -notmatch ('^' + [regex]::Escape($TopKey) + ':')) { throw "BlockFile must start with '${TopKey}:'" }
$lines = [IO.File]::ReadAllLines($cfg)
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match ('^' + [regex]::Escape($TopKey) + ':')) { $start = $i; break } }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item $cfg "$cfg.bak-tokens-$stamp"
if ($start -lt 0) {
    $out = @($lines) + $new
    $what = 'appended'
} else {
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^[A-Za-z_]') { $end = $i; break } }
    # keep trailing comment/blank lines that belong to the next key's header
    $keepFrom = $end
    while ($keepFrom -gt $start + 1 -and $lines[$keepFrom - 1] -match '^(#.*|\s*)$') { $keepFrom-- }
    $head = if ($start -gt 0) { @($lines[0..($start - 1)]) } else { @() }
    $tail = if ($keepFrom -lt $lines.Count) { @($lines[$keepFrom..($lines.Count - 1)]) } else { @() }
    $out = $head + $new + $tail
    $what = "replaced lines $($start + 1)-$keepFrom"
}
[IO.File]::WriteAllLines($cfg, $out, (New-Object Text.UTF8Encoding($false)))
"$ProfileName : '$TopKey' $what (backup config.yaml.bak-tokens-$stamp)"
