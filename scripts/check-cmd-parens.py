#!/usr/bin/env python3
"""Fail on an unescaped ")" inside a parenthesised cmd.exe block.

cmd.exe ends an `if (...) else (...)` block at the first bare ")" in ANY line of
it, echo text included. The launchers print a PowerShell hint such as
    (Get-Command node).Source
inside such a block; the ")" closed the block early and the user saw
    .Source was unexpected at this time.
instead of the intended "HERMES_CODEX_NODE is not set" message. Escape as ^).

Usage: check-cmd-parens.py FILE.cmd ...   (exit 1 on any hit)
"""
import re,sys
bad=0
for p in sys.argv[1:]:
    depth=0
    for n,l in enumerate(open(p,encoding='utf-8',errors='replace'),1):
        s=l.rstrip('\n'); t=s.strip()
        if t.upper().startswith('REM'): continue
        if depth and t.startswith(')'):
            depth-=1
            if t.endswith('('): depth+=1
            continue
        if depth:
            body=re.sub(r'\^\)','',s)
            if ')' in body:
                print(f"{p}:{n}: unescaped ) inside block: {t[:90]}"); bad+=1
        if t.endswith('('): depth+=1
sys.exit(1 if bad else 0)
