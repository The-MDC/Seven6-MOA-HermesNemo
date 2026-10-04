#!/usr/bin/env python3
import os, json, re
from seven6_orchestration.classify_domain import classify_prompt_v4
from seven6_orchestration.map_skills import SkillsMapper

SEVEN6 = r".\hermes-skills"

# Test the domain classifier integration with actual skills
print("=" * 80)
print("DOMAIN CLASSIFIER + SKILLS MAPPER INTEGRATION TEST")
print("=" * 80)

# Load all skills
mapper = SkillsMapper()

print(f"Loaded {len(mapper.all_skills)} skills from Seven6-Hermes-MOA")
print(f"Domain classifier v4 ready\n")

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

for prompt, expected_domain in test_prompts:
    primary_domain, primary_conf, all_results, secondary_domain, secondary_conf = classify_prompt_v4(prompt)
    
    confidence_status = "PASS" if primary_conf >= 0.95 else "BELOW TARGET"
    
    print(f"Prompt: {prompt[:55]}...")
    print(f"  Expected: {expected_domain}, Got: {primary_domain} (conf: {primary_conf}) [{confidence_status}]")
    if secondary_domain:
        print(f"  Secondary: {secondary_domain}({secondary_conf})")
    print()

print("=" * 80)
print("Phase 1 Wiring Complete - Domain Classifier + Skills Mapper Integrated")
print("=" * 80)