"""Unit tests for the seven6-trim plugin (stdlib only).

  python test_seven6_trim.py
"""
import importlib.util
import json
import os
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("seven6_trim", HERE / "seven6-trim" / "__init__.py")
trim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trim)


def run(cfg_over=None, **call):
    """Call the hook once with a captured log; return (returned value, log rows)."""
    cfg = trim.normalise_settings(cfg_over or {})
    rows = []
    cb = trim.make_callback(cfg, log=rows.append)
    value = cb(**call)
    return value, rows


def big_web_json(n_items=60, text_len=400):
    return json.dumps({"results": [{"title": f"t{i}", "snippet": "x" * text_len, "empty": "", "none": None,
                                    "tags": []} for i in range(n_items)]})


class Settings(unittest.TestCase):
    def test_defaults(self):
        cfg = trim.normalise_settings({})
        self.assertEqual(cfg["mode"], "observe")
        self.assertEqual(cfg["min_chars"], 6000)
        self.assertIn("mcp_*", cfg["tools"])

    def test_env_override_and_bad_values(self):
        cfg = trim.normalise_settings({"mode": "observe", "min_chars": "abc", "tools": "oops"}, env_mode="TRIM")
        self.assertEqual(cfg["mode"], "trim")
        self.assertEqual(cfg["min_chars"], 6000)
        self.assertEqual(cfg["tools"], trim.DEFAULTS["tools"])

    def test_unknown_mode_falls_back_to_observe(self):
        self.assertEqual(trim.normalise_settings({"mode": "destroy"})["mode"], "observe")


class Shrinking(unittest.TestCase):
    def test_json_drops_empties_keeps_falsey_values(self):
        out = trim.shrink_json({"a": None, "b": "", "c": [], "d": {}, "e": 0, "f": False, "g": "x"}, 25, 4000)
        self.assertEqual(out, {"e": 0, "f": False, "g": "x"})

    def test_json_cuts_lists_and_strings_and_stays_valid(self):
        doc = {"items": list(range(100)), "text": "y" * 10000}
        out = trim.shrink_json(doc, 10, 1000)
        self.assertEqual(len(out["items"]), 11)
        self.assertIn("more items omitted", out["items"][-1])
        self.assertLess(len(out["text"]), 1100)
        json.loads(json.dumps(out))

    def test_squeeze_text(self):
        text = "a  \nb\nb\nb\n\n\n\n\nc"
        self.assertEqual(trim.squeeze_text(text), "a\nb\n\nc")

    def test_cut_middle_keeps_head_and_tail(self):
        lines = [f"line {i} " + "z" * 60 for i in range(400)]
        text = "\n".join(lines)
        out = trim.cut_middle(text, 3500, 1500)
        self.assertTrue(out.startswith("line 0 "))
        self.assertTrue(out.rstrip().endswith("z" * 60))
        self.assertIn("characters omitted from the middle", out)
        self.assertLess(len(out), len(text))
        self.assertLess(len(out), 3500 + 1500 + 400)

    def test_cut_middle_leaves_short_text(self):
        self.assertEqual(trim.cut_middle("short", 3500, 1500), "short")


class Hook(unittest.TestCase):
    def test_observe_changes_nothing_and_logs_would_trim(self):
        value, rows = run(tool_name="web_search", result=big_web_json(), duration_ms=12, status="ok")
        self.assertIsNone(value)
        self.assertEqual(rows[0]["action"], "would_trim")
        self.assertGreater(rows[0]["saved"], 0)
        self.assertEqual(rows[0]["mode"], "observe")
        self.assertNotIn("result", rows[0])

    def test_trim_mode_returns_shorter_valid_json(self):
        src = big_web_json()
        value, rows = run({"mode": "trim"}, tool_name="web_search", result=src, status="ok")
        self.assertIsInstance(value, str)
        self.assertLess(len(value), len(src))
        json.loads(value)
        self.assertEqual(rows[0]["action"], "trimmed")

    def test_text_result_in_trim_mode(self):
        src = "\n".join(f"row {i} " + "q" * 70 for i in range(300))
        value, rows = run({"mode": "trim"}, tool_name="mcp_open-websearch_search", result=src, status="ok")
        self.assertIsInstance(value, str)
        self.assertLess(len(value), len(src))
        self.assertEqual(rows[0]["action"], "trimmed")

    def test_never_list_wins(self):
        value, rows = run({"mode": "trim"}, tool_name="read_file", result="x" * 20000, status="ok")
        self.assertIsNone(value)
        self.assertEqual(rows[0]["action"], "skip:never")

    def test_unlisted_tool_is_logged_not_trimmed(self):
        value, rows = run({"mode": "trim"}, tool_name="some_other_tool", result="x" * 20000, status="ok")
        self.assertIsNone(value)
        self.assertEqual(rows[0]["action"], "skip:not_listed")

    def test_errors_are_never_trimmed(self):
        value, rows = run({"mode": "trim"}, tool_name="web_extract", result="e" * 20000, status="error")
        self.assertIsNone(value)
        self.assertEqual(rows[0]["action"], "skip:error")

    def test_tiny_results_are_not_logged(self):
        value, rows = run(tool_name="web_search", result="x" * 500, status="ok")
        self.assertIsNone(value)
        self.assertEqual(rows, [])

    def test_mid_size_results_are_logged_as_small(self):
        value, rows = run(tool_name="web_search", result="x" * 3000, status="ok")
        self.assertIsNone(value)
        self.assertEqual(rows[0]["action"], "skip:small")

    def test_low_saving_is_skipped(self):
        compact = json.dumps({"items": [f"v{i}" for i in range(20)], "blob": "k" * 7000})
        value, rows = run({"mode": "trim", "min_saving_pct": 90}, tool_name="web_search", result=compact, status="ok")
        self.assertIsNone(value)
        self.assertEqual(rows[0]["action"], "skip:low_saving")

    def test_non_string_and_garbage_inputs_never_raise(self):
        for bad in ({"a": 1}, None, 12, b"bytes"):
            value, rows = run(tool_name="web_search", result=bad, status="ok")
            self.assertIsNone(value)
        value, rows = run(tool_name=None, result="x" * 9000, status=None)
        self.assertIsNone(value)

    def test_extra_hook_kwargs_are_ignored(self):
        value, rows = run(tool_name="web_search", args={"q": "x"}, result=big_web_json(), duration_ms=5,
                          status="ok", task_id="t", session_id="s", tool_call_id="c", error_type=None,
                          error_message=None, turn_id="u", api_request_id="r")
        self.assertIsNone(value)
        self.assertEqual(rows[0]["action"], "would_trim")


class Registration(unittest.TestCase):
    def test_register_hooks_transform_tool_result(self):
        seen = {}

        class Ctx:
            def get_config(self, key, default=None):
                return {"mode": "trim"}.get(key, default)

            def register_hook(self, name, cb):
                seen[name] = cb

        old = os.environ.pop("SEVEN6_TRIM_MODE", None)
        try:
            trim.register(Ctx())
        finally:
            if old is not None:
                os.environ["SEVEN6_TRIM_MODE"] = old
        self.assertIn("transform_tool_result", seen)
        self.assertTrue(callable(seen["transform_tool_result"]))

    def test_register_survives_a_broken_config_reader(self):
        class Ctx:
            def get_config(self, key, default=None):
                raise RuntimeError("config unavailable")

            def register_hook(self, name, cb):
                self.hooked = name

        ctx = Ctx()
        trim.register(ctx)
        self.assertEqual(ctx.hooked, "transform_tool_result")


if __name__ == "__main__":
    unittest.main(verbosity=2)
