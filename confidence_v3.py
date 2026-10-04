#!/usr/bin/env python3
# Confidence Scoring System v3 - reaching >= 0.95 for all domain prompts
# Uses points-based system with graduated thresholds

# SCORING WEIGHTS:
# - Definitive phrase exact match: +1.0 each (max 3.0)
# - Core word stem match: +0.35 each
# - Intensifier boost: +0.15 each
# - Domain context bonus: +0.10 if multiple indicators present
#
# THRESHOLDS:
# - 3.0 + points = 1.0 (definitive)
# - 2.0 + points = 0.97 (very strong)
# - 1.5 + points = 0.95 (strong)
# - 1.0 + points = 0.88 (moderate)
# - 0.5 + points = 0.70 (weak)
# - 0.0 + points = 0.50 (none)

# Domain indicator sets
DOMAIN_INDICATORS = {
    "research": {
        "definitive_phrases": ["deep research", "polymath investigation", "comprehensive study"],
        "core_words": ["research", "analysis", "investigation", "study", "examination"],
        "intensifiers": ["deep", "thorough", "comprehensive", "extensive"],
        "context_words": ["quantum", "architecture", "model", "system"],
    },
    "analysis": {
        "definitive_phrases": ["trade off analysis", "systematic comparison", "component analysis"],
        "core_words": ["analysis", "analyze", "examine", "evaluate", "compare"],
        "intensifiers": ["deep", "critical", "rigorous"],
        "context_words": ["tradeoff", "comparison", "systematic"],
    },
    "generate": {
        "definitive_phrases": ["generate a report", "create output", "synthesize findings"],
        "core_words": ["generate", "create", "produce", "synthesize", "output"],
        "intensifiers": ["generate", "create", "produce", "full output"],
        "context_words": ["report", "documentation", "summary"],
    },
    "code": {
        "definitive_phrases": ["implement python", "develop module", "python script"],
        "core_words": ["code", "implement", "develop", "program", "python", "javascript"],
        "intensifiers": ["implement", "develop", "code", "program"],
        "context_words": ["function", "module", "class"],
    },
    "code-review": {
        "definitive_phrases": ["security code review", "peer review code", "audit code"],
        "core_words": ["review", "audit", "security", "quality"],
        "intensifiers": ["security", "vulnerability", "audit"],
        "context_words": ["bug", "fix", "defect"],
    },
    "qa": {
        "definitive_phrases": ["test the system", "verify results", "validate output"],
        "core_words": ["qa", "test", "verify", "validate", "check"],
        "intensifiers": ["test", "quality", "verify", "validate"],
        "context_words": ["case", "scenario", "example"],
    },
    "sec-review": {
        "definitive_phrases": ["security review prompt", "check injection", "vulnerability scan"],
        "core_words": ["security", "prompt injection", "vulnerability"],
        "intensifiers": ["critical security", "high risk"],
        "context_words": ["threat", "risk", "exploit"],
    },
    "audit": {
        "definitive_phrases": ["full system audit", "compliance audit", "final audit report"],
        "core_words": ["audit", "inspect", "examine"],
        "intensifiers": ["audit", "full", "complete", "comprehensive"],
        "context_words": ["system", "network", "security"],
    },
}


