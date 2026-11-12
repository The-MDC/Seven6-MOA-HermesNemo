param([switch]$Yes)
# Retires the six tier profiles that were folded into `seven6moa` on 2026-10-16
# (codex-moa, local-floor, moa-aggregator, nim-subagents, nim-vision, or-fallback).
#   no switch : dry run - checks each archive and prints what it WOULD delete
#   -Yes      : deletes each profile whose archive is present and readable
# `hermes profile delete` already purges the profile's routing identity, so nothing else is needed.
# Restore one later with:  hermes profile import <archive>      (archives: local-llm\profile-archive)
$arch = Join-Path $env:USERPROFILE 'local-llm\profile-archive'
$tiers = 'codex-moa', 'local-floor', 'moa-aggregator', 'nim-subagents', 'nim-vision', 'or-fallback'
$profiles = Join-Path $env:LOCALAPPDATA 'hermes\profiles'
if (-not (Test-Path (Join-Path $profiles 'seven6moa\config.yaml'))) { throw 'seven6moa is missing - nothing to fold the tiers into. Aborting.' }
foreach ($p in $tiers) {
    if (-not (Test-Path (Join-Path $profiles $p))) { "{0,-15} already gone" -f $p; continue }
    $a = Get-ChildItem $arch -Filter "$p-*.tar.gz" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $ok = $a -and $a.Length -gt 1000 -and [bool](tar -tzf $a.FullName 2>$null | Select-String 'config\.yaml$')
    if (-not $ok) { "{0,-15} no readable archive in {1} - skipped" -f $p, $arch; continue }
    if (-not $Yes) { "{0,-15} archive {1} OK - would delete (re-run with -Yes)" -f $p, $a.Name; continue }
    hermes profile delete $p -y 2>&1 | Out-Null
    "{0,-15} {1} (archive kept: {2})" -f $p, $(if (Test-Path (Join-Path $profiles $p)) { 'DELETE FAILED' } else { 'deleted' }), $a.Name
}
''
hermes profile list
