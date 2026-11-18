# Changelog

All notable changes to `pilotfish-agy` are documented in this file.
Versioning follows `<upstream-pilotfish-version>-agy.<port-revision>`.

## [1.5.0-agy.6] - 2026-11-18

### Added
- **Project override templates (`plugin/examples/`):**
  - `project-pilotfish.config.json`: ready-to-copy `.agents/pilotfish.config.json` template with `quotaFloorPercent: 15`, `protectModels: ["argon", "claude-opus"]`, `networkGuard`, and `autoResumeOnQuotaReset`.
  - `swarm-hook-guard.py`: `PreToolUse` hook template enforcing explicit `model` on `swarm(action="add")` and preventing lightweight/continuous workers from exhausting scarce quotas.
  - `README.md`: multi-account durability guidance (`Hydrogen`/`Neon` accounts vs. `3.8 Flash` + `Claude 4.6` accounts).
- **Discoverability:** indexed `examples/` in `plugin/README.md` and `plugin/skills/pilotfish/SKILL.md`.

## [1.5.0-agy.5] - 2026-11-18

### Added
- **Network Outage Protection, Auto-Checkpoint & Auto-Resume (`scripts/pilotfish-net-watchdog.py`):**
  - Ultra-fast zero-token connection probe (`--probe`, <50ms) to classify tool/subagent timeouts and network failures vs real code bugs.
  - Subagent and worker shielding: freezes state without burning retries or killing swarm workers when connectivity drops.
  - Auto-checkpoint artifact (`pilotfish-checkpoint.md`) with `status: PAUSED_NETWORK_OFFLINE`.
  - Local background watchdog (`--wait-for-online`) with hysteresis (3 consecutive stable probes) that exits cleanly when connection returns, triggering Antigravity's reactive task wakeup without wasting tokens.
  - Passive background sentinel (`--sentinel`) for long autonomous runs (`AUTO` mode), ensuring Antigravity reactively revives even if an in-flight API call dies during a sudden network drop.
  - Integration with `tg-notify` to alert the user on mobile upon connection restoration.
- **New configuration section `networkGuard` in `config.json`:**
  - `enabled`, `probeTimeoutSeconds`, `consecutiveSuccessesRequired`, `probeIntervalSeconds`, `sentinelEnabled`, and `endpoints`.
- **Policy Section 7 in `rules/AGENTS.md` and updated `skills/pilotfish/SKILL.md`:**
  - Formalized pre-flight triage, subagent shielding, checkpoint contract, and sentinel lifecycle.
- **CLI flag `--network-guard <on|off>` in `scripts/configure.sh`.**
- **Automated tests in `tests/test-plugin.sh` and validator guards in `scripts/validate.sh`.**

## [1.5.0-agy.4] - 2026-11-18

### Fixed
- **Bug #1 (`PreToolUse` hook relative path):** `plugin/hooks.json` no longer uses `./hooks/safety-guard.py` (which exited with code 2 when Antigravity executed the hook from the workspace CWD instead of the plugin directory). Now uses a portable `${ANTIGRAVITY_PLUGIN_ROOT:-${PLUGIN_ROOT:-$HOME/.gemini/config/plugins/pilotfish-agy}}/hooks/safety-guard.py` fallback, and `scripts/install.sh` rewrites `hooks.json` with the exact absolute installed path (`$TARGET_DIR/hooks/safety-guard.py`) for both `--global` and `--project` installs.
- **Bug #2 (`PreToolUse` pass-through protocol):** `plugin/hooks/safety-guard.py` now exits 0 with **empty stdout (0 bytes)** on normal calls, invalid stdin, and `safetyGuard.enabled: false`, instead of printing `{}` (which Antigravity interpreted as `deny` with an empty reason).

### Added
- **Regression tests & validator guards:** `scripts/validate.sh` now rejects relative `./hooks/` commands in `hooks.json`; `tests/test-plugin.sh` now verifies absolute-path rewriting in `install.sh`, executes the installed hook command via `sh -c` from an unrelated CWD, and asserts literal `""` stdout for all pass-through paths.

## [1.5.0-agy.3] - 2026-11-17

### Added
- **Deterministic safety guard hook (`hooks.json` + `hooks/safety-guard.py`):**
  - `deny` automático para chaves privadas/tokens hardcoded em writes e egress de secrets via `search_web`.
  - `deny` para comandos destrutivos catastróficos (`rm -rf /`, `mkfs`, `dd` em block device, fork bomb).
  - `force_ask` para arquivos sensíveis (`.env`, `*.pem`, `*.key`, `~/.ssh/id_*`, `config.local.ts`, `*.m3u*`).
  - `force_ask` para comandos de alto risco (`git push --force`, `git reset --hard`, `DROP TABLE`, `TRUNCATE`, `DELETE` sem WHERE, `rm -rf` amplo fora de build/tmp).
  - Pass-through (`{}`) para tudo mais — nunca enfraquece as permissões nativas do Antigravity.
  - Respeita override de projeto via `.agents/pilotfish.config.json` → `safetyGuard.enabled: false`.
  - Ignora placeholders (`example`, `dummy`, `your_`, etc.) e arquivos de teste/template.
- **Auto-checkpoint & auto-resume em exaustão de cota:**
  - Failover cross-pool automático (`crossPoolRouting: true`) antes de pausar.
  - Checkpoint artifact com estado, próximo passo e cota restante.
  - Timer `schedule(DurationSeconds=...)` para auto-wakeup quando a cota resetar.
  - Configurável via `autoResumeOnQuotaReset` e `resumeBufferSeconds` em `config.json`.
- **Novos campos em `config.json`:** `autoResumeOnQuotaReset`, `resumeBufferSeconds`, `safetyGuard` (com `enabled`, `blockHardcodedSecrets`, `blockSecretWebEgress`, `protectSensitiveFiles`, `confirmDestructiveCommands`).
- **Script `configure.sh`:** flags `--auto-resume` e `--safety-guard` adicionadas.
- **Testes expandidos:** 6 estágios, com assertions determinísticos para o safety-guard.py.

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
