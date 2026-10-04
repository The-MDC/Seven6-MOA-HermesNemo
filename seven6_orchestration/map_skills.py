#!/usr/bin/env python3
"""Skills Mapper for Seven6-Hermes-MOA.

Maps model capabilities to relevant skills using composite scoring:
- Base score (40%)
- seven6-port compliance (25%)
- Related skill overlap (20%)
- Budget constraints (10%)
- Entry conditions (5%)

Provides custom profile generation per model per domain with skill filtering.
"""

from __future__ import annotations

import json
import os
from typing import Dict, List, Optional, Set


class SkillsMapper:
    """Maps skills to models/domains using composite scoring.

    The composite score formula:
        composite = (base_score × 0.4) +
                    (seven6_port × 0.25) +
                    (related_overlap × 0.20) +
                    (budget_mod × 0.10) +
                    (entry_condition × 0.05)
    """

    def __init__(self, all_skills: Optional[List[Dict]] = None):
        """Initialize the skills mapper.

        Args:
            all_skills: List of skill dicts with frontmatter parsed.
                       If None, loader will search hermes-skills/ directory.
        """
        self.all_skills = all_skills or self._load_all_skills()
        self.skill_index: Dict[str, Dict] = {
            s["id"]: s for s in self.all_skills if "id" in s
        }
        self.domain_skill_map = self._build_domain_skill_map()

    def _load_all_skills(self) -> List[Dict]:
        """Load all skills from hermes-skills/ directory.

        Returns list of dicts with at minimum:
        - id: skill directory name
        - name: from frontmatter
        - description: from frontmatter
        - version: from frontmatter
        - author: from frontmatter
        - license: from frontmatter
        - platforms: from frontmatter
        - tags: from frontmatter
        - seven6_port: from frontmatter metadata block
        """
        skills = []
        sevendir = r"./hermes-skills"

        for skill_dir in sorted(os.listdir(sevendir)):
            skill_md = os.path.join(sevendir, skill_dir, "SKILL.md")
            if not os.path.isfile(skill_md):
                continue

            skill_data = self._parse_skill_md(skill_dir, skill_md)
            if skill_data:
                skills.append(skill_data)

        return skills

    def _parse_skill_md(self, skill_id: str, content: str) -> Optional[Dict]:
        """Parse a single SKILL.md file and extract metadata fields."""
        result = {"id": skill_id}

        # Extract YAML frontmatter
        if content.startswith("---\n"):
            fm_end = content.find("\n---", 3)
            if fm_end < 0:
                return None
            fm_text = content[3:fm_end]
        else:
            return None

        # Extract fields from frontmatter
        import re

        name_match = re.search(r'name:\s*"([^"]*)"', fm_text)
        result["name"] = name_match.group(1) if name_match else skill_id

        desc_match = re.search(r'description:\s*"([^"]*)"', fm_text)
        result["description"] = desc_match.group(1) if desc_match else ""

        ver_match = re.search(r'version:\s*"?([^"\n,]+)', fm_text)
        result["version"] = ver_match.group(1) if ver_match else "0.1.0"

        auth_match = re.search(r'author:\s*"([^"]*)"', fm_text)
        result["author"] = auth_match.group(1) if auth_match else "unknown"

        lic_match = re.search(r'license:\s*"([^"]*)"', fm_text)
        result["license"] = lic_match.group(1) if lic_match else "MIT"

        plat_match = re.search(r'platforms:\s*\[([^\]]+)\]', fm_text)
        result["platforms"] = (
            [p.strip().strip('"') for p in plat_match.group(1).split(",")]
            if plat_match
            else ["local"]
        )

        tags_match = re.search(r'tags:\s*\[([^\]]+)\]', fm_text)
        result["tags"] = (
            [t.strip().strip('"') for t in tags_match.group(1).split(",")]
            if tags_match
            else []
        )

        result["seven6_port"] = "seven6-port" in fm_text

        # Check for hermes: block after frontmatter
        body_marker = content.find("\n---\n", fm_end + 3)
        result["hermes_in_body"] = body_marker >= 0 and "hermes:" in content[body_marker:]

        return result

    def _build_domain_skill_map(self) -> Dict[str, List[str]]:
        """Build mapping from domain to skill IDs based on tags."""
        domain_map: Dict[str, List[str]] = {}

        # Domain → tag mappings (from conventions skill)
        domain_tags = {
            "research": ["deep-research", "knowledge-retrieval", "memory-pipeline"],
            "analysis": ["analysis", "code-review", "security-review"],
            "generate": ["code", "six-perspectives", "memory-pipeline"],
            "code": ["code-review", "codex-hermes-bridge", "software-development"],
            "code-review": ["code-review", "enhanced-mem9", "security-review"],
            "qa": ["qa", "security-review", "enhanced-mem9"],
            "sec-review": ["security-review", "seven6-security", "enhanced-mem9"],
            "audit": ["security-review", "verification-loop", "code-review"],
        }

        for domain, tags in domain_tags.items():
            matching_skills = []
            for skill in self.all_skills:
                skill_tags = skill.get("tags", [])
                # Match if any domain tag is in skill's tags
                if any(tag in skill_tags for tag in tags):
                    matching_skills.append(skill["id"])
            domain_map[domain] = matching_skills

        return domain_map

    def compute_composite_score(
        self,
        skill_id: str,
        model_class: str = "general",
        domain: str = "general",
        budget_limit: Optional[float] = None,
        required_entries: Optional[Set[str]] = None,
    ) -> Dict[str, any]:
        """Compute composite score for a skill.

        Scoring breakdown:
            - base_score: 40% (inherent skill quality)
            - seven6_port: 25% (metadata compliance)
            - related_overlap: 20% (domain relevance)
            - budget_mod: 10% (cost within budget_limit)
            - entry_condition: 5% (prerequisites met)

        Returns dict with:
        - skill_id: str
        - composite: float (0.0 to 1.0)
        - breakdown: Dict[str, float] (per-component scores)
        - seven6_port: bool
        - domain_relevance: float
        - entry_met: bool
        - ranking: int (1 = best)
        - recommendations: List[str]
        """
        skill = self.skill_index.get(skill_id)
        if skill is None:
            return {
                "skill_id": skill_id,
                "composite": 0.0,
                "breakdown": {
                    "base_score": 0.0,
                    "seven6_port": 0.0,
                    "related_overlap": 0.0,
                    "budget_mod": 0.0,
                    "entry_condition": 0.0,
                },
                "seven6_port": False,
                "domain_relevance": 0.0,
                "entry_met": False,
                "ranking": 999,
                "recommendations": ["skill-not-found"],
            }

        # 1. Base score (0.4 weight)
        # Derived from version, author reputation, and tag presence
        base_score = self._compute_base_score(skill)

        # 2. seven6-port compliance (0.25 weight)
        seven6_port = skill.get("seven6_port", False)
        seven6_score = 1.0 if seven6_port else 0.0

        # 3. Related overlap (0.20 weight)
        # How many related skills does this skill connect to
        related_overlap = self._compute_related_overlap(skill, domain)

        # 4. Budget modification (0.10 weight)
        budget_mod = self._compute_budget_modifier(
            skill, budget_limit or 10.0
        )

        # 5. Entry condition (0.05 weight)
        entry_condition = self._compute_entry_condition(
            skill, required_entries or set()
        )

        # Composite formula
        composite = (
            base_score * 0.4
            + seven6_score * 0.25
            + related_overlap * 0.20
            + budget_mod * 0.10
            + entry_condition * 0.05
        )

        # Round to 3 decimal places
        composite = round(composite, 3)

        # Determine ranking among all skills
        all_composites = self._compute_all_composites(
            model_class, domain, budget_limit, required_entries
        )
        ranking = all_composites.index(composite) + 1 if composite in all_composites else 999

        # Generate recommendations
        recommendations = self._generate_recommendations(skill, domain)

        return {
            "skill_id": skill_id,
            "composite": composite,
            "breakdown": {
                "base_score": round(base_score, 3),
                "seven6_port": round(seven6_score, 3),
                "related_overlap": round(related_overlap, 3),
                "budget_mod": round(budget_mod, 3),
                "entry_condition": round(entry_condition, 3),
            },
            "seven6_port": seven6_port,
            "domain_relevance": round(related_overlap, 3),
            "entry_met": entry_condition > 0.5,
            "ranking": ranking,
            "recommendations": recommendations,
        }

    def _compute_base_score(self, skill: Dict) -> float:
        """Compute base score (0.0 to 1.0) from skill quality indicators."""
        score = 0.5  # Neutral start

        # Version recency: newer versions score higher
        try:
            version_parts = list(map(int, skill.get("version", "0.1.0").split(".")))
            if len(version_parts) >= 2:
                # Simple scoring: 1.x = 0.8, 2.x = 0.9, etc.
                if version_parts[0] >= 2:
                    score += 0.3
                elif version_parts[0] == 1:
                    score += 0.2
                else:
                    score += 0.1
        except (ValueError, IndexError):
            pass

        # Tag presence indicates skill is well-defined
        if skill.get("tags"):
            score += 0.2

        # Author "Seven6-Hermes-MOA conversion" is standard
        if skill.get("author") == "Seven6-Hermes-MOA conversion":
            score += 0.1

        # License MIT is standard
        if skill.get("license") == "MIT":
            score += 0.1

        # Platforms listed indicates broader compatibility
        if skill.get("platforms") and len(skill.get("platforms", [])) >= 2:
            score += 0.1

        return min(score, 1.0)

    def _compute_related_overlap(
        self, skill: Dict, domain: str
    ) -> float:
        """Compute related overlap score (0.0 to 1.0) based on domain relevance."""
        skill_tags = skill.get("tags", [])
        domain_tags = {
            "research": ["deep-research", "knowledge-retrieval", "memory-pipeline"],
            "analysis": ["analysis", "code-review", "security-review"],
            "generate": ["code", "six-perspectives", "memory-pipeline"],
            "code": ["code-review", "codex-hermes-bridge", "software-development"],
            "code-review": ["code-review", "enhanced-mem9", "security-review"],
            "qa": ["qa", "security-review", "enhanced-mem9"],
            "sec-review": ["security-review", "seven6-security", "enhanced-mem9"],
            "audit": ["security-review", "verification-loop", "code-review"],
        }

        domain_tag_set = set(domain_tags.get(domain, []))
        skill_tag_set = set(skill_tags)

        if not domain_tag_set or not skill_tag_set:
            return 0.3  # Neutral if no tags to compare

        # Jaccard-like: intersection / union
        intersection = len(domain_tag_set & skill_tag_set)
        union = len(domain_tag_set | skill_tag_set)

        if union == 0:
            return 0.3

        return round(intersection / union, 3)

    def _compute_budget_modifier(
        self, skill: Dict, budget_limit: float
    ) -> float:
        """Compute budget modifier (0.0 to 1.0) based on cost constraints.

        Higher score = better fit within budget.
        """
        # Skills with seven6-port typically have lower overhead
        if skill.get("seven6_port"):
            base_budget_score = 0.8
        else:
            base_budget_score = 0.5

        # Platform compatibility affects effective budget
        platforms = skill.get("platforms", ["local"])
        if "cloud" in platforms and "local" in platforms:
            base_budget_score *= 1.0  # Full flexibility
        elif "cloud" in platforms or "local" in platforms:
            base_budget_score *= 0.8  # Partial flexibility
        else:
            base_budget_score *= 0.5  # Limited flexibility

        # Normalize to 0-1 range relative to budget_limit
        # Assume $100 default budget; score decreases as skill cost approaches limit
        cost_factor = min(budget_limit / 100.0, 1.0)  # 100 = default budget
        final_score = base_budget_score * cost_factor

        return round(min(final_score, 1.0), 3)

    def _compute_entry_condition(
        self, skill: Dict, required_entries: Set[str]
    ) -> float:
        """Compute entry condition score (0.0 to 1.0).

        Checks if required prerequisites/entries are met.
        """
        # Check hermes:block for related_skills
        related_skills = skill.get("related_skills", [])
        if isinstance(related_skills, str):
            related_skills = [
                s.strip() for s in related_skills.split(",")
            ]

        # How many required entries are satisfied
        satisfied = 0
        total = max(len(required_entries), 1)

        for entry in required_entries:
            # Check if skill has this as a related skill
            if entry in related_skills:
                satisfied += 1
            # Check if skill tag matches
            elif entry in skill.get("tags", []):
                satisfied += 1

        score = satisfied / total if total > 0 else 1.0
        return round(score, 3)

    def _generate_recommendations(
        self, skill: Dict, domain: str
    ) -> List[str]:
        """Generate human-readable recommendations for a skill."""
        recs = []

        if skill.get("seven6_port"):
            recs.append("✅ seven6-port compliant - recommended for orchestration")
        else:
            recs.append("⚠️ Missing seven6-port - may have compatibility issues")

        if skill.get("tags"):
            recs.append(f"🏷️ {len(skill['tags'])} tags defined - good categorization")
        else:
            recs.append("⚠️ No tags defined - consider adding metadata.tags")

        if skill.get("platforms"):
            recs.append(
                f"🌐 {len(skill['platforms'])} platforms supported - good coverage"
            )
        else:
            recs.append("⚠️ No platforms defined - limited compatibility")

        if skill.get("description"):
            recs.append("📝 Description present - good for documentation")
        else:
            recs.append("⚠️ No description - add skill purpose")

        if skill.get("name") and skill.get("name") != skill["id"]:
            recs.append("✅ Name matches convention - ready for indexing")

        return recs

    def map_model_to_skills(
        self,
        model_id: str,
        model_class: str = "general",
        domain: str = "general",
        budget_limit: Optional[float] = None,
        required_entries: Optional[Set[str]] = None,
        exclude_skills: Optional[List[str]] = None,
    ) -> Dict[str, any]:
        """Map a model to its optimal skill subset.

        Returns custom skill profile for the given model/domain/budget.
        """
        # Compute composite scores for all skills
        all_scores = []

        for skill in self.all_skills:
            result = self.compute_composite_score(
                skill["id"],
                model_class=model_class,
                domain=domain,
                budget_limit=budget_limit,
                required_entries=required_entries,
            )
            all_scores.append(result)

        # Sort by composite score (best first)
        all_scores.sort(key=lambda x: x["composite"], reverse=True)

        # Assign rankings
        for i, score_result in enumerate(all_scores):
            score_result["ranking"] = i + 1

        # Filter: only include skills above a threshold or in top N
        threshold = 0.5
        selected = [s for s in all_scores if s["composite"] >= threshold]

        # If too few selected, take top N
        if len(selected) < 5 and len(all_scores) > 0:
            selected = all_scores[: min(len(all_scores), 10)]

        # Exclude requested skills
        if exclude_skills:
            selected = [s for s in selected if s["skill_id"] not in exclude_skills]

        # Build skill profile
        skill_ids_selected = [s["skill_id"] for s in selected]

        # Compute domain coverage
        domain_coverage = self._compute_domain_coverage(selected)

        # Compute average composite
        avg_composite = (
            sum(s["composite"] for s in selected) / len(selected)
            if selected
            else 0.0
        )

        # Skill category breakdown
        category_breakdown = self._compute_category_breakdown(selected)

        return {
            "model_id": model_id,
            "model_class": model_class,
            "domain": domain,
            "budget_limit": budget_limit,
            "selected_skills": skill_ids_selected,
            "selected_skill_details": selected,
            "total_skills_evaluated": len(all_scores),
            "num_selected": len(selected),
            "average_composite": round(avg_composite, 3),
            "domain_coverage": domain_coverage,
            "category_breakdown": category_breakdown,
            "exclusion_count": (exclude_skills or []).__len__(),
            "selection_criteria": {
                "minimum_composite": threshold,
                "include_seven6_port": True,
                "domain_filter": domain,
            },
        }

    def _compute_domain_coverage(
        self, selected: List[Dict]
    ) -> Dict[str, float]:
        """Compute how well selected skills cover each domain."""
        domain_weights = {
            "research": 0.0,
            "analysis": 0.0,
            "generate": 0.0,
            "code": 0.0,
            "code-review": 0.0,
            "qa": 0.0,
            "sec-review": 0.0,
            "audit": 0.0,
        }

        for s in selected:
            skill_tags = s.get("breakdown", {}).get("related_overlap", 0)
            # Simple: each selected skill contributes to its domains via tags
            for domain, tags in {
                "research": ["deep-research", "knowledge-retrieval"],
                "analysis": ["analysis", "code-review"],
                "generate": ["code", "six-perspectives"],
                "code": ["code-review", "software-development"],
                "code-review": ["code-review"],
                "qa": ["qa"],
                "sec-review": ["security-review"],
                "audit": ["security-review"],
            }.items():
                if any(t in s.get("skill_tags", []) for t in tags):
                    domain_weights[domain] += skill.get("composite", 0) / len(
                        selected
                    )

        # Normalize to 0-1
        for d in domain_weights:
            domain_weights[d] = min(round(domain_weights[d], 3), 1.0)

        return domain_weights

    def _compute_category_breakdown(self, selected: List[Dict]) -> Dict[str, int]:
        """Count skills by category/type."""
        categories = {
            "with_seven6_port": 0,
            "without_seven6_port": 0,
            "with_tags": 0,
            "without_tags": 0,
            "with_platforms": 0,
            "without_platforms": 0,
        }

        for s in selected:
            if s.get("seven6_port"):
                categories["with_seven6_port"] += 1
            else:
                categories["without_seven6_port"] += 1

            if s.get("skill_tags"):
                categories["with_tags"] += 1
            else:
                categories["without_tags"] += 1

            if s.get("skill_platforms"):
                categories["with_platforms"] += 1
            else:
                categories["without_platforms"] += 1

        return categories

    def export_skill_profile(
        self, output_path: str = "seven6_skill_profile.json"
    ) -> str:
        """Export the current skill mapping as a JSON profile.

        Useful for saving/loading skill configurations across sessions.
        """
        profile = {
            "total_skills": len(self.all_skills),
            "skill_index": self.skill_index,
            "domain_skill_map": self.domain_skill_map,
            "generated": __import__("datetime").datetime.now().isoformat(),
        }

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(profile, f, indent=2)

        return output_path