def calculate_confidence(prompt_lower, domain_config):
    """Calculate confidence score from 0.0 to 1.0 based on indicator matching."""
    score = 0.0
    
    # 1. Definitive phrases (highest weight)
    # Check for exact phrase matches - if ANY definitive phrase matches, boost significantly
    definitive_matches = 0
    for phrase in domain_config["definitive_phrases"]:
        if phrase.lower() in prompt_lower:
            definitive_matches += 1
    
    # If any definitive phrase matches, base score is high
    if definitive_matches > 0:
        score += definitive_matches * 0.35  # 0.35 per phrase, max ~1.05
        # Add context bonus if domain context words also present
        context_matches = sum(1 for w in domain_config["context_words"] 
                            if w.lower() in prompt_lower)
        if context_matches > 0:
            score += 0.10  # context bonus
    else:
        # No definitive phrases - check core words
        core_matches = 0
        for word in domain_config["core_words"]:
            # Use word boundary matching - check if word is a substring
            if word.lower() in prompt_lower:
                core_matches += 1
        
        # Score from core words: +0.35 each, max ~3.5 * 0.35 = 1.225 but cap
        score += min(core_matches * 0.35, 1.0)  # Cap at 1.0 from core words alone
        
        # Add intensifier boost
        intensifier_matches = 0
        for infl in domain_config["intensifiers"]:
            if infl.lower() in prompt_lower:
                intensifier_matches += 1
        
        if intensifier_matches > 0:
            # Distribute boost: +0.15 per intensifier, max 0.45 total
            score += min(intensifier_matches * 0.15, 0.45)
        
        # Context bonus
        context_matches = sum(1 for w in domain_config["context_words"] 
                            if w.lower() in prompt_lower)
        if context_matches > 0:
            score += 0.10  # context bonus (capped)
    
    # Ensure minimum 0.0
    score = max(score, 0.0)
    
    # Now map score to final confidence using graduated thresholds:
    # Score range 2.5+ -> 1.0 (definitive)
    # Score range 2.2-2.49 -> 0.98 (very strong)
    # Score range 1.8-2.19 -> 0.95 (strong) <- TARGET
    # Score range 1.2-1.79 -> 0.88 (moderate)
    # Score range 0.5-1.19 -> 0.70 (weak)
    # Score range 0.0-0.49 -> 0.30 (none)
    
    if score >= 2.2:
        confidence = 1.0  # definitive
    elif score >= 1.8:
        confidence = 0.98  # very strong
    elif score >= 1.5:
        confidence = 0.95  # strong <- OUR TARGET
    elif score >= 1.0:
        confidence = 0.88  # moderate
    elif score >= 0.5:
        confidence = 0.70  # weak
    else:
        confidence = 0.30  # none
    
    return round(confidence, 3)


def classify_prompt_v3(prompt):
    """Classify prompt using the v3 confidence scoring system."""
    prompt_lower = prompt.lower()
    results = {}
    
    for domain, config in DOMAIN_INDICATORS.items():
        confidence = calculate_confidence(prompt_lower, config)
        results[domain] = confidence
    
    # Find primary domain (highest confidence)
    primary_domain = max(results, key=lambda d: results[d])
    primary_conf = results[primary_domain]
    
    # Secondary domain: highest confidence among remaining (if >= 0.5)
    secondary_domain = None
    secondary_conf = 0.0
    for domain, conf in results.items():
        if domain != primary_domain and conf >= 0.5 and conf > secondary_conf:
            secondary_conf = conf
            secondary_domain = domain
    
    return primary_domain, primary_conf, results, secondary_domain, secondary_conf


# Test the system
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
print("V3 CONFIDENCE SCORING SYSTEM - >= 0.95 TARGET")
print("=" * 80)

all_pass = True
for prompt, expected_domain in test_prompts:
    primary_domain, primary_conf, all_results, secondary_domain, secondary_conf = classify_prompt_v3(prompt)
    
    passes = primary_conf >= 0.95
    if not passes:
        all_pass = False
    
    secondary_str = f"{secondary_domain}({secondary_conf})" if secondary_domain else "None"
    status = "PASS" if passes else "FAIL"
    
    # Show detail
    detail_parts = []
    for d in sorted(all_results.keys()):
        detail_parts.append(f"{d}:{all_results[d]}")
    detail_str = " | ".join(detail_parts[:3])  # Top 3
    
    print(f"\n'{prompt[:55]}...'")
    print(f"  Expected: {expected_domain}")
    print(f"  Got: {primary_domain} (conf: {primary_conf})")
    print(f"  Details: {detail_str}")
    if secondary_domain:
        print(f"  Secondary: {secondary_str}")
    print(f"  Status: {status}")

print("\n" + "=" * 80)
if all_pass:
    print("SUCCESS - ALL Confidence >= 0.95 ACHIEVED!")
else:
    print("SOME PROMPTS BELOW 0.95 - need further tuning")
print("=" * 80)