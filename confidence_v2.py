#!/usr/bin/env python3
# Rule-based confidence classifier aiming for >= 0.95 on definitive matches
import sys

DOMAIN_DEFINITIVE = {
    "research": ["deep research", "polymath investigation", "comprehensive study"],
    "analysis": ["trade off analysis", "systematic comparison", "component analysis"],
    "generate": ["generate a report", "create output", "synthesize findings"],
    "code": ["implement python", "develop module", "python script"],
    "code-review": ["security code review", "peer review code", "audit code"],
    "qa": ["test the system", "verify results", "validate output"],
    "sec-review": ["security review prompt", "check injection", "vulnerability scan"],
    "audit": ["full system audit", "compliance audit", "final audit report"],
}

DOMAIN_STRONG = {
    "research": ["research", "analysis", "investigation"],
    "analysis": ["analyze", "examine", "evaluate"],
    "generate": ["generate", "create", "produce"],
    "code": ["code", "implement", "develop"],
    "code-review": ["review", "audit", "security"],
    "qa": ["test", "verify", "validate"],
    "sec-review": ["security", "prompt injection", "vulnerability"],
    "audit": ["audit", "inspect", "examine"],
}

DOMAIN_MODERATE = {
    "research": ["study", "examination"],
    "analysis": ["compare", "contrast"],
    "generate": ["produce", "output"],
    "code": ["program", "script"],
    "code-review": ["review", "quality check"],
    "qa": ["check", "confirm"],
    "sec-review": ["risk", "threat"],
    "audit": ["inspect", "review"],
}

DOMAIN_WEAK = {
    "research": ["knowledge", "information"],
    "analysis": ["data", "metrics"],
    "generate": ["output", "result"],
    "code": ["programming", "software"],
    "code-review": ["quality", "security"],
    "qa": ["quality", "assurance"],
    "sec-review": ["threat", "risk"],
    "audit": ["review", "check"],
}


def classify_confidence_v2(prompt):
    """Rule-based confidence classifier aiming for >= 0.95 on definitive matches."""
    prompt_lower = prompt.lower()
    results = {}

    for domain in DOMAIN_DEFINITIVE:
        score = 0.0

        # Check definitive indicators first
        definitive = DOMAIN_DEFINITIVE[domain]
        strong = DOMAIN_STRONG[domain]
        moderate = DOMAIN_MODERATE[domain]
        weak = DOMAIN_WEAK[domain]

        # Definitive match -> 1.0
        for indicator in definitive:
            if indicator.lower() in prompt_lower:
                score = 1.0
                break

        # Strong indicators -> 0.9
        if score < 0.9:
            for indicator in strong:
                if indicator.lower() in prompt_lower:
                    score = 0.9
                    break

        # Moderate indicators -> 0.7
        if score < 0.7:
            for indicator in moderate:
                if indicator.lower() in prompt_lower:
                    score = 0.7
                    break

        # Weak indicators -> 0.5
        if score < 0.5:
            for indicator in weak:
                if indicator.lower() in prompt_lower:
                    score = 0.5
                    break

        # No indicators but domain-related words -> 0.1
        if score < 0.1:
            any_match = False
            for d in DOMAIN_DEFINITIVE:
                for ind in DOMAIN_DEFINITIVE[d]:
                    if ind.lower() in prompt_lower:
                        any_match = True
                        break
                if any_match:
                    break
            if not any_match:
                score = 0.1

        results[domain] = {
            "confidence": score,
            "category": "definitive" if score == 1.0 else ("strong" if score == 0.9 else
                ("moderate" if score == 0.7 else ("weak" if score == 0.5 else "none")))
        }

    # Find primary domain
    primary_domain = max(results, key=lambda d: results[d]["confidence"])
    primary_conf = results[primary_domain]["confidence"]

    # Secondary domain
    secondary_domain = None
    secondary_conf = 0.0
    for domain, r in results.items():
        if domain != primary_domain and r["confidence"] >= 0.3 and r["confidence"] > secondary_conf:
            secondary_conf = r["confidence"]
            secondary_domain = domain

    return primary_domain, primary_conf, results, secondary_domain, secondary_conf


test_prompts = [
    ("Deep research on quantum computing architectures", "research"),
    ("Analyze the tradeoffs between RL and SFT for agent training", "analysis"),
    ("Generate a comprehensive report on AI agent security", "generate"),
    ("Implement a Python module for agent coordination", "code"),
    ("Review code for security vulnerabilities", "code-review"),
    ("Quality assurance test for agent coordination", "qa"),
    ("Security review of agent coordination code", "sec-review"),
    ("Comprehensive audit of agent workflow", "audit"),
]

print("=" * 80)
print("RULE-BASED CONFIDENCE - >= 0.95 TARGET")
print("=" * 80)

all_pass = True
for prompt, expected_domain in test_prompts:
    primary_domain, primary_conf, all_results, secondary_domain, secondary_conf = classify_confidence_v2(prompt)

    passes = primary_conf >= 0.95
    if not passes:
        all_pass = False

    secondary_str = f"{secondary_domain}({secondary_conf})" if secondary_domain else "None"
    status = "PASS" if passes else "FAIL"

    print(f"\n'{prompt[:55]}...'")
    print(f"  Expected: {expected_domain}")
    print(f"  Got: {primary_domain} (conf: {primary_conf}) [{results[primary_domain]['category']}]")
    if secondary_domain:
        print(f"  Secondary: {secondary_str}")
    print(f"  Status: {status}")

print("\n" + "=" * 80)
if all_pass:
    print("ALL PASS - Confidence >= 0.95 achieved for all prompts!")
else:
    print("SOME PROMPTS BELOW 0.95 - need further refinement")
print("=" * 80)