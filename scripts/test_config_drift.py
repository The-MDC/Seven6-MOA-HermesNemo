#!/usr/bin/env python3
"""Tests for check-config-drift.py. A drift check that cannot fail is not a check.

Every case builds an installed config from the real repo config, breaks it in ONE
way, and runs the real script as a subprocess, so the exit code and the output are
what the box will see. The "must fail" cases are the point of the file: remove a
detector from the checker and the matching test goes red.

Run:  python3 -I scripts/test_config_drift.py
"""
import copy
import os
import subprocess
import sys
import tempfile
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "check-config-drift.py")
GOLDEN = os.path.join(HERE, "..", "configs", "hermes", "config.yaml")

with open(GOLDEN, encoding="utf-8") as fh:
    GOLDEN_TEXT = fh.read()
GOLDEN_CFG = yaml.safe_load(GOLDEN_TEXT)


def run(installed_text, *extra, golden=GOLDEN):
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "installed.yaml")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(installed_text)
        p = subprocess.run(
            [sys.executable, "-I", SCRIPT, "--golden", golden, "--installed", path, *extra],
            capture_output=True, text=True, timeout=60,
        )
    return p.returncode, p.stdout + p.stderr


def dump(cfg):
    return yaml.safe_dump(cfg, sort_keys=False)


def mutated(fn):
    cfg = copy.deepcopy(GOLDEN_CFG)
    fn(cfg)
    return dump(cfg)


class FullConfig(unittest.TestCase):
    def test_repo_against_itself_passes(self):
        code, out = run(GOLDEN_TEXT)
        self.assertEqual(code, 0, out)

    def test_migration_style_extra_keys_pass(self):
        # What the v0 -> v51 migration did: extra keys, nothing else changed.
        def f(c):
            c["some_new_upstream_section"] = {"enabled": True}
            c["gateway"]["new_flag"] = 1
        code, out = run(mutated(f))
        self.assertEqual(code, 0, out)

    def test_changed_main_model_fails_and_names_the_key(self):
        def f(c):
            c["model"]["default"] = "nvidia/nemotron-3-ultra-550b-a55b"
        code, out = run(mutated(f))
        self.assertEqual(code, 1, out)
        self.assertIn("model.default", out)

    def test_changed_main_provider_fails(self):
        def f(c):
            c["model"]["provider"] = "custom:or-fallback"
        code, out = run(mutated(f))
        self.assertEqual(code, 1, out)
        self.assertIn("model.provider", out)

    def test_auto_auxiliary_slot_fails(self):
        def f(c):
            c["auxiliary"]["vision"]["provider"] = "auto"
        code, out = run(mutated(f))
        self.assertEqual(code, 1, out)
        self.assertIn("auxiliary", out)
        self.assertIn("vision", out)

    def test_empty_auxiliary_model_fails(self):
        def f(c):
            c["auxiliary"]["compression"]["model"] = ""
        code, out = run(mutated(f))
        self.assertEqual(code, 1, out)
        self.assertIn("compression", out)

    def test_removed_auxiliary_slot_fails(self):
        def f(c):
            del c["auxiliary"]["vision"]
        code, out = run(mutated(f))
        self.assertEqual(code, 1, out)
        self.assertIn("auxiliary.vision", out)

    def test_fallback_order_change_fails(self):
        def f(c):
            c["fallback_providers"].reverse()
        code, out = run(mutated(f))
        self.assertEqual(code, 1, out)
        self.assertIn("fallback_providers", out)

    def test_moa_aggregator_change_fails_in_both_shapes(self):
        def flat(c):
            c["moa"]["aggregator"]["model"] = "nvidia/nemotron-3-ultra-550b-a55b"
        code, out = run(mutated(flat))
        self.assertEqual(code, 1, out)
        self.assertIn("moa.aggregator", out)

        def preset(c):
            c["moa"]["presets"]["default"]["aggregator"]["model"] = "nvidia/nemotron-3-ultra-550b-a55b"
        code, out = run(mutated(preset))
        self.assertEqual(code, 1, out)
        self.assertIn("moa.presets.default.aggregator", out)

    def test_moa_reference_roster_change_fails(self):
        def f(c):
            c["moa"]["reference_models"].pop()
        code, out = run(mutated(f))
        self.assertEqual(code, 1, out)
        self.assertIn("moa.reference_models", out)

    def test_renamed_provider_dangles_every_reference(self):
        def f(c):
            c["providers"]["nim"] = c["providers"].pop("nvidia-nim")
        code, out = run(mutated(f))
        self.assertEqual(code, 1, out)
        self.assertIn("dangling", out)

    def test_changed_endpoint_fails(self):
        def f(c):
            c["providers"]["nvidia-nim"]["api"] = "https://example.invalid/v1"
        code, out = run(mutated(f))
        self.assertEqual(code, 1, out)
        self.assertIn("providers.nvidia-nim.api", out)

    def test_excluded_providers_change_fails(self):
        def f(c):
            c["excluded_providers"].remove("openrouter")
        code, out = run(mutated(f))
        self.assertEqual(code, 1, out)
        self.assertIn("excluded_providers", out)

    def test_missing_gateway_and_version_keys_only_warn(self):
        def f(c):
            del c["gateway"]
            del c["_config_version"]
        code, out = run(mutated(f))
        self.assertEqual(code, 0, out)
        self.assertIn("warn", out)
        self.assertIn("gateway.multiplex_profiles", out)

    def test_key_shaped_string_fails_and_is_never_printed(self):
        secret = "nvapi-" + "A1b2C3d4E5f6G7h8I9j0K1l2M3"
        text = GOLDEN_TEXT + f"\nstray: {secret}\n"
        code, out = run(text)
        self.assertEqual(code, 1, out)
        self.assertIn("key", out.lower())
        self.assertNotIn(secret, out)
        self.assertNotIn("A1b2C3d4", out)

    def test_invariants_do_not_trust_the_golden(self):
        # Golden and installed are the SAME broken file: drift is zero, so only the
        # invariants can catch it. An id not listed under its provider resolves
        # silently to the main model.
        def f(c):
            c["model"]["default"] = "nvidia/not-a-listed-model"
        with tempfile.TemporaryDirectory() as d:
            broken = os.path.join(d, "broken.yaml")
            with open(broken, "w", encoding="utf-8") as fh:
                fh.write(mutated(f))
            p = subprocess.run(
                [sys.executable, "-I", SCRIPT, "--golden", broken, "--installed", broken],
                capture_output=True, text=True, timeout=60,
            )
        self.assertEqual(p.returncode, 1, p.stdout)
        self.assertIn("NOT listed", p.stdout)


