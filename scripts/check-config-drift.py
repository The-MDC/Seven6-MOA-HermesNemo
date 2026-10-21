#!/usr/bin/env python3
"""Compare an installed Hermes config against this repo's, on the keys that route inference.

WHY THIS EXISTS
  CI checks the repo copy. Nothing checked the file Hermes actually reads, and three
  things rewrite or bypass it without an error:
    * `hermes update` / `hermes dashboard` migrate the config format (v0 -> v51 did).
    * A model picked in a UI can land in a profile's own config.yaml.
    * `hermes-apply.ps1` writes the root config only; profiles keep whatever they had.
  Every one of those leaves a file that parses and loads. A wrong id does not error:
  with `discover_models: false` it silently resolves to the main model, and an `auto`
  auxiliary slot means "use the main model". So this reads the real file.

WHAT IT CHECKS
  1. INVARIANTS, true of any config regardless of the golden copy:
       - no auxiliary slot is `auto` / empty                      (CLAUDE.md rule 2)
       - every `custom:<name>` reference names a defined provider
       - model.default is listed under its provider's `models:`   (CLAUDE.md rule 1)
       - no key-shaped string anywhere in the file                (never printed)
  2. DRIFT, installed vs golden, on the routing keys only: model, fallback order,
     delegation, moa roster, every auxiliary slot, provider endpoints and model lists,
     excluded_providers. Extra keys in the installed file are fine -- that is what a
     migration adds. A key the golden has and the installed lacks is drift.

  Invariants are independent of the golden on purpose: a golden that went stale (or a
  config that was copied over it) must not be able to bless a broken file.

PROFILES
  A profile's config.yaml may be partial. With --profile, a key that is ABSENT is
  reported as "not set" (the profile may inherit it) and is not drift; a key that is
  PRESENT and different is drift. Drift is a warning unless --strict: a profile such as
  `mylocal` may differ on purpose. Invariant failures are always failures.

EXIT CODES
  0  clean (warnings allowed)     1  invariant or drift failure
  2  a file could not be read or parsed -- never reported as a pass

Prints ids and paths only. Never prints a value that could be a secret.
"""
from __future__ import annotations

import argparse
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - environment, not logic
    print("FAIL  PyYAML is not importable by this interpreter; no check was run", file=sys.stderr)
    sys.exit(2)

OK, FAIL, UNREADABLE = 0, 1, 2

# Shapes only. The match is never echoed.
KEY_SHAPES = [r"nvapi-[A-Za-z0-9_\-]{20,}", r"hf_[A-Za-z0-9]{30,}", r"sk-or-v1-[A-Za-z0-9]{20,}"]

# Top-level scalars/blocks that decide routing. Compared by projection (see project()).
SCALAR_PATHS = [
    ("model", "provider"),
    ("model", "default"),
    ("delegation", "provider"),
    ("delegation", "model"),
    ("moa", "default_preset"),
    ("moa", "aggregator"),
]


class Unreadable(Exception):
    pass


def load(path: str) -> tuple[str, dict]:
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        raise Unreadable(f"cannot read {path}: {exc.strerror or exc}") from exc
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise Unreadable(f"{path} is not valid YAML: {str(exc).splitlines()[0]}") from exc
    if not isinstance(data, dict) or not data:
        raise Unreadable(f"{path} parsed to {type(data).__name__}, not a non-empty mapping")
    return text, data


def get(d: dict, *path):
    """Return (found, value). `found` separates an absent key from an explicit null."""
    cur = d
    for p in path:
        if not isinstance(cur, dict) or p not in cur:
            return False, None
        cur = cur[p]
    return True, cur


def model_ids(provider_block) -> list[str]:
    out = []
    for m in (provider_block or {}).get("models") or []:
        if isinstance(m, str):
            out.append(m)
        elif isinstance(m, dict):
            for k in ("id", "name", "model"):
                if isinstance(m.get(k), str):
                    out.append(m[k])
                    break
    return out


def link(entry) -> tuple:
    """A provider/model pair, ignoring everything that is not routing (enabled, keys)."""
    if isinstance(entry, dict):
        return (entry.get("provider"), entry.get("model"), entry.get("base_url"), entry.get("enabled", True))
    return (entry,)


def pair(v):
    """Project a {provider, model, ...} block to the two fields that route."""
    if isinstance(v, dict):
        return (v.get("provider"), v.get("model"))
    return v


def is_auto(v) -> bool:
    return v is None or (isinstance(v, str) and v.strip().lower() in ("", "auto"))


