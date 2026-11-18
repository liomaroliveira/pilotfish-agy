# Changelog

All notable changes to `pilotfish-agy` are documented in this file.
Versioning follows `<upstream-pilotfish-version>-agy.<port-revision>`.

## [1.5.0-agy.2] - 2026-11-17

### Added
- **Live model + thinking + quota discovery:** uses Antigravity's native `swarm(action="models", all=true)` before non-trivial delegation to inspect enabled models, thinking/effort variants (`-low`, `-medium`, `-high`, `-extra`, `-thinking`), and live `quota_remaining` / `quota_resets`.
- **Adaptive 3-tier Demand Grouping:** dynamically groups whatever healthy models exist on the active account (Plus, Pro, Flash-only, Gemini 4 Hydrogen/Argon, Claude 4.6, GPT-OSS) into Light / Medium / Frontier tiers.
- **Configurable settings (`plugin/config.json`, `.agents/pilotfish.config.json`, `scripts/configure.sh`):**
  - `routingMode`: `"hybrid"` (default) | `"subagent"` | `"swarm"`
  - `crossPoolRouting`: `true` (default; Gemini ↔ Claude ↔ GPT balancing/failover)
  - `quotaFloorPercent`: `10` (default; configurable e.g. `5`, `10`, `15`, `20`)
  - `protectModels`: `["argon"]` (default; protects scarce weekly quotas from routine dispatch)
  - `projectAgentPrecedence`: `true` (default)
- **Project-specialist precedence:** workspace domain subagents (e.g. `vega-*`, `iptv-*` in `firetv-dev`) beat generic `pf-*` roles for domain/MCP work; `pf-*` act as complementary governance, verification, and fallback roles.
- **Explicit native Antigravity ecosystem integration:** wires `research`, `browser`, `image-generator`, `run_workflow`, `swarm`, `ask_question`, `schedule`, MCP tools, global/workspace skills, plugins, and slash command composition into `rules/AGENTS.md` and `skills/pilotfish/SKILL.md`.

## [1.5.0-agy.1] - 2026-11-17

### Added
- Initial Antigravity native plugin port of [Nanako0129/pilotfish](https://github.com/Nanako0129/pilotfish) `v1.5.0`.
- 7 collision-safe leaf subagents (`pf-scout`, `pf-mech-executor`, `pf-executor`, `pf-plan-verifier`, `pf-security-reviewer`, `pf-security-executor`, `pf-verifier`).
- Always-on policy (`plugin/rules/AGENTS.md`), skill (`plugin/skills/pilotfish/SKILL.md`), logo, and portable build/test/release/install toolchain.
