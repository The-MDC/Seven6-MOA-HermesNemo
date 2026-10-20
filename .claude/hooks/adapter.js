/**
 * adapter.js - the module the working hooks in this directory require.
 *
 * It provides `readStdin` and nothing else. before-submit-prompt.js (secret scanning)
 * and after-mcp-execution.js (MCP result logging) need it.
 *
 * Why it matters: a hook that crashes on `require('./adapter')` still exits, so the
 * session continues and nothing reports that the hook did not run.
 */

'use strict';

/**
 * Read the hook payload from stdin.
 *
 * Claude Code writes a single JSON object to the hook's stdin and reads stdout back.
 * Resolves to the raw string so callers can both parse it and echo it through
 * unchanged - every hook here is pass-through and must not alter the payload.
 */
function readStdin() {
  return new Promise((resolve) => {
    let data = '';
    // A hook invoked with no stdin (a manual run, a smoke test) must not hang.
    if (process.stdin.isTTY) return resolve('');
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => { data += chunk; });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', () => resolve(data));
  });
}

module.exports = { readStdin };
