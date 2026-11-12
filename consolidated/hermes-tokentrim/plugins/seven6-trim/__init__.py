"""seven6-trim: measure, then optionally shorten, large tool results before they reach the model.

Hook used: ``transform_tool_result``. Hermes runs it after ``post_tool_call`` and before the result enters
the conversation. It is fail-open (an exception here never breaks a tool call) and the first string a
callback returns replaces the result.

Default mode is OBSERVE: nothing is changed. Every result of 1,000+ characters is logged to
``<HERMES_HOME>/seven6-trim.jsonl`` with its tool name, size and what a trim would have saved, so the
saving can be measured before anything is trimmed. Tool arguments and result text are never written.

Settings live in config.yaml under ``plugins.entries.seven6-trim.settings`` (the env var SEVEN6_TRIM_MODE
overrides ``mode``):

  mode              observe | trim                                    default observe
  min_chars         results shorter than this are never touched       default 6000
  head_chars        characters kept from the start of a text result   default 3500
  tail_chars        characters kept from the end of a text result     default 1500
  max_list_items    JSON lists longer than this are cut               default 25
  max_string_chars  JSON strings longer than this are cut             default 4000
  min_saving_pct    a trim is applied only if it saves this much      default 20
  tools             glob patterns of tools that may be trimmed        default web_extract, web_search, mcp_*
  never             glob patterns that are never trimmed              default file, shell, code, memory, delegation

Errors are never trimmed. A JSON result stays valid JSON: it is shrunk by dropping empty values and cutting long
lists and strings, never cut in the middle of the document.
"""
from __future__ import annotations

import fnmatch
import json
import os
import re
import threading
import time
from pathlib import Path
from typing import Any

_LOCK = threading.Lock()
_LOG_MAX_BYTES = 2 * 1024 * 1024
_LOG_MIN_CHARS = 1000

DEFAULTS: dict[str, Any] = {
    "mode": "observe",
    "min_chars": 6000,
    "head_chars": 3500,
    "tail_chars": 1500,
    "max_list_items": 25,
    "max_string_chars": 4000,
    "min_saving_pct": 20,
    "tools": ["web_extract", "web_search", "mcp_*"],
    "never": [
        "read_file", "write_file", "patch", "search_files", "terminal", "execute_code", "process",
        "delegate_task", "memory", "todo", "clarify", "skill*", "session_search", "cronjob",
    ],
}

_INT_KEYS = ("min_chars", "head_chars", "tail_chars", "max_list_items", "max_string_chars", "min_saving_pct")
_TRAILING_WS = re.compile(r"[ \t]+\n")
_BLANK_RUNS = re.compile(r"\n{3,}")


# ----------------------------------------------------------------------------- settings
def normalise_settings(raw: dict[str, Any] | None, env_mode: str = "") -> dict[str, Any]:
    """Merge user settings over DEFAULTS and coerce every value to a safe type."""
    cfg: dict[str, Any] = dict(DEFAULTS)
    for key in DEFAULTS:
        value = (raw or {}).get(key)
        if value is not None:
            cfg[key] = value
    mode = (env_mode or "").strip().lower() or str(cfg["mode"]).strip().lower()
    cfg["mode"] = "trim" if mode == "trim" else "observe"
    for key in _INT_KEYS:
        try:
            cfg[key] = max(0, int(cfg[key]))
        except (TypeError, ValueError):
            cfg[key] = DEFAULTS[key]
    for key in ("tools", "never"):
        value = cfg[key]
        cfg[key] = [str(x) for x in value] if isinstance(value, (list, tuple)) else list(DEFAULTS[key])
    return cfg


def _load_settings(ctx: Any) -> dict[str, Any]:
    raw: dict[str, Any] = {}
    for key, default in DEFAULTS.items():
        try:
            raw[key] = ctx.get_config(key, default)
        except Exception:
            raw[key] = default
    return normalise_settings(raw, os.environ.get("SEVEN6_TRIM_MODE", ""))


# ----------------------------------------------------------------------------- logging
def _log_path() -> Path | None:
    try:
        from hermes_constants import get_hermes_home
        return Path(get_hermes_home()) / "seven6-trim.jsonl"
    except Exception:
        home = os.environ.get("HERMES_HOME")
        return Path(home) / "seven6-trim.jsonl" if home else None


def _log(row: dict[str, Any]) -> None:
    path = _log_path()
    if path is None:
        return
    line = json.dumps(row, separators=(",", ":"))
    with _LOCK:
        try:
            if path.exists() and path.stat().st_size > _LOG_MAX_BYTES:
                path.replace(path.with_name(path.name + ".1"))
            with path.open("a", encoding="utf-8") as fh:
                fh.write(line + "\n")
        except Exception:
            pass


