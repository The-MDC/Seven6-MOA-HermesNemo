param(
    [Parameter(Mandatory)][string]$Old,
    [Parameter(Mandatory)][string]$New,
    [string[]]$Profiles = @(),      # empty = every profile including default
    [switch]$WhatIf
)
# Replaces one model id with another in every Hermes profile's config.yaml, on non-comment lines only.
# A catalog entry (a mapping key under providers.<id>.models) for the OLD id is dropped instead of renamed, so no duplicate YAML key is created.
# Each changed file is backed up first (config.yaml.bak-swap-<stamp>). Comments are never touched.
$h = Join-Path $env:LOCALAPPDATA 'hermes'
$cfgs = New-Object System.Collections.Generic.List[object]
if ($Profiles.Count -eq 0 -or $Profiles -contains 'default') { $cfgs.Add([pscustomobject]@{ Name = 'default'; Path = (Join-Path $h 'config.yaml') }) }
foreach ($d in (Get-ChildItem (Join-Path $h 'profiles') -Directory)) {
    if ($Profiles.Count -eq 0 -or $Profiles -contains $d.Name) {
        $p = Join-Path $d.FullName 'config.yaml'
        if (Test-Path $p) { $cfgs.Add([pscustomobject]@{ Name = $d.Name; Path = $p }) }
    }
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$keyRx = '^(\s+)' + [regex]::Escape($Old) + ':\s*(\{\}\s*)?(#.*)?$'
foreach ($c in $cfgs) {
    $raw = [IO.File]::ReadAllText($c.Path)
    $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $raw -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $replaced = 0; $dropped = 0
    $i = 0
    while ($i -lt $lines.Count) {
        $ln = $lines[$i]
        if ($ln -match '^\s*#') { $out.Add($ln); $i++; continue }
        $m = [regex]::Match($ln, $keyRx)
        if ($m.Success) {
            $indent = $m.Groups[1].Length
            $i++; $dropped++
            while ($i -lt $lines.Count) {
                $nx = $lines[$i]
                if ($nx.Trim() -eq '') { break }
                $nxIndent = $nx.Length - $nx.TrimStart().Length
                if ($nxIndent -gt $indent) { $i++ } else { break }
            }
            continue
        }
        if ($ln.Contains($Old)) { $out.Add($ln.Replace($Old, $New)); $replaced++ } else { $out.Add($ln) }
        $i++
    }
    if ($replaced -eq 0 -and $dropped -eq 0) { '{0,-16} nothing to change' -f $c.Name; continue }
    if ($WhatIf) { '{0,-16} would replace {1} value(s), drop {2} catalog entr(y/ies)' -f $c.Name, $replaced, $dropped; continue }
    Copy-Item $c.Path "$($c.Path).bak-swap-$stamp"
    [IO.File]::WriteAllText($c.Path, ($out -join $nl), (New-Object Text.UTF8Encoding($false)))
    '{0,-16} replaced {1} value(s), dropped {2} catalog entr(y/ies)  (backup config.yaml.bak-swap-{3})' -f $c.Name, $replaced, $dropped, $stamp
}
