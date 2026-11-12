"""Print the tool-call flow of a Hermes session (read-only).  python sessflow.py <path to state.db> [session id]  (default: newest)"""
import json, sqlite3, sys
db, sid = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else None)
con = sqlite3.connect('file:' + db.replace('\\', '/') + '?mode=ro', uri=True)
if not sid:
    sid = con.execute('select id from sessions order by started_at desc limit 1').fetchone()[0]
m = con.execute('select model, api_call_count, input_tokens, cache_read_tokens, output_tokens from sessions where id=?', (sid,)).fetchone()
print(f'session {sid}  model {m[0]}  api_calls {m[1]}  in {m[2]:,}  cache_read {m[3]:,}  out {m[4]:,}')
for role, content, tcalls, tname in con.execute('select role, content, tool_calls, tool_name from messages where session_id=? order by id', (sid,)):
    c = content or ''
    tc = ''
    if tcalls:
        try:
            tc = '; '.join('%s(%s)' % (t.get('function', {}).get('name'), (t.get('function', {}).get('arguments') or '')[:120]) for t in json.loads(tcalls))
        except Exception:
            tc = tcalls[:160]
    print('%-9s %-14s %6d chars  %s%s' % (role, tname or '', len(c), tc, ('  | ' + c[:90].replace('\n', ' ')) if role != 'tool' and not tc else ''))
