---
name: research-pipeline
description: "academic-research-skills **Full 10-stage research pipeline for Claude Code**"
version: 1.0.0
author: "Seven6-Hermes-MOA conversion"
license: "MIT"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [research, pipeline, academic]
    category: general
    related_skills: []
    source: seven6-port
---

# academic-research-skills
**Full 10-stage research pipeline for Claude Code**

A Hermes skill implementing the complete academic research pipeline from research to publication, covering:
- Deep Research (13-agent Socratic guided team with PRISMA-style systematic review)
- Academic Paper (12-agent LaTeX-hardened writing with visualization, citation conversion)
- Academic Paper Reviewer (multi-perspective peer review with 0-100 quality rubrics)
- Academic Pipeline (10-stage orchestrator with adaptive checkpoints, integrity verification, material passport)

**Key Features:**
1. Adaptive checkpoints (FULL / SLIM / MANDATORY) after every stage
2. Pre-review integrity verification — 100% reference, data, and claim validation
2. Two-stage review with Devil's Advocate + 0-100 quality rubrics
3. Socratic revision coaching between review and revision stages
4. Final integrity verification before publication
5. Output: MD + DOCX + LaTeX (APA 7.0 / IEEE / Chicago) → PDF via tectonic
6. Post-pipeline process summary with 6-dimension collaboration quality scoring
7. Material passport for mid-entry provenance tracking
8. Cross-skill mode advisor (14 scenarios + user archetypes)

**Pipeline Stages:**
```
Research → Write → Integrity Check → Review (5-person) → Socratic Coaching
  → Revise → Re-Review → Re-Revise → Final Integrity Check → Finalize
  → Process Summary (with Collaboration Quality Evaluation)
```

**Dependencies:**
- mem9 for persistent memory
- LaTeX toolchain (tectonic, pdflatex)
- MSAL for Azure AD authentication
- GraphClient for Microsoft Graph APIs

**Surfaces:** hermes

**Tags:** research, pipeline, academic-writing, review, latex, prisma, socratic, integrity