#!/usr/bin/env python3
import os, json

SEVEN6 = r".\hermes-skills"
ORCHESTRATE_DIR = r".\seven6_orchestration"
MEMORY_PATH = r".\seven6_moa\memory"

os.makedirs(ORCHESTRATE_DIR, exist_ok=True)

pipelines = {
    "p1-code-review": {
        "name": "Code Review Pipeline",
        "description": "Multi-step code review pipeline: static analysis -> security review -> quality check -> synthesis",
        "steps": [
            {
                "step_id": "p1-step-1",
                "name": "Static Analysis",
                "skill": "code-review",
                "description": "Run static code analysis using code-review skill",
                "output_schema": {"issues": "list", "complexity": "string"},
                "guardrails": ["no-sensitive-data-leak", "no-undefined-behavior"],
                "estimated_time": "30s"
            },
            {
                "step_id": "p1-step-2",
                "name": "Security Review",
                "skill": "sec-review",
                "description": "Security-focused code review",
                "output_schema": {"vulnerabilities": "list", "risk-level": "string"},
                "guardrails": ["no-exploit-generation", "privacy-preserving"],
                "estimated_time": "45s"
            },
            {
                "step_id": "p1-step-3",
                "name": "Quality Check",
                "skill": "qa",
                "description": "Quality assurance validation",
                "output_schema": {"quality-score": "0-100", "pass-fail": "boolean"},
                "guardrails": ["output-validation", "schema-checking"],
                "estimated_time": "20s"
            },
            {
                "step_id": "p1-step-4",
                "name": "Synthesis",
                "skill": "code-review",
                "description": "Compile review into actionable feedback",
                "output_schema": {"feedback": "string", "priority-issues": "list"},
                "guardrails": ["feedback-length-limit", "tone-guidelines"],
                "estimated_time": "25s"
            }
        ],
        "total_estimated_time": "120s",
        "success_criteria": "all-steps-pass AND quality-score >= 70"
    },
    "p2-rl-training": {
        "name": "RL Training Pipeline",
        "description": "Reinforcement learning training pipeline: data collection -> policy training -> evaluation -> model selection -> trajectory aggregation",
        "steps": [
            {
                "step_id": "p2-step-1",
                "name": "Data Collection",
                "skill": "rl-optimization",
                "description": "Collect agent trajectories and performance data",
                "output_schema": {"trajectories": "count", "data-quality": "0-1"},
                "guardrails": ["privacy-preserving", "no-raw-data-exfil"],
                "estimated_time": "2m"
            },
            {
                "step_id": "p2-step-2",
                "name": "Policy Training",
                "skill": "rl-optimization",
                "description": "Train policy using RL algorithms (PPO, RLHF, etc.)",
                "output_schema": {"policy-version": "string", "training-loss": "float"},
                "guardrails": ["convergence-check", "no-unstable-updates"],
                "estimated_time": "5m"
            },
            {
                "step_id": "p2-step-3",
                "name": "Evaluation",
                "skill": "qa",
                "description": "Evaluate trained policy on holdout set",
                "output_schema": {"success-rate": "0-1", "evaluation-metrics": "dict"},
                "guardrails": ["no-data-leakage", "statistical-significance"],
                "estimated_time": "3m"
            },
            {
                "step_id": "p2-step-4",
                "name": "Model Selection",
                "skill": "model_comparison_skill",
                "description": "Select best performing model variant",
                "output_schema": {"selected-model": "string", "comparison-metrics": "dict"},
                "guardrails": ["deterministic-selection", "performance-threshold"],
                "estimated_time": "2m"
            },
            {
                "step_id": "p2-step-5",
                "name": "Trajectory Aggregation",
                "skill": "trajectory-aggregation",
                "description": "Aggregate trained trajectories for faster convergence",
                "output_schema": {"aggregated-model": "string", "improvement-factor": "float"},
                "guardrails": ["aggregation-validation", "no-degradation"],
                "estimated_time": "1m"
            }
        ],
        "total_estimated_time": "11m",
        "success_criteria": "success-rate >= 0.6 AND improvement-factor > 1.0"
    },
    "p3-mcp-integration": {
        "name": "MCP Integration Pipeline",
        "description": "Model Context Protocol integration and Zendriver-MCP setup",
        "steps": [
            {
                "step_id": "p3-step-1",
                "name": "MCP Builder Setup",
                "skill": "mcp-builder",
                "description": "Initialize MCP builder with required capabilities",
                "output_schema": {"mcp-config": "dict", "capabilities": "list"},
                "guardrails": ["valid-mcp-spec", "compliance-check"],
                "estimated_time": "1m"
            },
            {
                "step_id": "p3-step-2",
                "name": "Zendriver-MCP Integration",
                "skill": "mcp-zendriver",
                "description": "Integrate Zendriver-MCP patterns and extensions",
                "output_schema": {"integration-status": "string", "endpoint": "string"},
                "guardrails": ["valid-endpoint", "protocol-compliance"],
                "estimated_time": "2m"
            },
            {
                "step_id": "p3-step-3",
                "name": "Pattern Validation",
                "skill": "schema-drift",
                "description": "Validate MCP patterns against drift detection",
                "output_schema": {"drift-score": "0-1", "validation-result": "boolean"},
                "guardrails": ["no-false-positives", "pattern-compliance"],
                "estimated_time": "1m"
            },
            {
                "step_id": "p3-step-4",
                "name": "Configuration Finalization",
                "skill": "config-drift",
                "description": "Finalize MCP configuration with drift baselines",
                "output_schema": {"final-config": "dict", "baseline-established": "boolean"},
                "guardrails": ["config-integrity", "version-consistency"],
                "estimated_time": "1m"
            }
        ],
        "total_estimated_time": "5m",
        "success_criteria": "all-steps-pass AND drift-score < 0.1"
    },
    "p4-agent-coordination": {
        "name": "Multi-Agent Coordination Pipeline",
        "description": "Coordinate multiple agents using multi-agent-coordination skill",
        "steps": [
            {
                "step_id": "p4-step-1",
                "name": "Agent Registration",
                "skill": "multi-agent-coordination",
                "description": "Register all agents in the coordination system",
                "output_schema": {"registered-agents": "count", "agent-ids": "list"},
                "guardrails": ["unique-agent-ids", "capability-validation"],
                "estimated_time": "1m"
            },
            {
                "step_id": "p4-step-2",
                "name": "Capability Alignment",
                "skill": "multi-agent-coordination",
                "description": "Align agent capabilities for complementary operation",
                "output_schema": {"alignment-map": "dict", "coverage": "0-1"},
                "guardrails": ["capability-coverage", "no-redundancy"],
                "estimated_time": "2m"
            },
            {
                "step_id": "p4-step-3",
                "name": "Optimization",
                "skill": "rl-optimization",
                "description": "Apply RL-based optimization to coordinated agents",
                "output_schema": {"optimization-result": "dict", "performance-gain": "float"},
                "guardrails": ["performance-threshold", "stability-check"],
                "estimated_time": "3m"
            },
            {
                "step_id": "p4-step-4",
                "name": "Consistency Check",
                "skill": "sec-review",
                "description": "Verify system-wide consistency and safety",
                "output_schema": {"consistency-score": "0-1", "safety-issues": "list"},
                "guardrails": ["no-safety-violations", "system-integrity"],
                "estimated_time": "2m"
            },
            {
                "step_id": "p4-step-5",
                "name": "Synthesis & Report",
                "skill": "code-review",
                "description": "Generate final coordination report and recommendations",
                "output_schema": {"report": "string", "recommendations": "list"},
                "guardrails": ["report-length", "actionable-recommendations"],
                "estimated_time": "1m"
            }
        ],
        "total_estimated_time": "9m",
        "success_criteria": "consistency-score >= 0.8 AND performance-gain > 0.15"
    },
    "p5-security-audit": {
        "name": "Security Audit Pipeline",
        "description": "Comprehensive security audit across all skill layers",
        "steps": [
            {
                "step_id": "p5-step-1",
                "name": "Prompt Injection Scan",
                "skill": "seven6-security",
                "description": "Scan prompts for injection vulnerabilities",
                "output_schema": {"injection-risk": "0-1", "risk-factors": "list"},
                "guardrails": ["no-real-exploits-generated", "safe-scan-only"],
                "estimated_time": "1m"
            },
            {
                "step_id": "p5-step-2",
                "name": "Code Security Review",
                "skill": "sec-review",
                "description": "Comprehensive code security review",
                "output_schema": {"security-issues": "list", "severity-breakdown": "dict"},
                "guardrails": ["no-exploit-generation", "privacy-preserving"],
                "estimated_time": "3m"
            },
            {
                "step_id": "p5-step-3",
                "name": "Schema & Config Audit",
                "skill": "schema-drift",
                "description": "Audit all schemas and configurations for drift",
                "output_schema": {"drift-reports": "count", "critical-drift": "count"},
                "guardrails": ["complete-coverage", "actionable-reports"],
                "estimated_time": "2m"
            },
            {
                "step_id": "p5-step-4",
                "name": "Token Optimization Audit",
                "skill": "token-optimization",
                "description": "Audit token optimization for drift and safety",
                "output_schema": {"optimization-audit": "dict", "safety-score": "0-1"},
                "guardrails": ["no-drift-introduction", "safety-preservation"],
                "estimated_time": "1m"
            },
            {
                "step_id": "p5-step-5",
                "name": "Final Audit Report",
                "skill": "code-review",
                "description": "Compile comprehensive security audit report",
                "output_schema": {"audit-report": "string", "critical-issues": "list", "remediation-priority": "list"},
                "guardrails": ["report-completeness", "actionable-remediation"],
                "estimated_time": "1m"
            }
        ],
        "total_estimated_time": "8m",
        "success_criteria": "critical-issues = 0 AND remediation-priority has clear actions"
    }
}

pipelines_path = os.path.join(ORCHESTRATE_DIR, "p1-p5-pipelines.json")
with open(pipelines_path, "w", encoding="utf-8", newline='') as f:
    json.dump(pipelines, f, indent=2)

print(f"Created pipelines: {pipelines_path}")
for pname, pdata in pipelines.items():
    print(f"  {pname}: {len(pdata['steps'])} steps")