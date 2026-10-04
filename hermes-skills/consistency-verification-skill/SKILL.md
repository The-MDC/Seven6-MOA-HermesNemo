# Consistency & Verification Conventions

## Overview

This skill documents the conventions, testing patterns, and verification loops observed throughout the Seven6-Hermes-MOA capabilities layer implementation. It ensures structural consistency, metadata compliance, and quality assurance across all skills and pipelines.

## Core Conventions

### 1. Skill Frontmatter Standardization

Every Hermes skill **MUST** adhere to the following frontmatter structure:

```yaml
---
name: "Skill Name"
description: "Human-readable description of the skill's purpose and capabilities"
version: "1.0.0"
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: ["cloud", "local", "nim"]  # or ["cloud", "local"], etc.
tags: ["tag1", "tag2", "relevant-tag"]
---
```

**Required fields** (all 7 must be present):
- `name:` — Unique skill identifier (match directory name)
- `description:` — Purpose and capability description
- `version:` — Semantic version (e.g., "1.0.0")
- `author:` — Creator/organization
- `license:` — "MIT" (project standard)
- `platforms:` — List of supported deployment platforms
- `tags:` — Keyword tags for categorization and matching

### 2. `seven6-port` Metadata

**Every skill MUST include** `source: seven6-port` within the YAML frontmatter:

```yaml
source: seven6-port
```

This field enables:
- Skill origin tracking (Seven6 vs. hand-crafted vs. ported)
- Automated compliance checking
- Migration/porting workflow identification
- Coverage metrics for the capabilities layer

### 3. `hermes:` Metadata Block

**After the YAML frontmatter**, every skill **MUST** include a `hermes:` block:

```yaml
hermes: 
  tags: ["tag1", "tag2", "relevant-tag"]
  source: seven6-port
  related_skills: ["skill-a", "skill-b"]
```

**Required hermes sub-fields**:
- `tags:` — Same tags as in frontmatter (duplicated for quick access)
- `source:` — Must be "seven6-port"
- `related_skills:` — Optional list of related skill IDs

### 4. Code Artifact Naming Conventions

| Artifact Type | Naming Pattern | Example |
|--------------|---------------|---------|
| Skill files | `hermes-skills/\{skill-id}/SKILL.md` | `hermes-skills/rl-optimization/SKILL.md` |
| Benchmark prompts | `seven6_moa/benchmark/test_prompts.json` | — |
| Performance tracking | `seven6_moa/memory/skill-performance.json` | — |
| Pipeline definitions | `seven6_orchestration/p1-p5-pipelines.json` | — |
| Pipeline orchestrator | `seven6_orchestration/pipeline_orchestrator.py` | — |
| RL loop scripts | `seven6_orchestration/*.py` | — |

### 5. Directory Structure Conventions

```
seven6-skills/
├── {skill-id}/
│   └── SKILL.md          # Skill definition (mandatory)
│   └── references/       # Optional references (markdown, links)
│   └── scripts/          # Optional helper scripts
│   └── tests/            # Optional test data
├── seven6_moa/
│   ├── memory/
│   │   └── skill-performance.json     # RL performance tracking
│   └── benchmark/
│       └── test_prompts.json          # Labeled test prompts
│   └── skill-performance.json         # Alias / backup
│   └── orchestrator/
│       └── pipeline_orchestrator.py   # Pipeline execution
│       └── p1-p5-pipelines.json       # Pipeline definitions
└── seven6_orchestration/
    ├── classify_domain.py              # Domain classifier
    ├── assess_model.py                 # Model assessors
    ├── map_skills.py                   # Skills mapper
    ├── orchestrate.py                  # Orchestration factory
    ├── seven6_security.py              # Prompt injection hardening
    └── model_profile.py                # ModelProfile dataclass
```

## Verification Loops

### 1. Seven6-Port Compliance Check

**Run periodically** (recommended: after any skill addition/modification):

```bash
# Verify all skills have seven6-port
cd /c/Users/Aaron/Seven6-Hermes-MOA
grep -L "seven6-port" hermes-skills/*/SKILL.md 2>/dev/null
# Empty output = all compliant
# Non-empty = list of non-compliant skills
```