# ----------------------------------------------------------------------------- shrinking
def _is_empty(value: Any) -> bool:
    return value is None or (isinstance(value, (str, list, dict)) and len(value) == 0)


def shrink_json(obj: Any, max_items: int, max_str: int) -> Any:
    """Drop empty values, cut long lists and long strings. The structure stays valid JSON."""
    if isinstance(obj, dict):
        return {k: shrink_json(v, max_items, max_str) for k, v in obj.items() if not _is_empty(v)}
    if isinstance(obj, list):
        items = [shrink_json(v, max_items, max_str) for v in obj[:max_items]]
        extra = len(obj) - max_items
        if extra > 0:
            items.append(f"[seven6-trim: {extra} more items omitted]")
        return items
    if isinstance(obj, str) and len(obj) > max_str:
        head = int(max_str * 0.7)
        tail = max_str - head
        return f"{obj[:head]} [seven6-trim: {len(obj) - max_str} characters omitted] {obj[len(obj) - tail:]}"
    return obj


def squeeze_text(text: str) -> str:
    """Strip trailing blanks, collapse blank-line runs, drop consecutive duplicate lines."""
    text = _TRAILING_WS.sub("\n", text)
    text = _BLANK_RUNS.sub("\n\n", text)
    out: list[str] = []
    prev: str | None = None
    for line in text.split("\n"):
        if line == prev and line.strip():
            continue
        out.append(line)
        prev = line
    return "\n".join(out)


def cut_middle(text: str, head: int, tail: int) -> str:
    if len(text) <= head + tail + 200:
        return text
    end = text.rfind("\n", max(0, head - 200), head)
    head_end = end if end > 0 else head
    start = text.find("\n", len(text) - tail, len(text) - tail + 200)
    tail_start = start + 1 if 0 <= start else len(text) - tail
    omitted = tail_start - head_end
    note = (f"\n[seven6-trim: {omitted} characters omitted from the middle; "
            f"re-run the tool with a narrower request if the missing part matters]\n")
    return text[:head_end] + note + text[tail_start:]


def shrink(result: str, cfg: dict[str, Any]) -> str:
    parsed: Any = None
    if result.lstrip()[:1] in ("{", "["):
        try:
            parsed = json.loads(result)
        except ValueError:
            parsed = None
    if parsed is not None:
        slim = shrink_json(parsed, cfg["max_list_items"], cfg["max_string_chars"])
        return json.dumps(slim, ensure_ascii=False, separators=(",", ":"))
    return cut_middle(squeeze_text(result), cfg["head_chars"], cfg["tail_chars"])


def _matches(name: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(name, p) for p in patterns)


# ----------------------------------------------------------------------------- the hook
def make_callback(cfg: dict[str, Any], log=_log):
    def on_tool_result(tool_name: str = "", args: Any = None, result: Any = None, duration_ms: int = 0,
                       status: str | None = None, **_ignored: Any):
        try:
            if not isinstance(result, str):
                return None
            n = len(result)
            if n < _LOG_MIN_CHARS:
                return None
            name = str(tool_name or "")
            row: dict[str, Any] = {"ts": round(time.time(), 1), "tool": name, "chars_in": n,
                                   "ms": int(duration_ms or 0), "mode": cfg["mode"]}
            if status not in (None, "", "ok"):
                row["action"] = "skip:error"
            elif _matches(name, cfg["never"]):
                row["action"] = "skip:never"
            elif not _matches(name, cfg["tools"]):
                row["action"] = "skip:not_listed"
            elif n < cfg["min_chars"]:
                row["action"] = "skip:small"
            else:
                shrunk = shrink(result, cfg)
                saved = n - len(shrunk)
                pct = round(100.0 * saved / n, 1)
                row.update({"chars_out": len(shrunk), "saved": saved, "saved_pct": pct})
                if saved <= 0 or pct < cfg["min_saving_pct"]:
                    row["action"] = "skip:low_saving"
                elif cfg["mode"] == "trim":
                    row["action"] = "trimmed"
                    log(row)
                    return shrunk
                else:
                    row["action"] = "would_trim"
            log(row)
            return None
        except Exception:
            return None
    return on_tool_result


def register(ctx: Any) -> None:
    cfg = _load_settings(ctx)
    ctx.register_hook("transform_tool_result", make_callback(cfg))
