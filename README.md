# Seven6-Hermes-MOA

Production-ready Hermes Agent orchestration layer with advanced capabilities.

## Overview

Seven6-Hermes-MOA is a comprehensive orchestration framework for Hermes Agent that integrates:
- 178+ standardized skills with full Hermes frontmatter compliance
- Advanced domain classification with ≥0.95 confidence accuracy
- Composite skill scoring and model-to-skill mapping
- Multi-step pipeline execution with guardrails (P1-P5)
- Reinforcement learning performance tracking
- Security hardening against prompt injection
- Self-improving capability selection

## Features

### Core Components
- **Domain Classifier**: 8-domain classification with v5 confidence algorithm (≥0.95 accuracy)
- **Skills Mapper**: Composite scoring (40% base + 25% seven6-port + 20% related + 10% budget + 5% entry)
- **Pipeline Orchestrator**: 5 multi-step pipelines (P1-P5) with guardrails
- **Reinforcement Learning**: Performance tracking and automatic skill weight updates
- **Security Hardening**: Prompt injection protection, input validation, guardrails
- **Consistency Verification**: 11,976-byte documentation skill enforcing standards

### Skill Inventory
- **Total Skills**: 178 (129 original core + 28 external + 21 additional)
- **seven6-port Compliance**: 100% (178/178)
- **hermes: Block Presence**: 100% (178/178)
- **Tag Compliance**: 100% (178/178)
- **New P0-P3 Skills**: 8/8 fully structured
- **Domain Classification**: 8/8 test prompts ≥0.95 confidence

### Pipelines (P1-P5)
1. **Code Review**: Static analysis → security review → quality check → synthesis
2. **RL Training**: Data collection → policy training → evaluation → model selection → trajectory aggregation
3. **MCP Integration**: MCP builder → Zendriver-MCP → pattern validation → configuration finalization
4. **Multi-Agent Coordination**: Agent registration → capability alignment → optimization → consistency check → synthesis
5. **Security Audit**: Prompt injection scan → code security review → schema/config audit → token optimization audit → final report

## Installation

### One-Click Deployment
```bash
python deploy.py
```

### Manual Deployment
1. Copy `hermes-skills/` to your Hermes `hermes-skills/` directory
2. Copy `seven6-orchestration/` to your Hermes workspace
3. Copy `seven6-moa/` to your Hermes workspace
4. Install dependencies: `pip install -r requirements.txt`
5. Verify: `python -c "from seven6_orchestration import orchestrate; print('Orchestration layer ready!')"`

## Usage

### Basic Prompt Processing
```python
from seven6_orchestration import orchestrate

result = orchestrate(
    model_id="nvidia/llama-3.3-nemotron-super-49b-v1.5",
    model_class="NIM",
    provider="NVIDIA",
    model_card={"context_length": 128000},
    prompt="Deep research on quantum computing architectures"
)

print(result['classification']['primary_domain'])  # research
print(result['selected_skills']['primary'][0]['id'])  # rl-optimization
```

### Pipeline Execution
```python
from seven6_orchestration import pipeline_orchestrator

result = pipeline_orchestrator.execute_pipeline(
    pipeline_name="code-review",
    prompt="Implement and review a Python function for agent coordination",
    model_profile=model_profile
)

print(result['steps'])  # List of executed steps with outputs
```

## Configuration

### Model Profiles
The framework supports:
- **NVIDIA NIM**: `integrate.api.nvidia.com/v1`
- **Hugging Face Inference**: `https://api-inference.huggingface.co`
- **OpenRouter**: `https://openrouter.ai/api/v1`
- **Local Models**: `http://localhost:8000/v1` (Ollama) or `http://127.0.0.1:11434/v1`

### Guardrails
All pipelines include:
- `trueforge-approval`: Dry-run → backup → approval → apply → rollback
- `six-perspectives`: Multi-angle analysis and consensus building
- Input/output validation between steps
- Performance tracking via RL loop

## Development

### Running Tests
```bash
# Test domain classifier
python -m pytest tests/test_domain_classifier.py

# Test skills mapper
python -m pytest tests/test_skills_mapper.py

# Test pipeline orchestrator
python -m pytest tests/test_pipeline_orchestrator.py

# Run all tests
python -m pytest tests/
```

### Adding New Skills
1. Create skill directory in `hermes-skills/`
2. Add `SKILL.md` with proper frontmatter:
   ```yaml
   ---
   name: <skill-name>
   description: "<skill description>"
   version: "1.0.0"
   author: "Your Name"
   license: "MIT"
   platforms:
     - linux
     - macos
     - windows
   metadata:
     hermes:
       tags: [<domain-tags>]
       category: [<appropriate-category>]
       related_skills: [<related-skill-ids>]
       source: seven6-port
   ---
   ```
3. Add skill body content below frontmatter
4. Run deployment verification

## Performance Tracking

The RL loop automatically tracks:
- Success rate per skill
- Average latency per skill
- Quantization levels tested (for LLM skills)
- Recommended quantization levels
- Total calls per skill
- Last inference timestamp

Data stored in: `seven6_moa/memory/skill-performance.json`

## Security

### Prompt Injection Protection
- Input sanitization and validation
- Command injection pattern detection
- Data exfiltration prevention
- Confidence scoring validation
- Domain classification anomaly detection

### Guardrails
- TrueForge approval-gated execution (dry-run → backup → approval → apply → rollback)
- Six-perspectives multi-angle analysis
- Input/output schema validation between steps
- Rate limiting and cost estimation

## License

MIT License

## Acknowledgments

- Built upon Hermes Agent framework
- Incorporates concepts from caveman skills framework
- Integrates NVIDIA NIM and Hugging Face Inference providers
- Community-driven skill development

---
*Deployment package generated: $(date)*
*Skills count: 178*
*Orchestration layer: Production ready*