class InvariantsAlone(unittest.TestCase):
    """Golden and installed are the SAME broken file, so drift is zero and only the
    invariants can fail. Without these, a golden that was copied over the installed
    file (or went stale the same way) would bless an `auto` slot."""

    def _same_file(self, fn):
        with tempfile.TemporaryDirectory() as d:
            broken = os.path.join(d, "broken.yaml")
            with open(broken, "w", encoding="utf-8") as fh:
                fh.write(mutated(fn))
            p = subprocess.run(
                [sys.executable, "-I", SCRIPT, "--golden", broken, "--installed", broken],
                capture_output=True, text=True, timeout=60,
            )
        return p.returncode, p.stdout + p.stderr

    def test_auto_provider_fails_with_zero_drift(self):
        def f(c):
            c["auxiliary"]["vision"]["provider"] = "auto"
        code, out = self._same_file(f)
        self.assertEqual(code, 1, out)
        self.assertIn("vision", out)

    def test_empty_model_fails_with_zero_drift(self):
        def f(c):
            c["auxiliary"]["compression"]["model"] = ""
        code, out = self._same_file(f)
        self.assertEqual(code, 1, out)
        self.assertIn("compression", out)

    def test_missing_auxiliary_block_fails_in_a_full_config(self):
        def f(c):
            del c["auxiliary"]
        code, out = self._same_file(f)
        self.assertEqual(code, 1, out)
        self.assertIn("auxiliary", out)

    def test_dangling_reference_fails_with_zero_drift(self):
        def f(c):
            c["moa"]["aggregator"]["provider"] = "custom:does-not-exist"
            c["moa"]["presets"]["default"]["aggregator"]["provider"] = "custom:does-not-exist"
        code, out = self._same_file(f)
        self.assertEqual(code, 1, out)
        self.assertIn("dangling", out)


class Unreadable(unittest.TestCase):
    def test_missing_file_is_exit_2_not_a_pass(self):
        p = subprocess.run(
            [sys.executable, "-I", SCRIPT, "--golden", GOLDEN, "--installed", "/nonexistent/config.yaml"],
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)

    def test_invalid_yaml_is_exit_2(self):
        code, out = run("model: [unterminated\n  - x: : :\n")
        self.assertEqual(code, 2, out)

    def test_empty_file_is_exit_2(self):
        code, out = run("")
        self.assertEqual(code, 2, out)

    def test_empty_mapping_is_exit_2(self):
        # `{}` parses to a dict, so only the non-empty check rejects it.
        code, out = run("{}\n")
        self.assertEqual(code, 2, out)

    def test_non_mapping_is_exit_2(self):
        code, out = run("- just\n- a list\n")
        self.assertEqual(code, 2, out)


class Profile(unittest.TestCase):
    def test_partial_profile_inherits_and_passes(self):
        text = dump({"model": copy.deepcopy(GOLDEN_CFG["model"])})
        code, out = run(text, "--profile")
        self.assertEqual(code, 0, out)
        self.assertIn("not set here", out)

    def test_empty_routing_profile_says_nothing_was_compared(self):
        code, out = run(dump({"display": {"theme": "dark"}}), "--profile")
        self.assertEqual(code, 0, out)
        self.assertIn("nothing to compare", out)
        self.assertNotIn("none differ", out)
        # An `ok` line about routing keys here would claim a match nothing established.
        self.assertNotRegex(out, r"(?m)^\s+ok\s+.*routing")

    def test_profile_on_another_model_warns_by_default_and_fails_when_strict(self):
        text = dump({"model": {"provider": "custom:local",
                               "default": GOLDEN_CFG["providers"]["local"]["default_model"]}})
        code, out = run(text, "--profile")
        self.assertEqual(code, 0, out)
        self.assertIn("warn", out)
        self.assertIn("model.provider", out)
        code, out = run(text, "--profile", "--strict")
        self.assertEqual(code, 1, out)
        self.assertIn("model.provider", out)

    def test_profile_with_auto_slot_fails_even_without_strict(self):
        text = dump({"auxiliary": {"vision": {"provider": "auto", "model": "auto"}}})
        code, out = run(text, "--profile")
        self.assertEqual(code, 1, out)
        self.assertIn("vision", out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
