#!/usr/bin/env node
/**
 * pre-bash-guard.js — PreToolUse on Bash. The one hook here that can block.
 *
 * WHY THIS EXISTS
 *     A git hook-bypass flag silently skips a hook the repository installed on
 *     purpose. This blocks it with no dependencies and no network (an `npx` check
 *     would reach the registry on every shell command, which the agent container
 *     cannot do at all).
 *
 *WHAT IT BLOCKS
 *     --no-verify / -n on git commit and git push, and --no-gpg-sign, because each
 *     silently skips a hook the repository installed on purpose. The block is
 *     advisory in the sense that you can still run the command yourself in a
 *     terminal; what it prevents is an agent skipping the gate without saying so.
 *
 * WHAT IT DOES NOT DO
 *     It does not parse shell grammar. A sufficiently creative command can evade
 *     it. This is a guardrail against absent-mindedness, not an adversary.
 */

'use strict';

const fs = require('fs');

/** git commit -n / --no-verify, git push --no-verify, and unsigned commits. */
const PATTERNS = [
  {
    re: /\bgit\b[^\n;|&]*\b(commit|push|merge|rebase)\b[^\n;|&]*\s--no-verify\b/,
    why: '--no-verify skips the pre-commit, commit-msg and pre-push hooks this repository installs on purpose.',
  },
  {
    re: /\bgit\b[^\n;|&]*\bcommit\b[^\n;|&]*\s-n(?=\s|$)/,
    why: '`git commit -n` is --no-verify in short form; it skips the commit hooks.',
  },
  {
    re: /\bgit\b[^\n;|&]*\s--no-gpg-sign\b/,
    why: '--no-gpg-sign drops commit signing.',
  },
];

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function allow() {
  process.exit(0); // Silence is consent. No output means "no opinion".
}

function deny(reason) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'deny',
        permissionDecisionReason: reason,
      },
    }) + '\n'
  );
  process.exit(0);
}

function main() {
  const raw = readStdin();
  if (!raw.trim()) return allow();

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    return allow();
  }

  const command = payload?.tool_input?.command;
  if (typeof command !== 'string' || !command) return allow();

  for (const { re, why } of PATTERNS) {
    if (re.test(command)) {
      return deny(
        `Blocked by pre-bash-guard: ${why}\n\n` +
          `If the hook is genuinely wrong — a generated lockfile it cannot parse, ` +
          `say — fix the hook or run the command yourself. Do not route around the ` +
          `gate silently; that is the failure this guard exists to prevent.`
      );
    }
  }
  allow();
}

try {
  main();
} catch {
  allow(); // A broken guard must fail open, never wedge the session.
}
