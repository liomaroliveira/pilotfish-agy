# Pilotfish for Antigravity (`pilotfish-agy`)

Multi-model, quota-aware orchestration policy and 7 specialized leaf subagents ported from [Nanako0129/pilotfish](https://github.com/Nanako0129/pilotfish) `v1.5.0` for **Google Antigravity**.

## What This Plugin Ships

- **Always-on orchestration policy:** `rules/AGENTS.md` (live model+thinking+quota discovery via `swarm(action="models", all=true)`, adaptive 3-tier grouping, project-specialist precedence, and full Antigravity native tool/skill/MCP integration).
- **Configurable defaults:** `config.json` (`routingMode: "hybrid"`, `crossPoolRouting: true`, `quotaFloorPercent: 10`, `protectModels: ["argon"]`, `projectAgentPrecedence: true`). Override per project via `.agents/pilotfish.config.json` or inline in your prompt.
- **On-demand orchestration playbook skill:** `skills/pilotfish/SKILL.md`.
- **7 complementary leaf subagents (`agents/pf-*.md`):** `pf-scout`, `pf-mech-executor`, `pf-executor`, `pf-plan-verifier`, `pf-security-reviewer`, `pf-security-executor`, `pf-verifier`.
- **Project override templates (`examples/`):** ready-to-copy `examples/project-pilotfish.config.json` (`.agents/pilotfish.config.json`), `examples/swarm-hook-guard.py` (`PreToolUse` model/quota guard), and `examples/README.md` with multi-account durability rules.

## Quick Usage

To run explicitly or override settings for one task:

> Use pilotfish (mode=hybrid, cross_pool=on, floor=10%): map the target files, present a phased plan, and verify the implementation.

To toggle on/off live without uninstalling, open **Pilotfish for Antigravity** in Antigravity Customizations.
