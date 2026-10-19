# `.claude/hooks/`

`.claude/settings.json` is the only file Claude Code reads hooks from. It never reads
`.claude/hooks/hooks.json`. `scripts/repo-doctor.sh` validates `settings.json` and warns
if a `hooks.json` ever appears, because nothing would execute it.

## What runs now

All five are wired in `.claude/settings.json`.

| Hook | Event | Matcher | Does |
|---|---|---|---|
| `before-submit-prompt.js` | `UserPromptSubmit` | — | Secret scanning on the prompt. |
| `after-mcp-execution.js` | `PostToolUse` | `mcp__.*` | MCP result logging. |
| `post-edit-check.js` | `PostToolUse` | `Write\|Edit` | console.log warning · Prettier · `tsc --noEmit`. |
| `pre-bash-guard.js` | `PreToolUse` | `Bash` | Blocks `--no-verify` / `-n` / `--no-gpg-sign` on git. |
| `stop-audit.js` | `Stop` | — | console.log sweep across changed files. |

The last three implement what `.claude/rules/typescript-hooks.md` already
specified: Prettier auto-format, TypeScript check, console.log warning, and an
end-of-session console.log audit.

### Design rules they all follow

**Only `pre-bash-guard.js` can block.** Everything else is advisory and exits 0
regardless. A formatting opinion is not worth killing a turn over.

**No network, ever.** Prettier and `tsc` run only if a *local* `node_modules/.bin`
binary exists. An `npx` check would reach the registry on every shell command; the
agent container gets 403 from npm. Absent tooling is skipped silently,
not treated as failure.

**They fail open.** Every one is wrapped so a bug in a hook cannot wedge a session.

**Zero dependencies.** The console.log checks are plain Node string work, so they
are the part that always functions regardless of what is installed.

## Verification

Both directions were exercised, because a gate that can only pass is not a gate:

- `post-edit-check.js` — flags `console.log` at the right line numbers, ignores
  commented-out ones, silent on clean files, ignores non-code extensions.
- `pre-bash-guard.js` — 4/4 bypass forms denied, 5/5 ordinary commands allowed.
- `stop-audit.js` — proven non-vacuous by planting a `console.log` in a changed
  file (detected, correct line), then removing it (silent again).
- `repo-doctor.sh` — exits **1** when a wired hook points at a missing script,
  exits **0** on the current tree, and warns if `hooks.json` appears.
