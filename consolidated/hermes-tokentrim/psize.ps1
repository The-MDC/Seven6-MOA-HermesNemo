param([Parameter(Mandatory)][string]$ProfileName, [string]$Label, [string]$Platform = 'cli')
# One-line offline measurement of the fixed per-request prompt (system prompt + tool schemas) via `hermes prompt-size --json`.
$raw = hermes -p $ProfileName prompt-size --platform $Platform --json 2>&1 | Out-String
$i = $raw.IndexOf('{')
if ($i -lt 0) { "$ProfileName : no JSON from prompt-size"; $raw; return }
$o = $raw.Substring($i) | ConvertFrom-Json
$sys = [int]$o.system_prompt.chars; $tools = [int]$o.tools.json_bytes
$tot = $sys + $tools
if (-not $Label) { $Label = $ProfileName }
'{0,-34} system {1,6:N0} (skills {2,6:N0}, mem+profile {3,5:N0}) | tools {4,2} = {5,6:N0} | total {6,7:N0} chars ~{7,6:N0} tok' -f $Label, $sys, [int]$o.skills_index.chars, ([int]$o.memory.chars + [int]$o.user_profile.chars), [int]$o.tools.count, $tools, $tot, [math]::Round($tot / 4)
