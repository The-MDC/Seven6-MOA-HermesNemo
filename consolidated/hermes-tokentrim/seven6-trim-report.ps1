<#
Summarises the seven6-trim log: which tools return large results and how much a trim would save (or saved).
Reads <profile>\seven6-trim.jsonl (and the rotated .1 file). Sizes only; the log holds no tool content.

  .\seven6-trim-report.ps1                  # profile seven6moa, all time
  .\seven6-trim-report.ps1 -Hours 24
  .\seven6-trim-report.ps1 -Profile default
#>
param([string]$Profile = 'seven6moa', [double]$Hours = 0)
$hh   = Join-Path $env:LOCALAPPDATA 'hermes'
$pdir = if ($Profile -eq 'default') { $hh } else { Join-Path $hh "profiles\$Profile" }
$files = @("$pdir\seven6-trim.jsonl.1", "$pdir\seven6-trim.jsonl") | Where-Object { Test-Path -LiteralPath $_ }
if (-not $files) { "No log yet at $pdir\seven6-trim.jsonl. Install the plugin (install-seven6-trim.ps1), restart Hermes and use it for a while."; return }

$cut = if ($Hours -gt 0) { [DateTimeOffset]::UtcNow.AddHours(-$Hours).ToUnixTimeSeconds() } else { 0 }
$rows = foreach ($f in $files) { Get-Content -LiteralPath $f | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } }
$rows = @($rows | Where-Object { $_ -and $_.ts -ge $cut })
if (-not $rows) { "The log has no rows in that window."; return }

$saving = @('would_trim', 'trimmed')
$summary = $rows | Group-Object tool | ForEach-Object {
    $r = $_.Group
    $elig = @($r | Where-Object { $_.action -in ($saving + 'skip:low_saving' + 'skip:small') })
    $sv = ($r | Where-Object { $_.action -in $saving } | Measure-Object saved -Sum).Sum
    [pscustomobject]@{
        Tool        = $_.Name
        Calls       = $r.Count
        CharsSeen   = ($r | Measure-Object chars_in -Sum).Sum
        AvgChars    = [int](($r | Measure-Object chars_in -Average).Average)
        MaxChars    = ($r | Measure-Object chars_in -Maximum).Maximum
        Saved       = [int]$sv
        Actions     = (($r | Group-Object action | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' ')
    }
} | Sort-Object CharsSeen -Descending
$summary | Format-Table Tool, Calls, CharsSeen, AvgChars, MaxChars, Saved, Actions -AutoSize | Out-String -Width 220

$seen = ($rows | Measure-Object chars_in -Sum).Sum
$sv = ($rows | Where-Object { $_.action -in $saving } | Measure-Object saved -Sum).Sum
$mode = ($rows | Select-Object -Last 1).mode
"Window: {0} results of 1,000+ characters, {1:N0} characters seen (about {2:N0} tokens)." -f $rows.Count, $seen, ($seen / 4)
"Trim {0}: {1:N0} characters (about {2:N0} tokens), {3:P0} of what was seen." -f $(if ($mode -eq 'trim') { 'saved' } else { 'would save' }), $sv, ($sv / 4), $(if ($seen) { $sv / $seen } else { 0 })
$unlisted = @($summary | Where-Object { $_.Actions -match 'skip:not_listed' -and $_.AvgChars -gt 6000 })
if ($unlisted) { "Large results from tools the trimmer does not touch: " + (($unlisted | ForEach-Object { "$($_.Tool) (avg $($_.AvgChars))" }) -join ', ') + ". Add them to plugins.entries.seven6-trim.settings.tools if you want them trimmed." }