# Convenience function for quick mapping
def map_model_skills(
    model_id: str,
    all_skills: Optional[List[Dict]] = None,
    model_class: str = "general",
    domain: str = "general",
    budget_limit: Optional[float] = None,
    required_entries: Optional[Set[str]] = None,
) -> Dict[str, any]:
    """Quick skill mapping for a model."""
    mapper = SkillsMapper(all_skills=all_skills)
    return mapper.map_model_to_skills(
        model_id=model_id,
        model_class=model_class,
        domain=domain,
        budget_limit=budget_limit,
        required_entries=required_entries,
    )


if __name__ == "__main__":
    # Quick demo
    import os

    mapper = SkillsMapper()
    print(f"Loaded {mapper.skills_mapper.__len__() if hasattr(mapper, '__len__') else 'skills'} skills")

    # Map skills for a NIM model in sec-review domain
    profile = mapper.map_model_to_skills(
        model_id="nvidia/llama-3.3-nemotron-super-49b-v1.5",
        model_class="NIM",
        domain="sec-review",
        budget_limit=15.0,
    )

    print(f"\nModel: {profile['model_id']}")
    print(f"Domain: {profile['domain']}")
    print(f"Budget: {profile['budget_limit']}")
    print(f"Selected {profile['num_selected']} skills (of {profile['total_skills']} evaluated)")
    print(f"Average composite: {profile['average_composite']}")
    print(f"\nTop 5 selected skills:")
    for s in profile["selected_skill_details"][:5]:
        print(f"  {s['ranking']}. {s['skill_id']} (composite: {s['composite']}) - {s['recommendations'][0] if s['recommendations'] else 'N/A'}")
