#!/usr/bin/env python3
"""
MoA Configuration Audit for Seven6-MoA
Asserts:
- Exactly 7 moa.reference_models entries
- Every advisor has reasoning_effort: max
- Aggregator is nvidia/nemotron-3.5-super-vl-120b-a12b
- DeepSeek-V2 provider entry exists
- Preset default mirrors reference_models
"""

import sys
from pathlib import Path

import yaml

CONFIG_PATH = Path(
    r"C:\Users\nicholasjmcleod\AppData\Local\hermes\profiles\seven6moa\config.yaml"
)

FAILURES = []


def check(condition: bool, msg: str):
    status = "PASS" if condition else "FAIL"
    print(f"[{status}] {msg}")
    if not condition:
        FAILURES.append(msg)


def main():
    with open(CONFIG_PATH, "r") as f:
        data = yaml.safe_load(f)

    moa = data.get("moa", {})
    refs = moa.get("reference_models", [])
    aggregator = moa.get("aggregator", {})
    preset = moa.get("presets", {}).get("default", {})
    preset_refs = preset.get("reference_models", [])

    check(len(refs) == 7, f"Exactly 7 reference_models (got {len(refs)})")

    for i, ref in enumerate(refs, 1):
        check(
            ref.get("enabled") is True,
            f"R{i}: {ref.get('model')} enabled=true",
        )
        check(
            ref.get("reasoning_effort") == "max",
            f"R{i}: {ref.get('model')} reasoning_effort=max",
        )

    check(
        aggregator.get("model") == "nvidia/nemotron-3.5-super-vl-120b-a12b",
        f"Aggregator is nemotron-3.5-super-vl-120b-a12b (got {aggregator.get('model')})",
    )

    check(
        any(r.get("model") == "deepseek-v2:236b-chat-q8_0" for r in refs),
        "DeepSeek-V2 Q8 present in moa.reference_models",
    )

    check(
        any(r.get("model") == "deepseek-v2:236b-chat-q8_0" for r in preset_refs),
        "DeepSeek-V2 Q8 present in presets.default.reference_models",
    )

    # Verify preset mirrors reference_models count
    check(
        len(preset_refs) == len(refs),
        f"preset.default.reference_models count matches ({len(preset_refs)} vs {len(refs)})",
    )

    print()
    if FAILURES:
        print(f"AUDIT FAILED: {len(FAILURES)} check(s) failed")
        for f in FAILURES:
            print(f"  - {f}")
        sys.exit(1)
    else:
        print("AUDIT PASSED: All checks green")


if __name__ == "__main__":
    main()
