#!/usr/bin/env python3
"""Domain Classifier for Seven6-Hermes-MOA.

Classifies user prompts into 8 domains to enable skill selection
and model orchestration. Supports keyword-based classification with
intensifier boosts, secondary domain detection, and action routing.
"""

from __future__ import annotations

import re
from typing import Dict, List, Optional, Tuple

# 8 domains with their keyword patterns
DOMAIN_PATTERNS = {
    "research": {
        "primary": [
            r"\bresearch\b",
            r"\bcomprehensive.?analysis\b",
            r"\bdeep.?investigation\b",
            r"\bpolymath\b",
            r"\bcritical.?thinking\b",
            r"\bliterature.?review\b",
            r"\bdomain.?analysis\b",
        ],
        "intensifiers": [
            r"\bdeep\b",
            r"\bthorough\b",
            r"\bcomprehensive\b",
        ],
        "weight": 1.0,
    },
    "analysis": {
        "primary": [
            r"\banalysis\b",
            r"\btrade.?off\b",
            r"\bcomparison\b",
            r"\bcomponent.?analysis\b",
            r"\bsystematic\b",
            r"\bmulti.?perspective\b",
            r"\bperspective.?analysis\b",
        ],
        "intensifiers": [
            r"\bdeep\b",
            r"\bcritical\b",
        ],
        "weight": 1.0,
    },
    "generate": {
        "primary": [
            r"\bgenerate\b",
            r"\bcreate\b",
            r"\bsynthesize\b",
            r"\sproduce\b",
            r"\soutput\b",
            r"\sformulate\b",
            r"\sdesign\b",
        ],
        "intensifiers": [
            r"\bcomplete\b",
            r"\bfull.?output\b",
        ],
        "weight": 1.0,
    },
    "code": {
        "primary": [
            r"\bcode\b",
            r"\bimplement\b",
            r"\bdevelop\b",
            r"\bprogram\b",
            r"\bscript\b",
            r"\bfunction\b",
            r"\bclass\b",
            r"\bpython\b",
            r"\bjavascript\b",
        ],
        "intensifiers": [
            r"\bfunction.?implementation\b",
            r"\bmodule.?development\b",
        ],
        "weight": 1.0,
    },
    "code-review": {
        "primary": [
            r"\bcode.?review\b",
            r"\breview.?code\b",
            r"\bpeer.?review\b",
            r"\bsecurity.?review\b",
            r"\baudit\b",
            r"\bquality.?check\b",
        ],
        "intensifiers": [
            r"\bsecurity.?audit\b",
            r"\bvulnerability\b",
        ],
        "weight": 1.0,
    },
    "qa": {
        "primary": [
            r"\bqa\b",
            r"\bquality.?assurance\b",
            r"\btest\b",
            r"\bvalidation\b",
            r"\bverification\b",
            r"\bcheck\b",
            r"\bconfirm\b",
        ],
        "intensifiers": [
            r"\bthorough.?testing\b",
            r"\bfull.?test\b",
        ],
        "weight": 1.0,
    },
    "sec-review": {
        "primary": [
            r"\bsecurity.?review\b",
            r"\bsec.?review\b",
            r"\bprompt.?injection\b",
            r"\bvulnerability\b",
            r"\bthreat.?modeling\b",
            r"\bcompliance\b",
            r"\brisk.?assessment\b",
        ],
        "intensifiers": [
            r"\bcritical.?security\b",
            r"\bhigh.?risk\b",
        ],
        "weight": 1.2,  # Higher weight for security-sensitive prompts
    },
    "audit": {
        "primary": [
            r"\baudit\b",
            r"\bcomprehensive.?audit\b",
            r"\bfull.?audit\b",
            r"\bsystem.?audit\b",
            r"\mrc accountability\b",
            r"\bcompliance.?audit\b",
        ],
        "intensifiers": [
            r"\bcompliance\b",
            r"\mrc governance\b",
        ],
        "weight": 1.0,
    },
}