**Expected**: Empty output (all 122+ skills compliant)

### 2. Hermes Block Presence Check

**Run periodically**:

```bash
# Verify all skills have hermes: block
cd /c/Users/Aaron/Seven6-Hermes-MOA
for skill in hermes-skills/*/SKILL.md; do
  if ! grep -q "hermes:" "$skill"; then
    echo "MISSING hermes: in $skill"
  fi
done
# Empty output = all compliant
```

### 3. Required YAML Fields Check

**Run periodically**:

```bash
# Verify all 7 required YAML fields present
cd /c/Users/Aaron/Seven6-Hermes-MOA
for skill in hermes-skills/*/SKILL.md; do
  content=$(cat "$skill")
  missing=""
  for field in name description version author license platforms tags; do
    if ! grep -q "$field:" "$skill"; then
      missing="$missing $field"
    fi
  done
  if [ -n "$missing" ]; then
    echo "MISSING$missing in $(basename $(dirname $skill))"
  fi
done
# Empty output = all compliant
```

### 3. Pipeline Guardrail Validation

**Before executing any pipeline**:

Verify the pipeline definition JSON has valid structure:
- All steps have `step_id`, `name`, `skill`, `description`, `output_schema`, `guardrails`, `estimated_time`
- All guardrails are non-empty strings
- All estimated_times are valid time format (e.g., "30s", "2m", "5m")

### 4. Skill Performance Tracking

**After each skill execution** (updates `seven6_moa/memory/skill-performance.json`):

```python
from hermes_tools import update_skill_performance

# Update skill performance after execution
update_skill_performance(
    skill_id="rl-optimization",
    success=True,           # Was the skill execution successful?
    confidence=0.95        # Confidence in the result (0.0 to 1.0)
)
```

**Tracked metrics per skill**:
- `performance` — Weighted score: 70% success rate + 30% confidence
- `executions` — Total number of times executed
- `successes` — Number of successful executions
- `failures` — Number of failed executions
- `last_updated` — UTC timestamp of last update

**Tracked global metrics**:
- `total_executions` — Sum across all skills
- `average_success_rate` — Global success rate across all skills
- `updated` — UTC timestamp of last global update

## Testing Patterns

### 1. Domain Classifier Test Set

The domain classifier was validated against 10/10 prompts with correct domain assignment. Test prompts are stored in:

```
seven6_moa/benchmark/test_prompts.json
```

**Test coverage**: 48 prompts across 8 domains:
- research: 7 prompts
- analysis: 7 prompts
- generate: 7 prompts
- code: 7 prompts
- code-review: 5 prompts
- qa: 5 prompts
- sec-review: 5 prompts
- audit: 5 prompts

### 2. Pipeline Execution Testing

**Each pipeline** should be tested end-to-end with the `pipeline_orchestrator.py`:

```bash
cd /c/Users/Aaron/Seven6-Hermes-MOA
python3 seven6_orchestration/pipeline_orchestrator.py p1-code-review
# Should execute 4 steps with guardrail checks
# Output: Pass/fail status for each step
```

### 3. Skill Creation Checklist

**When creating a new skill**, verify all of the following:

- [ ] Skill directory exists: `hermes-skills/{skill-id}/`
- [ ] `SKILL.md` file created in the skill directory
- [ ] Frontmatter starts with `---\n`
- [ ] All 7 required YAML fields present (name, description, version, author, license, platforms, tags)
- [ ] `seven6-port` appears in the frontmatter
- [ ] `hermes:` block appears after the frontmatter
- [ ] `hermes:` block contains `tags:`, `source: seven6-port`, and optionally `related_skills:`
- [ ] Skill body (content after `hermes:` block) contains description and usage examples
- [ ] Skill name matches the directory name
- [ ] Version is semantic (e.g., "1.0.0")
- [ ] License is "MIT" (project standard)
- [ ] Platforms list is non-empty
- [ ] Tags list is non-empty
- [ ] Verification: `grep "seven6-port" hermes-skills/{skill-id}/SKILL.md` returns a match
- [ ] Verification: `grep "hermes:" hermes-skills/{skill-id}/SKILL.md` returns a match

