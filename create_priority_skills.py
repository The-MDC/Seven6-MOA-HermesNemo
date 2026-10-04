#!/usr/bin/env python3
import os

SEVEN6 = r".\hermes-skills"

skills_data = {
    "rl-optimization": {
        "name": "RL Optimization",
        "description": "Reinforcement Learning-based agent skill optimization framework. Optimizes agent performance through reward shaping, policy gradients, and trajectory aggregation. Works with any agent framework (LangChain, AutoGen, CrewAI, OpenAI Agent SDK) without code changes.",
        "version": "1.0.0",
        "author": "Seven6-Hermes-MOA conversion",
        "license": "MIT",
        "platforms": ["cloud", "local", "nim"],
        "tags": ["rl-optimization", "reinforcement-learning", "agent-training", "prompt-optimization"],
        "category": "optimization",
        "metadata": 'hermes: {tags: ["rl-optimization", "reinforcement-learning", "agent-training", "prompt-optimization"], source: seven6-port, related_skills: ["prompt-optimization", "multi-agent-coordination"]}',
        "body": "# RL Optimization Skill\n\n## Overview\nProvides reinforcement learning-based optimization for AI agents.\n\n## Features\n- Policy gradient optimization\n- Reward shaping\n- Trajectory aggregation (from Agent Lightning)\n- Framework-agnostic integration\n\n## Usage\n```python\nfrom hermes import RLOptimizer\noptimizer = RLOptimizer(agent_framework=\"auto\")\noptimized = optimizer.optimize(agent)\n```"
    },
    "prompt-optimization": {
        "name": "Prompt Optimization",
        "description": "Automatic prompt tuning and optimization using algorithms from Agent Lightning. Zero-code change prompt improvement for any agent framework.",
        "version": "1.0.0",
        "author": "Seven6-Hermes-MOA conversion",
        "license": "MIT",
        "platforms": ["cloud", "local", "nim", "hf"],
        "tags": ["prompt-optimization", "auto-prompt-optimization", "trajectory-aggregation"],
        "category": "optimization",
        "metadata": 'hermes: {tags: ["prompt-optimization", "auto-prompt-optimization", "trajectory-aggregation"], source: seven6-port, related_skills: ["rl-optimization"]}',
        "body": "# Prompt Optimization Skill\n\n## Overview\nAutomatic prompt tuning and optimization.\n\n## Features\n- Auto-prompt optimization (Part 2 from Agent Lightning blog)\n- Trajectory level aggregation\n- Zero-code change integration\n- Multi-framework support\n\n## Usage\n```python\nfrom hermes import PromptOptimizer\noptimizer = PromptOptimizer()\noptimized_prompt = optimizer.optimize(\"original prompt\")\n```"
    },
    "multi-agent-coordination": {
        "name": "Multi-Agent Coordination",
        "description": "Optimize and coordinate multiple agents in a multi-agent system. Selective optimization of specific agents while maintaining system-wide consistency.",
        "version": "1.0.0",
        "author": "Seven6-Hermes-MOA conversion",
        "license": "MIT",
        "platforms": ["cloud", "local", "nim"],
        "tags": ["multi-agent-coordination", "agentic-gateway", "multi-agent-systems"],
        "category": "coordination",
        "metadata": 'hermes: {tags: ["multi-agent-coordination", "agentic-gateway", "multi-agent-systems"], source: seven6-port, related_skills: ["agentic-gateway", "rl-optimization"]}',
        "body": "# Multi-Agent Coordination Skill\n\n## Overview\nCoordinate and optimize multiple agents in a system.\n\n## Features\n- Selective agent optimization\n- System-wide consistency maintenance\n- Framework-agnostic (LangChain, AutoGen, CrewAI)\n- Integration with agentic-gateway\n\n## Usage\n```python\nfrom hermes import MultiAgentCoordinator\ncoordinator = MultiAgentCoordinator()\nresult = coordinator.coordinate([agent1, agent2, agent3])\n```"
    },
    "schema-drift": {
        "name": "Schema Drift Detection",
        "description": "Detects and reports configuration and schema drift in AI agent workflows, inspired by suavir600/schema-drift-checker and jameskomo/config-drift-checker repos.",
        "version": "1.0.0",
        "author": "Seven6-Hermes-MOA conversion",
        "license": "MIT",
        "platforms": ["cloud", "local"],
        "tags": ["schema-drift", "config-drift", "infrastructure-drift"],
        "category": "drift-detection",
        "metadata": 'hermes: {tags: ["schema-drift", "config-drift", "infrastructure-drift"], source: seven6-port, related_skills: ["config-drift"]}',
        "body": "# Schema Drift Detection Skill\n\n## Overview\nDetects configuration and schema drift in AI agent workflows.\n\n## Features\n- Config drift detection (from config-drift-checker)\n- Schema validation and drift reporting\n- IaC drift (terraform, python3, terragrunt)\n- Integration with Seven6 config management\n\n## Usage\n```python\nfrom hermes import SchemaDriftDetector\ndetector = SchemaDriftDetector()\nreport = detector.detect_drift(current_config, baseline_config)\n```"
    },
    "trajectory-aggregation": {
        "name": "Trajectory Aggregation",
        "description": "Trajectory level aggregation for faster agent training, from Agent Lightning's 'Adopting the Trajectory Level Aggregation for Faster Training' blog post.",
        "version": "1.0.0",
        "author": "Seven6-Hermes-MOA conversion",
        "license": "MIT",
        "platforms": ["cloud", "local", "nim"],
        "tags": ["trajectory-aggregation", "rl-training", "agent-lightning"],
        "category": "training",
        "metadata": 'hermes: {tags: ["trajectory-aggregation", "rl-training", "agent-lightning"], source: seven6-port, related_skills: ["rl-optimization", "prompt-optimization"]}',
        "body": "# Trajectory Aggregation Skill\n\n## Overview\nTrajectory level aggregation for faster agent training.\n\n## Features\n- Trajectory level aggregation algorithm\n- Faster training convergence\n- Compatible with any RL framework\n- Integration with Agent Lightning\n\n## Usage\n```python\nfrom hermes import TrajectoryAggregator\naggregator = TrajectoryAggregator()\ntrained_agent = aggregator.aggregate(trajectories)\n```"
    },
    "mcp-zendriver": {
        "name": "MCP-Zendriver Integration",
        "description": "Integrates Zendriver-MCP capabilities with the Seven6 MCP skill framework. Provides Model Context Protocol integration with Zendriver-specific patterns and extensions.",
        "version": "1.0.0",
        "author": "Seven6-Hermes-MOA conversion",
        "license": "MIT",
        "platforms": ["cloud", "local"],
        "tags": ["mcp-zendriver", "mcp-integration", "zendriver-mcp"],
        "category": "mcp",
        "metadata": 'hermes: {tags: ["mcp-zendriver", "mcp-integration", "zendriver-mcp"], source: seven6-port, related_skills: ["mcp-builder", "mcp-server-patterns"]}',
        "body": "# MCP-Zendriver Integration Skill\n\n## Overview\nZendriver-MCP integration with Seven6 MCP framework.\n\n## Features\n- Zendriver-MCP protocol support\n- Integration with existing mcp-builder skills\n- Custom patterns from Zendriver-MCP repo\n- Zero-code change setup\n\n## Usage\n```python\nfrom hermes import MCPZendriverIntegration\nintegrator = MCPZendriverIntegration()\nresult = integrator.integrate()\n```"
    },
    "sql-rl": {
        "name": "SQL Reinforcement Learning",
        "description": "Train AI agents to write and self-correct SQL with Reinforcement Learning, from Agent Lightning's 'Training AI Agents to Write and Self-correct SQL with Reinforcement Learning' Medium post.",
        "version": "1.0.0",
        "author": "Seven6-Hermes-MOA conversion",
        "license": "MIT",
        "platforms": ["cloud", "local"],
        "tags": ["sql-rl", "rl-training", "sql-coding"],
        "category": "coding",
        "metadata": 'hermes: {tags: ["sql-rl", "rl-training", "sql-coding"], source: seven6-port, related_skills: ["code-review", "codex-hermes-bridge"]}',
        "body": "# SQL Reinforcement Learning Skill\n\n## Overview\nTrain AI agents to write and self-correct SQL with RL.\n\n## Features\n- SQL query generation with RL\n- Self-correction loops\n- Integration with Agent Lightning\n- Zero-code change for SQL-reliant agents\n\n## Usage\n```python\nfrom hermes import SQLRLTrainer\ntrainer = SQLRLTrainer()\ntrained_trainer = trainer.train(\"schema\", \"query-examples\")\n```"
    },
    "token-optimization": {
        "name": "Token Optimization",
        "description": "Address retokenization drift by returning token IDs via OpenAI Compatible API, from Agent Lightning's 'No More Retokenization Drift: Returning Token IDs via the OpenAI Compatible API Matters in Agent RL vLLM' blog post.",
        "version": "1.0.0",
        "author": "Seven6-Hermes-MOA conversion",
        "license": "MIT",
        "platforms": ["cloud", "local", "nim", "hf"],
        "tags": ["token-optimization", "ret-tokenization-drift", "agent-lightning"],
        "category": "optimization",
        "metadata": 'hermes: {tags: ["token-optimization", "ret-tokenization-drift", "agent-lightning"], source: seven6-port, related_skills: ["prompt-optimization", "rl-optimization"]}',
        "body": "# Token Optimization Skill\n\n## Overview\nSolves retokenization drift by returning token IDs via OpenAI Compatible API.\n\n## Features\n- Token ID return via OpenAI Compatible API\n- Retokenization drift elimination\n- Compatible with vLLM and any LLM backend\n- Integration with Agent Lightning\n\n## Usage\n```python\nfrom hermes import TokenOptimizer\noptimizer = TokenOptimizer()\ntoken_ids = optimizer.optimize(\"prompt\", model)\n```"
    }
}

# Create all 8 skill directories and SKILL.md files
for skill_id, data in skills_data.items():
    skill_dir = os.path.join(SEVEN6, skill_id)
    os.makedirs(skill_dir, exist_ok=True)
    
    skill_md_path = os.path.join(skill_dir, "SKILL.md")
    
    # Build frontmatter
    fm = f'---\nname: "{data["name"]}"\ndescription: "{data["description"]}"\nversion: {data["version"]}\nauthor: "{data["author"]}"\nlicense: "{data["license"]}"\nplatforms: {data["platforms"]}\ntags: {data["tags"]}\n---\n\n'
    
    # Add metadata.hermes block
    fm += data['metadata'] + "\n"
    
    # Add body
    fm += data['body']
    
    with open(skill_md_path, "w", encoding="utf-8", newline='') as f:
        f.write(fm)
    
    print(f"✅ Created {skill_id}/SKILL.md")

print("\n=== All 8 priority skills created successfully ===")