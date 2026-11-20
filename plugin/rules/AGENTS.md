<!-- pilotfish-agy:begin -->
<!-- pilotfish-agy v1.5.0-agy.7 (upstream Nanako0129/pilotfish v1.5.0) -->
# Pilotfish Multi-Model Orchestration Policy (Antigravity)

Main-session policy. Leaf roles (`pf-scout`, `pf-plan-verifier`, `pf-security-reviewer`, `pf-mech-executor`, `pf-executor`, `pf-verifier`, `pf-security-executor`): ignore this policy, execute your assigned task directly, and never spawn subagents.

The main session owns framing, architecture, ambiguity resolution, Plan synthesis, user approval, integration, and final judgment. Subagents and workers supply bounded discovery, quota-aware execution, and fresh-context review.

## 0. Configurable Defaults & Overrides

Overridable via project `.agents/pilotfish.config.json`, global `~/.gemini/config/plugins/pilotfish-agy/config.json`, or inline user prompt:
- `routingMode`: `"hybrid"` (`"hybrid"` | `"subagent"` | `"swarm"`)
- `crossPoolRouting`: `true` (Gemini ↔ Claude ↔ GPT balancing/failover across healthy quota pools)
- `quotaFloorPercent`: `10` (configurable `5`–`20`; models with `quota_remaining <= quotaFloorPercent` are avoided unless no other healthy model exists)
- `protectModels`: `["argon"]` (substrings protected from routine dispatch to preserve scarce weekly quotas)
- `projectAgentPrecedence`: `true` (workspace domain subagents in `.agents/agents/` beat generic `pf-*` roles)
- `autoResumeOnQuotaReset`: `true` (checkpoints and schedules wakeup at `quota_resets + resumeBufferSeconds`)
- `networkGuard.enabled`: `true` (zero-token TCP probe & sentinel via `scripts/pilotfish-net-watchdog.py`)
- `safetyGuard.enabled`: `true` (`PreToolUse` hook in `hooks.json` + `hooks/safety-guard.py`)

## 1. Live Model, Thinking & Quota Discovery

Before any non-trivial delegation or multi-step orchestration:
1. **Inspect live inventory & quotas:** call `swarm(action: "models", all: true)` (zero-cost read-only check). Never guess available models or quotas.
2. **Filter healthy candidates:** exclude models with `quota_remaining <= quotaFloorPercent`. Exclude `protectModels` (e.g. `argon`) from Light/Medium tiers and reserve them in Frontier tier only when no other strong healthy model exists.
3. **Group healthy candidates into 3 Demand Tiers:**
   - **Tier 1 — Light (Recon / lookups / `pf-scout` / project `explore` or `scribe`):** cheapest healthy model (`*-low`, `flash_lite`, or `gpt-oss-120b-medium` when Gemini `<= quotaFloorPercent`).
   - **Tier 2 — Medium (Mechanical & scoped execution / `pf-mech-executor`, `pf-executor`, project `measure`/`builder`/`analyst`):** mid-thinking healthy model (`*-medium`, `flash`, `hydrogen-medium`, or `flash-high`).
   - **Tier 3 — Frontier (Plan review, security, verification / `pf-plan-verifier`, `pf-security-reviewer`, `pf-security-executor`, `pf-verifier`):** strongest healthy model (`hydrogen-high`, `claude-sonnet-*`, or 1 surgical shot of `claude-opus-*`).

## 2. Execution Engines & Project-Specialist Precedence

### A. Project Specialists Come First (`projectAgentPrecedence: true`)
Workspace subagents in `.agents/agents/` (e.g. `explore`, `measure`, `analyst`, `builder`, `scribe`, or `vega-*` / `iptv-*`) **take precedence** over generic `pf-*` roles for domain work. Generic `pf-*` roles provide complementary pre-approval review (`pf-plan-verifier`, `pf-security-reviewer`), fresh-context verification (`pf-verifier`), and fallback execution (`pf-mech-executor`, `pf-executor`).

### B. Deterministic Routing (`hybrid` / `subagent` / `swarm`)
- **`invoke_subagent` (and `run_workflow` `agent()`):** enforces `agents/*.md` tool allowlists.
  - **Mandatory explicit `Model`:** ALWAYS pass an explicit `Model` parameter (`"flash_lite"`, `"flash"`, `"inherit"`, `"pro"`). Never omit `Model` on Tier 1/Tier 2 subagents: the default is `"inherit"`, which silently inherits the orchestrator's expensive `Argon`/`Opus` model! Map Tier 1 → `"flash_lite"`, Tier 2 → `"flash"`, Tier 3 → `"inherit"` (use `"pro"` only when live `swarm(action: "models", all: true)` confirms a non-protected Pro pool is healthy).
- **`swarm` (`add` / `model`):** pins exact model+thinking IDs from `swarm(action: "models", all: true)` (e.g. `gemini-3.8-flash-low`, `gemini-4-hydrogen-medium`, `gpt-oss-120b-medium`) and supports live failover via `swarm(action: "model", ...)`. Always pass explicit `model` on `swarm(action: "add")`.

## 3. Native Antigravity Ecosystem Integration

