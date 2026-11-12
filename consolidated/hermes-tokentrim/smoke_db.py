"""Read-only look at one Hermes session in a profile's state.db (stdlib only).

  python smoke_db.py <profile_dir> <session_id>

Prints ONE json line: the tools the session called, the session ids involved (the session and any child sessions
that delegation created) and the models used per session and task. Never prints message text.
"""
import json
import pathlib
import sqlite3
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(json.dumps({"error": "usage: smoke_db.py <profile_dir> <session_id>"}))
        return 2
    db = pathlib.Path(sys.argv[1]) / "state.db"
    sid = sys.argv[2]
    if not db.exists():
        print(json.dumps({"error": f"no state.db in {sys.argv[1]}"}))
        return 2
    con = sqlite3.connect("file:" + db.as_posix() + "?mode=ro", uri=True, timeout=10)
    cur = con.cursor()
    ids = [sid] + [r[0] for r in cur.execute("select id from sessions where parent_session_id = ?", (sid,))]
    marks = ",".join("?" for _ in ids)
    tools = {}
    for name, n in cur.execute(
            f"select tool_name, count(*) from messages where session_id in ({marks}) and role = 'tool' "
            f"and tool_name is not null group by 1", ids):
        tools[name] = n
    usage = [
        {"session": r[0], "model": r[1], "provider": r[2], "task": r[3], "calls": r[4]}
        for r in cur.execute(
            f"select session_id, model, billing_provider, task, api_call_count from session_model_usage "
            f"where session_id in ({marks}) order by session_id, task", ids)
    ]
    children = [{"id": r[0], "model": r[1]} for r in cur.execute(
        "select id, model from sessions where parent_session_id = ?", (sid,))]
    con.close()
    print(json.dumps({"session": sid, "sessions": ids, "children": children, "tools": tools, "usage": usage}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
