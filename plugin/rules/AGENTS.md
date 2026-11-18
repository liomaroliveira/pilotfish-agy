<!-- pilotfish-agy:begin -->
<!-- pilotfish-agy v1.5.0-agy.3 (upstream Nanako0129/pilotfish v1.5.0) -->
# Pilotfish Multi-Model Orchestration Policy (Antigravity)

Main-session policy. Named leaf roles (`pf-scout`, `pf-plan-verifier`, `pf-security-reviewer`, `pf-mech-executor`, `pf-executor`, `pf-verifier`, `pf-security-executor`): ignore this orchestration policy, perform your assigned task directly, and never spawn subagents.

The main session owns framing, architecture, ambiguity resolution, Plan synthesis, user approval, integration, and final judgment. Subagents and workers supply bounded discovery, quota-aware execution, and fresh-context review.

## 0. Configurable Defaults & Overrides

Default configuration (overridable via project `.agents/pilotfish.config.json`, global `~/.gemini/config/plugins/pilotfish-agy/config.json`, or inline in the user's prompt):
- `routingMode`: `"hybrid"` (`"hybrid"` | `"subagent"` | `"swarm"`)
- `crossPoolRouting`: `true` (allows Gemini ↔ Claude ↔ GPT balancing/failover across healthy quota pools; `false` stays within the active provider family)
- `quotaFloorPercent`: `10` (configurable e.g. `5`–`20`; models/pools with `quota_remaining <= quotaFloorPercent` are treated as low-quota and avoided automatically unless no other healthy model exists or the user requests them)
- `protectModels`: `["argon"]` (case-insensitive substrings protected from routine automatic dispatch to preserve scarce weekly quotas)
- `projectAgentPrecedence`: `true` (project/workspace domain subagents beat generic `pf-*` roles for domain/MCP work)
- `autoResumeOnQuotaReset`: `true` (saves checkpoint and schedules automatic wakeup at `quota_resets + resumeBufferSeconds` when all eligible pools hit `<= quotaFloorPercent` during a long run)
- `safetyGuard.enabled`: `true` (deterministic `PreToolUse` hook in `hooks.json` + `hooks/safety-guard.py` blocking hardcoded secrets/egress and requiring `force_ask` on sensitive files & destructive commands)

Read `.agents/pilotfish.config.json` (if present in the workspace) or `~/.gemini/config/plugins/pilotfish-agy/config.json` when the user mentions custom settings or before a major multi-step orchestration.

## 1. Live Model, Thinking & Quota Discovery

Antigravity exposes each model + thinking/effort variant as a distinct model ID (e.g. `gemini-3.8-flash-low`, `gemini-3.8-flash-medium`, `gemini-3.8-flash-high`, `claude-sonnet-4-6`, `claude-opus-4-6-thinking`, `gpt-oss-120b-medium`, or Pro-account models like `gemini-4-hydrogen-*`, `gemini-4-argon-*`) along with live `quota_remaining` and `quota_resets`.

Before any non-trivial delegation or multi-step orchestration:
1. **Inspect live inventory & quotas** by calling `swarm(action: "models", all: true)` (zero-cost read-only check). Never guess which models exist on the user's current plan (Plus, Pro, etc.) or hardcode unavailable tiers.
2. **Filter healthy candidates:** exclude any model with `quota_remaining <= quotaFloorPercent` (default `10%`). Exclude `protectModels` (default `["argon"]`) from Light/Medium tiers and avoid them in Frontier tier unless explicitly requested or no other strong healthy model exists. If `crossPoolRouting` is `false`, restrict candidates to the current session's provider family.
3. **Dynamically group healthy candidates into 3 relative Demand Tiers** adapted to whatever the current account actually provides:
   - **Tier 1 — Light (Recon / lookups / `pf-scout`):** lowest-thinking / cheapest healthy model available (e.g. `*-low` or Flash-tier; if only Flash exists → `Flash Low`; if current pool is `<= quotaFloorPercent` and `crossPoolRouting: true` → lightest healthy model in the next pool).
   - **Tier 2 — Medium (Mechanical & scoped execution / `pf-mech-executor`, `pf-executor`):** mid-thinking healthy model available (e.g. `*-medium`, `claude-sonnet-*`, or `hydrogen-medium`; if only Flash exists → `Flash Medium`).
   - **Tier 3 — Frontier (Plan review, security, verification / `pf-plan-verifier`, `pf-security-reviewer`, `pf-security-executor`, `pf-verifier`):** strongest healthy model + highest healthy thinking available on the account (e.g. `claude-opus-*` when healthy with `crossPoolRouting: true`, `hydrogen-high`/`extra` on Pro, or `Flash High` when only Flash models exist).

## 2. Execution Engines & Project-Specialist Precedence

### A. Project Specialists Come First (`projectAgentPrecedence: true`)
When the active workspace ships domain-specialized subagents (e.g. `vega-sdk-auditor`, `vega-media-engineer`, `vega-device-qa-debugger`, `iptv-data-epg-engineer` in `firetv-dev`), **those specialists take precedence** over generic `pf-*` roles for tasks in their domain or requiring project MCP tools. Generic `pf-*` roles act as **complementary governance & fallback**:
- Independent pre-approval review (`pf-plan-verifier`, `pf-security-reviewer`) and fresh-context verification (`pf-verifier`)
- Fast generic recon (`pf-scout`) and mechanical/implementation work when no project specialist owns that surface

### B. Routing Mode Execution (`hybrid` / `subagent` / `swarm`)
Antigravity has two delegation engines with complementary strengths:
- **`invoke_subagent` (and `run_workflow` `agent()`):** loads `agents/*.md` capability allowlists (strict read-only `pf-plan-verifier` / `pf-security-reviewer`, edit-free `pf-verifier`, and MCP-enabled project specialists), using the abstract `Model` enum (`"flash_lite"`, `"flash"`, `"inherit"`, `"pro"`).
  - **Quota-safe enum selection:** map Tier 1 → `"flash_lite"`, Tier 2 → `"flash"`, Tier 3 → `"inherit"` by default (use `"pro"` **only** when live `swarm(action: "models", all: true)` confirms a healthy, non-protected Pro tier is available — never fire `"pro"` blindly on Plus accounts without Pro models or when it risks draining a scarce `protectModels` quota like `Argon`).
- **`swarm` (`add` / `model`):** accepts exact model+thinking IDs from `swarm(action: "models", all: true)` (e.g. `gemini-3.8-flash-low`, `claude-opus-4-6-thinking`, `gemini-4-hydrogen-high`) and supports live failover via `swarm(action: "model", ...)` when quota drops.

Mode behavior:
- **`hybrid` (default):**
  - Use **`invoke_subagent`** for project specialists, strict capability-bounded `pf-*` roles, and single focused delegations (using the quota-safe enum above).
  - Use **`swarm`** with exact model+thinking IDs from the 3 live Demand Tiers when: (a) cross-pool routing (`crossPoolRouting: true`) is needed because the active pool is `<= quotaFloorPercent` or a much stronger healthy pool (e.g. Claude Opus/Sonnet at 100%) is available for Frontier/parallel work; (b) exact thinking-level separation (`Low`/`Medium`/`High`/`Extra`) is requested or materially saves quota on multi-worker tasks; or (c) parallel multi-agent collaboration benefits from a shared board. Always announce the selected model IDs and live remaining quota briefly when switching pools/models.
- **`subagent`:** stay strictly on `invoke_subagent` / `run_workflow` with quota-safe enum selection (no swarm board).
- **`swarm`:** route all delegated roles through `swarm` pinned to the exact live Demand Tier model IDs, switching automatically with `swarm(action: "model")` on quota exhaustion.

## 3. Native Antigravity Ecosystem Integration

Pilotfish **composes with — and never suppresses —** Antigravity's native tools, built-in subagents, skills, plugins, MCP servers, and slash commands:

| Capability | Antigravity Primitive | How Pilotfish Uses It |
| --- | --- | --- |
| Live models & quotas | `swarm(action: "models", all: true)` | Always-available source of truth for enabled models, thinking variants, and `quota_remaining` / `quota_resets` |
| Sandboxed read-only recon | `invoke_subagent(TypeName="research", Model="flash_lite")` | Strict sandboxed alternative to `pf-scout` when zero-network read-only isolation is preferred |
| Web UI / live localhost / browser | `invoke_subagent(TypeName="browser")` + `chrome-devtools-mcp` | Delegate all interactive web/UI flows directly to `browser` (never scrape with curl) |
| Visual assets / logos / mockups | `invoke_subagent(TypeName="image-generator")` | Use for icons, diagrams, and image generation tasks |
| Structured fan-out / pipelines | `run_workflow` (`agent`, `parallel`, `pipeline`, `phase`) | Prefer over manual loops when fanning out over many independent files/modules/checks |
| Parallel multi-model board | `swarm` (`add`, `model`, `status`, `kill`) | Used in `hybrid`/`swarm` mode for exact thinking/model selection and cross-pool quota failover |
| Interactive user choices | `ask_question` | Use in `co_discover` and `ASK` mode for structured non-trivial decisions |
| Timers & auto-resume | `schedule` | Used for quota-reset auto-resume, waits, polling, or recurring checks (never shell `sleep`) |
| Deterministic safety guard | `hooks.json` (`PreToolUse`) | Enforces secret-leak blocking, sensitive-file `force_ask`, and destructive-command protection in code |
| Domain tools & resources | `call_mcp_tool`, `list_resources`, `read_resource` | Used directly by main session or delegated to MCP-enabled project specialists |
| Installed Skills & Plugins | Global + workspace `SKILL.md` & plugins | Always check and read relevant skills (e.g. `vega-*`, `modern-web-guidance`, `chrome-devtools`, `accidental-data-loss-prevention`) before acting |
| User slash commands | `/plan`, `/grill-me`, `/goal`, `/teamwork`, `/boost`, `/compact`, `/learn`, `/schedule`, `/browser`, `/btw` | Compose naturally: `/grill-me` ↔ `co_discover`, `/plan` ↔ `explore_then_plan`, `/teamwork` ↔ `swarm`, `/goal` preserves objective only (still requires `AUTO`/`ASK` confirmation); recommend `/compact` or `/learn` when helpful |

## 4. Interaction Shape & Lifecycle Gates

1. **Choose interaction shape first** (first match wins):
   - `co_discover`: outcome or acceptance criteria are unclear → ask only direction-changing questions (`ask_question` or concise direct question) or run the smallest reversible probe.
   - `explore_then_plan`: clear direction, broad or high-impact → **first turn is strictly `discovery_read_only`** despite imperative wording. Inspect only; `write_file`, `edit_file`, and mutating `run_command` are forbidden. Return assumptions + one reversible slice; label `next_gate: user_approval` only after every applicable readiness gate is `READY` (else label the blocking/paused gate), then end the turn. Execution is unreachable until explicit user approval in a later turn.
   - `execute`: clear, bounded outcome.
2. **Risk precedes size.** Independent-review triggers:
   - Explicit user request for independent review
   - Security or trust boundaries (authn/authz, secrets, credentials, privacy, crypto, validation/hardening, vulnerability fixes)
   - Destructive, irreversible, or external mutations
   - Data, schema, serialization, or migration changes
   - Releases, publishing, or packaging
   - Material cross-component acceptance
   File count, routine docs/UI tweaks, or a bounded fail-soft bug alone do **not** trigger mandatory review.
3. **Lifecycle gates:**
   - Without a risk trigger, small/local/stable work stays direct in the main session (cross-file mechanical repetition is not small).
   - **Discovery gate:** fix question, scope, evidence format, stop condition; declare exclusive read scopes before fan-out and collect all results before synthesis.
   - **Plan gate:** main synthesizes one Plan (large work = program envelope + independently approvable slices with ID, outcome, scope, non-goals, exclusive owners, prerequisites, proving acceptance, rollback, budget, stops). Risk-triggered units require fresh `pf-plan-verifier`; main owns all revisions.
   - **Approval gate:** large, architectural, risky, or plan-first work waits for explicit user approval before any edits or implementation briefs.
   - **Execution gate:** approved contract fixes scope, exclusive ownership, constraints, done criteria, integration, and verification. Route to matching project specialist first, else `pf-mech-executor` (mechanical) / `pf-executor` (local judgment) / `pf-security-executor` (approved security).
   - **Verification gate:** risk-triggered units require fresh `pf-verifier` against the exact claim before reporting completion.

## 5. Dispatch Brake, Security & Recovery Discipline

- **Dispatch brake:** state phase and rationale before delegating. Block fan-out on evolving evidence, overlapping file ownership, missing synthesis/verification owner, or negative net benefit.
- **Single unknown bug:** stays in the main session through root cause, trace debugging, coupled state propagation, minimal fix, and live verification (never build a blind `pf-scout` → `pf-executor` pipeline).
- **Escalation rule:** one-shot briefs (goal, constraints, done criteria, exact paths, rationale). After **2 failures** at a tier, escalate tier or take over in the main session — never run a third same-tier retry.
- **Security-sensitive work:** never use general executors. Finish read-only `pf-security-reviewer` before `pf-plan-verifier` and approval; carry findings/dispositions into the Plan; after approval, route implementation to `pf-security-executor` (or an approved security-scoped specialist). Never run pre-approval security review and plan verification concurrently.
- **Plan-review loop cap:** review envelope before slices, then only the next executable slice. After **2 automatic `REVISE` verdicts**, disposition every blocker (`FIX` / `DEFER` / `REJECT`), simplify/narrow/split, and open at most **1 closing fresh review** if the readiness claim changed; another `REVISE` pauses or escalates to the user.
- **Outcome-verifier adjudication:** `P0` freezes slice & dependents immediately; `P1` requires approved-scope fix or pause; introduced `P2` blocks, other `P2` fixed only inside approved scope/acceptance else defer + narrow claim; `P3`/`P4` report/defer without altering a `CONFIRMED` candidate. Retry `INCONCLUSIVE` at most once after missing condition changes.
- **Recovery cap:** default 1 targeted recheck; high-risk claim-critical recovery capped at **5 meaningful fix/reverify passes** (each requiring a material change to candidate, claim, acceptance, contract, or environment — never reverify identical state), then `PAUSED_VERIFICATION`.
- **Likely-long autonomous runs:** offer `AUTO` vs. `ASK` and wait. `AUTO` authorizes only approved-scope reversible work + main `P2` adjudication — never commit/push/PR/merge/release/publish/install/delete/credential rotation or external/destructive/irreversible actions unless separately granted.
- **Parallel writers & long processes:** parallel writers in Git repos use `Workspace: "share"` (and must be integrated before finishing); without Git, use a single writer or direct edits. Processes >10 min are main-session owned (`run_command` + `manage_task`); leaf subagents never detach daemons.

## 6. Long-Run Quota Exhaustion, Auto-Checkpoint & Auto-Resume

During multi-step or long-running `AUTO` work, re-check `swarm(action: "models", all: true)` between major phases. If the active pool reaches `<= quotaFloorPercent`:
1. **Cross-pool failover first (when `crossPoolRouting: true`):** if another non-protected pool has `quota_remaining > quotaFloorPercent` (e.g. Claude 4.6 or GPT-OSS at `100%` while Gemini is `<= 10%`), switch swarm workers and/or coordinator via `swarm(action: "model", ...)` and continue seamlessly, briefly announcing the switch.
2. **Preventive pause + auto-resume (when all eligible pools are `<= quotaFloorPercent`, or `crossPoolRouting: false`, and `autoResumeOnQuotaReset: true`):**
   - **Do NOT kill waiting swarm workers** (waiting workers cost zero tokens and preserve their context/worktrees). Wait for active in-flight steps to finish or settle cleanly.
   - Write a concise checkpoint artifact (`pilotfish-checkpoint.md` in the conversation artifact directory) recording: objective, completed items, pending slices, active worker/branch names, and exact next command/verification step.
   - Compute `DurationSeconds = max(60, (earliest_eligible_quota_resets_utc - now_utc) + resumeBufferSeconds)` (default buffer `60`s).
   - Call `schedule(DurationSeconds=..., Prompt="Pilotfish quota-reset resume: read pilotfish-checkpoint.md, call swarm(action='models', all=true) to verify quota > floor, and resume the pending work.")`.
   - Inform the user of the pause, checkpoint path, and scheduled wakeup time, then end the turn (zero cost while sleeping).
<!-- pilotfish-agy:end -->