def provider_refs(node, trail="") -> list[tuple[str, str]]:
    """Every (path, name) where a `provider:` value is `custom:<name>[:...]`."""
    refs = []
    if isinstance(node, dict):
        for k, v in node.items():
            p = f"{trail}.{k}" if trail else str(k)
            if k == "provider" and isinstance(v, str) and v.startswith("custom:"):
                refs.append((p, v.split(":", 2)[1]))
            else:
                refs.extend(provider_refs(v, p))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            refs.extend(provider_refs(v, f"{trail}[{i}]"))
    return refs


class Report:
    def __init__(self, label: str):
        self.label = label
        self.fail = 0
        self.warn = 0

    def ok(self, msg):
        print(f"  ok    {msg}")

    def info(self, msg):
        print(f"  ..    {msg}")

    def warning(self, msg):
        self.warn += 1
        print(f"  warn  {msg}")

    def failure(self, msg):
        self.fail += 1
        print(f"  FAIL  {msg}")


def check_invariants(text: str, cfg: dict, r: Report, partial: bool) -> None:
    # 1. no auto auxiliary slot. A slot that is present and auto is always a failure;
    #    an absent `auxiliary:` block is only "not set" in a partial (profile) file.
    aux = cfg.get("auxiliary")
    if isinstance(aux, dict):
        bad = []
        for slot, v in aux.items():
            if not isinstance(v, dict):
                continue
            if is_auto(v.get("provider")) or is_auto(v.get("model")):
                bad.append(slot)
        if bad:
            r.failure(
                "auxiliary slot(s) on auto/empty: "
                + ", ".join(sorted(bad))
                + " -- `auto` means the main model, so vision and the rest silently follow it"
            )
        else:
            r.ok(f"no auxiliary slot is auto ({len(aux)} slots)")
    elif not partial:
        r.failure("no `auxiliary:` block -- every slot defaults to auto (the main model)")

    # 2. every custom:<name> reference resolves.
    defined = set((cfg.get("providers") or {}).keys())
    refs = provider_refs(cfg)
    if refs:
        if not defined and partial:
            r.info("custom: references present but no `providers:` block here (inherits from root)")
        else:
            dangling = sorted({f"{p} -> custom:{n}" for p, n in refs if n not in defined})
            if dangling:
                r.failure("dangling provider reference(s): " + "; ".join(dangling[:6]))
            else:
                r.ok(f"{len(refs)} custom: reference(s) all resolve")

    # 3. the main model is listed under its provider (the id belongs to the gateway).
    f1, prov = get(cfg, "model", "provider")
    f2, mid = get(cfg, "model", "default")
    if f1 and f2 and isinstance(prov, str) and prov.startswith("custom:"):
        name = prov.split(":", 2)[1]
        block = (cfg.get("providers") or {}).get(name)
        if block is None:
            if not partial:
                r.failure(f"model.provider is custom:{name}, which is not defined")
        elif mid in model_ids(block):
            r.ok(f"model.default is listed under providers.{name}.models")
        else:
            r.failure(f"model.default '{mid}' is NOT listed under providers.{name}.models -- an unlisted id resolves silently to the main model")

    # 4. no key-shaped string. Match, never echo.
    leaked = [i for i, s in enumerate(KEY_SHAPES) if re.search(s, text)]
    if leaked:
        r.failure("something shaped like a live API key is in this file -- rotate it, then move it to .env")
    else:
        r.ok("no key-shaped string in the file")