class DomainClassifier:
    """Classifies prompts into domains with confidence scoring."""

    def __init__(self, patterns: Optional[Dict] = None):
        self.patterns = patterns or DOMAIN_PATTERNS
        self.domain_scores: Dict[str, float] = {}
        self.secondary_domains: List[Tuple[str, float]] = []

    def classify(self, prompt: str) -> Dict[str, any]:
        """Classify a prompt into domains with scores and secondary suggestions.

        Returns dict with:
        - primary_domain: str (highest confidence domain)
        - confidence: float (0.0 to 1.0)
        - secondary_domains: List[Tuple[str, float]] (top 2, optional)
        - all_domains: Dict[str, float] (all domain scores)
        - action: str (suggested action based on domain)
        - domain_data: Dict with domain-specific metadata
        """
        self.domain_scores = {}
        self.secondary_domains = []

        prompt_lower = prompt.lower()

        # Score each domain
        for domain, config in self.patterns.items():
            score = 0.0

            # Primary keyword matches
            for pattern in config["primary"]:
                if re.search(pattern, prompt_lower):
                    score += 1.0

            # Intensifier boosts (+1 each)
            for pattern in config["intensifiers"]:
                if re.search(pattern, prompt_lower):
                    score += 1.0

            # Normalize by number of primary patterns
            normalized = score / max(len(config["primary"]), 1)
            self.domain_scores[domain] = min(normalized, 1.0)

        # Find primary domain (highest score)
        if self.domain_scores:
            primary_domain = max(self.domain_scores, key=self.domain_scores.get)
            confidence = self.domain_scores[primary_domain]
        else:
            primary_domain = "generate"  # fallback
            confidence = 0.3

        # Find secondary domains (top 2 after primary)
        sorted_domains = sorted(
            self.domain_scores.items(), key=lambda x: x[1], reverse=True
        )

        # Remove primary and get next top 2
        secondary_candidates = [
            (d, s) for d, s in sorted_domains if d != primary_domain
        ]
        self.secondary_domains = secondary_candidates[:2]

        # Determine action based on domain
        action = self._determine_action(primary_domain, confidence)

        # Domain-specific metadata
        domain_data = self._get_domain_metadata(primary_domain, confidence)

        return {
            "primary_domain": primary_domain,
            "confidence": round(confidence, 3),
            "secondary_domains": [
                (d, round(s, 3)) for d, s in self.secondary_domains
            ],
            "all_domains": {
                d: round(s, 3) for d, s in self.domain_scores.items()
            },
            "action": action,
            "domain_data": domain_data,
        }

    def _determine_action(self, domain: str, confidence: float) -> str:
        """Determine suggested action based on domain and confidence."""
        if confidence < 0.2:
            return "generic-handling"

        actions = {
            "research": "retrieve-and-synthesize",
            "analysis": "decompose-and-evaluate",
            "generate": "create-and-output",
            "code": "implement-and-test",
            "code-review": "review-and-feedback",
            "qa": "test-and-validate",
            "sec-review": "scan-and-assess",
            "audit": "comprehensive-review",
        }

        return actions.get(domain, "process-per-domain")

    def _get_domain_metadata(self, domain: str, confidence: float) -> Dict[str, any]:
        """Get domain-specific metadata for skill selection."""
        return {
            "domain": domain,
            "confidence": confidence,
            "complexity": (
                "high"
                if confidence > 0.7
                else ("medium" if confidence > 0.4 else "low")
            ),
            "skill_priority": self._get_skill_priority(domain),
            "estimated_cost_factor": self._get_cost_factor(domain),
        }

    def _get_skill_priority(self, domain: str) -> List[str]:
        """Get recommended skill categories for this domain."""
        priorities = {
            "research": ["research", "deep-research", "knowledge-retrieval"],
            "analysis": ["analysis", "code-review", "security-review"],
            "generate": ["code", "six-perspectives", "memory-pipeline"],
            "code": ["code-review", "codex-hermes-bridge", "software-development"],
            "code-review": ["code-review", "enhanced-mem9", "security-review"],
            "qa": ["qa", "security-review", "enhanced-mem9"],
            "sec-review": ["security-review", "securuty-audit", "seven6-security"],
            "audit": ["security-review", "verification-loop", "code-review"],
        }
        return priorities.get(domain, ["skill-generation"])

    def classify_with_skills(
        self, prompt: str, all_skills: Optional[List[Dict]] = None
    ) -> Dict[str, any]:
        """Classify prompt and recommend skills based on domain.

        Returns classification result plus skill recommendations.
        """
        result = self.classify(prompt)

        # Domain-based skill recommendations
        domain = result["primary_domain"]
        skill_weights = {
            "research": {"deep-research": 1.0, "knowledge-retrieval": 0.8, "memory-pipeline": 0.6},
            "analysis": {"analysis": 1.0, "code-review": 0.8, "security-review": 0.7},
            "generate": {"code": 0.9, "six-perspectives": 0.7, "memory-pipeline": 0.5},
            "code": {"code-review": 1.0, "codex-hermes-bridge": 0.8, "software-development": 0.9},
            "code-review": {"code-review": 1.0, "enhanced-mem9": 0.7, "security-review": 0.6},
            "qa": {"qa": 1.0, "security-review": 0.6, "enhanced-mem9": 0.7},
            "sec-review": {"security-review": 1.0, "seven6-security": 0.9, "enhanced-mem9": 0.6},
            "audit": {"security-review": 0.9, "verification-loop": 0.8, "code-review": 0.7},
        }

        recommended_skills = skill_weights.get(domain, {})

        result["recommended_skills"] = recommended_skills
        result["skill_count"] = len(recommended_skills)

        return result


# Convenience function for quick classification
def classify_prompt(prompt: str, all_skills: Optional[List[Dict]] = None) -> Dict[str, any]:
    """Quick prompt classification."""
    classifier = DomainClassifier()
    return classifier.classify_with_skills(prompt, all_skills)


if __name__ == "__main__":
    # Quick test suite
    test_prompts = [
        "Deep research on quantum computing architectures",
        "Analyze the tradeoffs between RL and SFT for agent training",
        "Generate a comprehensive report on AI agent security",
        "Implement a Python module for agent coordination",
        "Review code for security vulnerabilities",
        "Quality assurance test for agent coordination",
        "Security review of agent coordination code",
        "Comprehensive audit of agent workflow",
    ]

    print("=== Domain Classifier Quick Tests ===\n")
    for prompt in test_prompts:
        result = classify_prompt(prompt)
        primary = result["primary_domain"]
        confidence = result["confidence"]
        secondary = result["secondary_domains"]
        action = result["action"]
        print(f"'{prompt[:50]}...'")
        print(f"  → Primary: {primary} (conf: {confidence})")
        if secondary:
            print(f"  → Secondary: {secondary[0][0]} (conf: {secondary[0][1]})")
        print(f"  → Action: {action}")
        if "recommended_skills" in result:
            print(f"  → Recommended skills: {list(result['recommended_skills'].keys())}")
        print()

    print("=== All tests complete ===")