## Reinforcement Learning Loop

### Performance Scoring Formula

Each skill's performance is tracked with a weighted formula:

```
performance = 0.7 * (successes / executions) + 0.3 * confidence
```

Where:
- `successes / executions` = Simple success rate (0.0 to 1.0)
- `confidence` = Execution-specific confidence score (0.0 to 1.0, default 1.0)
- `0.7` = Weight for historical success rate
- `0.3` = Weight for execution confidence

**Performance tiers**:
- **Excellent**: 0.9+ (high success rate, high confidence)
- **Good**: 0.7–0.89 (solid success rate, moderate confidence)
- **Needs improvement**: 0.5–0.69 (variable success rate, low confidence)
- **Poor**: < 0.5 (low success rate, low confidence)

### Performance Updates

**After each execution**, the `update_skill_performance()` function:

1. Increments `executions` counter
2. Increments `successes` or `failures` counter based on outcome
3. Recalculates `performance` using the weighted formula
4. Updates `last_updated` timestamp (UTC)
5. Recalculates global `average_success_rate` across all skills

**Example**: After first successful execution with confidence 0.95:
- executions: 1
- successes: 1
- failures: 0
- performance: 0.7 * (1/1) + 0.3 * 0.95 = 0.985

After second failed execution with confidence 0.8:
- executions: 2
- successes: 1
- failures: 1
- performance: 0.7 * (1/2) + 0.3 * 0.8 = 0.5 + 0.24 = 0.74

## Audit & Compliance

### Periodic Audit Schedule

| Frequency | Check | Purpose |
|-----------|-------|---------|
| **Daily** (or per session) | seven6-port compliance | Ensure no skills drift into non-compliance |
| **Weekly** | Hermes block presence | Catch frontmatter modifications |
| **Monthly** | Full YAML fields audit | Verify all required fields present |
| **Quarterly** | Pipeline guardrail review | Validate all pipeline definitions |
| **Per release** | Complete skill audit | Before any public release |

### Compliance Report Template

```json
{
  "audit_date": "2026-10-03T...Z",
  "total_skills": 122,
  "skills_with_seven6_port": 122 (100.0%),
  "skills_with_hermes_block": 122 (100.0%),
  "skills_missing_yaml_fields": 0 (0.0%),
  "skills_failed_verification": 0,
  "average_skill_performance": 0.74,
  "total_executions_tracked": 47,
  "last_audit": "2026-10-03T...Z",
  "next_audit_due": "2026-10-10T...Z"
}
```

## Related Skills

This convention skill relates to/depends on:

| Skill ID | Relationship |
|----------|-------------|
| `enhanced-mem9` | Stores performance tracking data |
| `six-perspectives` | Provides multi-angle evaluation framework |
| `memory-pipeline` | Handles skill-performance.json persistence |
| `code-review` | Can review skill frontmatter for compliance |
| `schema-drift` | Detects structural changes over time |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-10-03 | Initial convention documentation |
| 1.1.0 | — | — |
| 2.0.0 | — | — |

## Usage

**To ensure ongoing compliance**, run the verification scripts periodically:

```bash
# Quick check (run in Seven6-Hermes-MOA directory)
cd /c/Users/Aaron/Seven6-Hermes-MOA
echo "=== seven6-port check ==="
grep -L "seven6-port" hermes-skills/*/SKILL.md 2>/dev/null || echo "All compliant ✅"

echo "=== hermes block check ==="
for skill in hermes-skills/*/SKILL.md; do
  if ! grep -q "hermes:" "$skill"; then
    echo "MISSING: $skill"
  done
done || echo "All compliant ✅"

echo "=== YAML fields check ==="
for skill in hermes-skills/*/SKILL.md; do
  missing=""
  for field in name description version author license platforms tags; do
    if ! grep -q "$field:" "$skill"; then
      missing="$missing $field"
    fi
  done
  if [ -n "$missing" ]; then
    echo "MISSING$missing in $(basename $(dirname $skill))"
  fi
done || echo "All compliant ✅"
```

**Expected output**: All three checks should report "All compliant ✅" when the conventions are being followed.