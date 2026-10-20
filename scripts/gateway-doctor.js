#!/usr/bin/env node
'use strict';
/*
 * gateway-doctor: find the two faults that stopped Hermes Desktop's gateway.
 *
 *   1. A sticky non-default profile. Hermes runs ONE host gateway per machine, from
 *      the `default` profile. When `<HERMES_HOME>/active_profile` names another
 *      profile, `hermes gateway run` exits 78 ("Profile 'x' does not get a gateway
 *      of its own"). Fix: `hermes profile use default`.
 *   2. A git-symlink stub in an installed plugin. Git on Windows (core.symlinks
 *      off) writes a symlink as a tiny text file holding its target, for example
 *      `../pkg/desktop/plugin.js`. Desktop evaluates that text as JavaScript and
 *      reports "failed to load: Unexpected token '.'".
 *
 * usage: node scripts/gateway-doctor.js [--home <dir>] [--no-cli]
 *   --home    Hermes home to inspect (default: $HERMES_HOME, else
 *             %LOCALAPPDATA%\hermes on Windows, ~/.hermes elsewhere)
 *   --no-cli  skip the `hermes profile list` / `hermes gateway status` echo
 * exits: 0 = no fault found, 1 = a fault found, 2 = bad arguments
 *
 * Read-only. It never edits the Hermes home.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const args = process.argv.slice(2);
let homeArg = null;
let runCli = true;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--home') homeArg = args[++i];
  else if (args[i] === '--no-cli') runCli = false;
  else { console.error(`unknown argument: ${args[i]}`); process.exit(2); }
}
if (args.includes('--home') && !homeArg) { console.error('--home needs a directory'); process.exit(2); }

const home = homeArg
  || process.env.HERMES_HOME
  || (process.platform === 'win32'
    ? path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'hermes')
    : path.join(os.homedir(), '.hermes'));

let failed = 0;
const ok = (m) => console.log(`  ok    ${m}`);
const bad = (m) => { failed++; console.log(`  FAIL  ${m}`); };
const info = (m) => console.log(`        ${m}`);

console.log(`Hermes home: ${home}`);
if (!fs.existsSync(home)) {
  bad(`${home} does not exist. Set HERMES_HOME or pass --home.`);
  process.exit(1);
}

// 1. sticky profile
console.log('\nactive profile');
const activeFile = path.join(home, 'active_profile');
if (!fs.existsSync(activeFile)) {
  ok('no active_profile file: the default profile is active');
} else {
  const name = fs.readFileSync(activeFile, 'utf8').trim();
  if (name === '' || name === 'default') {
    ok(`active_profile names '${name || 'default'}'`);
  } else {
    bad(`active_profile is '${name}'. A named profile gets no gateway of its own (exit 78).`);
    info('fix:  hermes profile use default');
    info('then: hermes gateway install');
  }
}

// 2. symlink stubs in plugin trees
console.log('\nplugin symlink stubs');
const STUB = /^\.{1,2}[\\/][^\s]+$/;
const SKIP = new Set(['node_modules', '.git', '__pycache__', '.venv', 'venv']);
const found = [];
function walk(dir, depth) {
  if (depth > 8) return;
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    if (SKIP.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { walk(p, depth + 1); continue; }
    if (!/\.(c|m)?js$/.test(e.name)) continue;
    let st;
    try { st = fs.statSync(p); } catch { continue; }
    if (st.size > 512) continue;
    const text = fs.readFileSync(p, 'utf8').trim();
    if (!text.includes('\n') && STUB.test(text)) found.push({ p, text });
  }
}
const pluginsDir = path.join(home, 'plugins');
if (fs.existsSync(pluginsDir)) walk(pluginsDir, 0);
else info(`no plugins directory at ${pluginsDir}`);
if (found.length === 0) {
  ok('no JavaScript file consists of a bare relative path');
} else {
  for (const f of found) {
    bad(`${f.p} is a symlink stub pointing at '${f.text}'`);
  }
  info('fix:  remove the plugin and reinstall it from a commit where the file is a real file,');
  info('      or run `hermes plugins disable <name>` to silence the load error.');
}

// 3. echo what Hermes itself says
if (runCli) {
  console.log('\nhermes (echo, not parsed)');
  for (const sub of [['profile', 'list'], ['gateway', 'status']]) {
    const r = spawnSync('hermes', sub, { encoding: 'utf8', timeout: 30000, shell: process.platform === 'win32' });
    if (r.error) { info(`hermes ${sub.join(' ')}: ${r.error.code === 'ENOENT' ? 'hermes not on PATH' : r.error.message}`); continue; }
    info(`$ hermes ${sub.join(' ')}   (exit ${r.status})`);
    for (const line of `${r.stdout || ''}${r.stderr || ''}`.split(/\r?\n/).filter(Boolean).slice(0, 12)) info(`  ${line}`);
  }
}

console.log(failed ? `\n${failed} fault(s) found.` : '\nno fault found.');
process.exit(failed ? 1 : 0);