def check_drift(golden: dict, cfg: dict, r: Report, partial: bool, strict: bool) -> None:
    drift = r.failure if (strict or not partial) else r.warning
    differing = 0
    compared = 0
    unset_paths = []

    def absent(path):
        # Absent in a partial file means "inherits"; absent in a full file is drift.
        nonlocal differing
        if partial:
            unset_paths.append(path)
        else:
            differing += 1
            drift(f"missing: {path}")

    def compare(path, want, have):
        nonlocal differing, compared
        compared += 1
        if want != have:
            differing += 1
            drift(f"differs: {path}\n          repo      {want!r}\n          installed {have!r}")

    for path in SCALAR_PATHS:
        fg, want = get(golden, *path)
        if not fg:
            continue
        fi, have = get(cfg, *path)
        dotted = ".".join(path)
        if not fi:
            absent(dotted)
        else:
            compare(dotted, pair(want), pair(have))

    fg, want = get(golden, "fallback_providers")
    if fg:
        fi, have = get(cfg, "fallback_providers")
        if not fi:
            absent("fallback_providers")
        else:
            compare("fallback_providers (order matters)",
                    [link(e) for e in want or []], [link(e) for e in have or []])

    fg, want = get(golden, "moa", "reference_models")
    if fg:
        fi, have = get(cfg, "moa", "reference_models")
        if not fi:
            absent("moa.reference_models")
        else:
            compare("moa.reference_models", [link(e) for e in want or []], [link(e) for e in have or []])

    # The schema is written in two shapes (flat and moa.presets.<default>); the installed
    # Hermes may read either, so a drift in the one the repo does not use still matters.
    fg, preset = get(golden, "moa", "default_preset")
    if fg and isinstance(preset, str):
        base = ("moa", "presets", preset)
        fg, want = get(golden, *base, "reference_models")
        if fg:
            fi, have = get(cfg, *base, "reference_models")
            if not fi:
                absent(".".join(base) + ".reference_models")
            else:
                compare(".".join(base) + ".reference_models",
                        [link(e) for e in want or []], [link(e) for e in have or []])
        fg, want = get(golden, *base, "aggregator")
        if fg:
            fi, have = get(cfg, *base, "aggregator")
            if not fi:
                absent(".".join(base) + ".aggregator")
            else:
                compare(".".join(base) + ".aggregator", pair(want), pair(have))

    for slot, gv in (golden.get("auxiliary") or {}).items():
        fi, have = get(cfg, "auxiliary", slot)
        if not fi:
            absent(f"auxiliary.{slot}")
            continue
        want_pair = (gv.get("provider"), gv.get("model")) if isinstance(gv, dict) else gv
        have_pair = (have.get("provider"), have.get("model")) if isinstance(have, dict) else have
        compare(f"auxiliary.{slot}", want_pair, have_pair)

    for name, gb in (golden.get("providers") or {}).items():
        fi, hb = get(cfg, "providers", name)
        if not fi:
            absent(f"providers.{name}")
            continue
        hb = hb or {}
        compare(f"providers.{name}.api", gb.get("api"), hb.get("api"))
        compare(f"providers.{name}.default_model", gb.get("default_model"), hb.get("default_model"))
        compare(f"providers.{name}.models", sorted(model_ids(gb)), sorted(model_ids(hb)))

    fg, want = get(golden, "excluded_providers")
    if fg:
        fi, have = get(cfg, "excluded_providers")
        if not fi:
            absent("excluded_providers")
        else:
            compare("excluded_providers", sorted(want or []), sorted(have or []))

    if not partial:
        # Not routing, but a root config without these is a root that will be migrated
        # again and a gateway that stops serving the other profiles.
        for key in (("gateway", "multiplex_profiles"), ("_config_version",)):
            fg, want = get(golden, *key)
            if fg:
                fi, have = get(cfg, *key)
                if not fi:
                    r.warning(f"missing: {'.'.join(key)} (the repo copy carries it; a re-apply would restore it)")
                elif have != want:
                    r.warning(f"differs: {'.'.join(key)} repo {want!r} installed {have!r}")

    if unset_paths:
        shown = ", ".join(unset_paths[:5]) + (f", +{len(unset_paths) - 5} more" if len(unset_paths) > 5 else "")
        r.info(f"not set here ({len(unset_paths)}, inherited from root): {shown}")

    if differing == 0:
        if compared:
            r.ok(f"{compared} routing key(s) compared, none differ")
        else:
            r.info("no routing key is set in this file; it inherits everything, so there is nothing to compare")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--golden", required=True, help="the repo copy: configs/hermes/config.yaml")
    ap.add_argument("--installed", required=True, help="the file Hermes reads")
    ap.add_argument("--label", default="config", help="name shown in the output")
    ap.add_argument("--profile", action="store_true",
                    help="installed file is a profile's config: absent keys are 'not set', not drift")
    ap.add_argument("--strict", action="store_true",
                    help="with --profile, drift is a failure instead of a warning")
    a = ap.parse_args(argv)

    try:
        _, golden = load(a.golden)
        text, cfg = load(a.installed)
    except Unreadable as exc:
        print(f"  FAIL  {exc}")
        return UNREADABLE

    r = Report(a.label)
    print(f"{a.label}: {a.installed}")
    check_invariants(text, cfg, r, partial=a.profile)
    check_drift(golden, cfg, r, partial=a.profile, strict=a.strict)

    if r.fail:
        print(f"  => {a.label}: {r.fail} failure(s), {r.warn} warning(s)")
        return FAIL
    print(f"  => {a.label}: clean, {r.warn} warning(s)")
    return OK


if __name__ == "__main__":
    sys.exit(main())