| Capability | Antigravity Primitive | Pilotfish Usage |
| --- | --- | --- |
| Live models & quotas | `swarm(action: "models", all: true)` | Source of truth for enabled models, thinking variants, and `quota_remaining` / `quota_resets` |
| Sandboxed read-only recon | `invoke_subagent(TypeName="research", Model="flash_lite")` | Zero-network sandboxed alternative when project `explore` is not present |
| Web UI / localhost / browser | `invoke_subagent(TypeName="browser", Model="flash")` | Delegate all interactive web/UI flows directly to `browser` |
| Visual assets / diagrams | `invoke_subagent(TypeName="image-generator", Model="flash")` | Icons, diagrams, and image generation |
| Structured fan-out / pipelines | `run_workflow` (`agent`, `parallel`, `pipeline`, `phase`) | Multi-file/module parallel fan-out and staged pipelines |
| Parallel multi-model board | `swarm` (`add`, `model`, `status`, `kill`) | Exact thinking/model selection and cross-pool quota failover |
| Interactive user choices | `ask_question` | Structured decisions in `co_discover` and `ASK` mode |
| Timers & auto-resume | `schedule` | Quota-reset auto-resume and timers (never shell `sleep`) |
| Deterministic safety guard | `hooks.json` (`PreToolUse`) | Secret-leak blocking, sensitive-file `force_ask`, and destructive-command protection |

## 4. Interaction Shape & Lifecycle Gates

1. **Choose interaction shape first:**
   - `co_discover`: unclear criteria → ask direction-changing questions (`ask_question`) or run smallest reversible probe.
   - `explore_then_plan` (`/plan`): broad or high-impact → **first turn is strictly `discovery_read_only`** (`write_file`, `edit_file`, and mutating `run_command` forbidden). Synthesize Plan artifact and wait for explicit user approval.
   - `execute`: clear, bounded outcome.
2. **Independent-review triggers (Risk precedes size):** explicit user request; security/trust boundaries (authn/authz, secrets, crypto, validation); destructive/irreversible/external mutations; data/schema/migration changes; releases/packaging; material cross-component acceptance.
3. **Lifecycle gates:**
   - **Discovery gate:** fix question, scope, evidence format, stop condition; declare exclusive read scopes before fan-out.
   - **Plan gate:** main synthesizes one Plan. Risk-triggered units require fresh `pf-plan-verifier`.
   - **Approval gate:** wait for explicit user approval before edits on plan-first or high-impact work.
   - **Execution gate:** route to matching project specialist first, else `pf-mech-executor` / `pf-executor` / `pf-security-executor` with explicit `Model`.
   - **Verification gate:** risk-triggered units require fresh `pf-verifier` (`CONFIRMED` / `REFUTED` / `INCONCLUSIVE`).

## 5. Dispatch Brake, Security & Recovery Discipline

- **Dispatch brake:** state phase and rationale before delegating; block fan-out on overlapping file ownership or negative net benefit.
- **Single unknown bug:** keep root-cause trace debugging and minimal fix in the main session.
- **Escalation rule:** one-shot briefs (goal, constraints, done criteria, exact paths). After **2 failures** at a tier, escalate tier or take over in the main session.
- **Security-sensitive work:** run read-only `pf-security-reviewer` before `pf-plan-verifier` and approval; route approved implementation to `pf-security-executor`.
- **Plan-review & recovery caps:** max 2 automatic `REVISE` passes before dispositioning blockers (`FIX`/`DEFER`/`REJECT`); outcome recovery capped at 5 meaningful fix/reverify passes, then `PAUSED_VERIFICATION`.
- **Parallel writers & long processes:** parallel writers in Git repos use `Workspace: "share"`; processes >10 min are main-session owned (`run_command` + `manage_task`); leaf subagents never detach daemons.

## 6. Long-Run Quota Exhaustion, Auto-Checkpoint & Auto-Resume

Re-check `swarm(action: "models", all: true)` between major phases. If the active pool reaches `<= quotaFloorPercent`:
1. **Cross-pool failover first (`crossPoolRouting: true`):** switch workers/coordinator to a healthy non-protected pool via `swarm(action: "model", ...)`. If all non-protected pools are `<= quotaFloorPercent`, low/medium variants of `protectModels` may be used only as a last-resort survival fallback.
2. **Preventive pause + auto-resume (`autoResumeOnQuotaReset: true`):**
   - Do **not** kill waiting swarm workers (zero token cost while waiting).
   - Write `<Artifact Directory Path>/pilotfish-checkpoint.md` (objective, completed items, pending slices, active workers, next step).
   - Compute `DurationSeconds = max(60, (earliest_eligible_quota_resets_utc - now_utc) + resumeBufferSeconds)` and call `schedule(DurationSeconds=..., Prompt="Pilotfish quota-reset resume: read pilotfish-checkpoint.md, verify quota via swarm(action='models', all=true), and resume.")`.

## 7. Network Outage Protection, Auto-Checkpoint & Auto-Resume

1. **Fast Pre-Flight & Timeout Triage:** on tool/API timeout (`ETIMEDOUT`, `ECONNREFUSED`, `ENOTFOUND`, `FetchError`), run `python3 ~/.gemini/config/plugins/pilotfish-agy/scripts/pilotfish-net-watchdog.py --probe` (<50ms). If offline, never retry subagents or burn failure counts.
2. **State Freeze & Reactive Sleep:** do not kill waiting workers; write `pilotfish-checkpoint.md` (`status: PAUSED_NETWORK_OFFLINE`); launch background task:
   `run_command(CommandLine="python3 ~/.gemini/config/plugins/pilotfish-agy/scripts/pilotfish-net-watchdog.py --wait-for-online --checkpoint '<Artifact Directory Path>/pilotfish-checkpoint.md'", WaitMsBeforeAsync=500, toolSummary="Network outage watchdog waiting for restoration")`
   and end the turn immediately (0 tokens while offline).
3. **Reactive Wakeup & Sentinel:** when connectivity returns (3 stable probes), `pilotfish-net-watchdog.py` exits 0, waking Antigravity to verify `swarm(action: "models", all: true)`, send `tg-notify`, and resume. During long `AUTO` runs, detach `--sentinel` and terminate it via `manage_task(Action="kill", TaskId=...)` upon completion.
<!-- pilotfish-agy:end -->
