---
name: pilotfish
description: >-
  Run, configure, or audit a task using Pilotfish for Antigravity: inspect live
  models, thinking variants, and quotas via swarm(action="models", all=true),
  group available models into 3 adaptive Demand Tiers (hybrid Gemini/Claude/GPT
  cross-pool routing with configurable quota floor), prioritize project
  specialists, leverage all native Antigravity tools/skills/MCPs, and enforce
  pre-approval plan review and fresh-context verification.
---

# Pilotfish Orchestration Playbook (Antigravity)

Use this skill when the user explicitly asks to "use pilotfish", wants to inspect or adjust Pilotfish routing/quota settings, or wants a structured multi-model workflow with live quota awareness.

## Step 1: Load Config & Live Quota Inventory

1. Check active settings (precedence: inline user override → `<workspace>/.agents/pilotfish.config.json` → `~/.gemini/config/plugins/pilotfish-agy/config.json` → defaults):
   - `routingMode`: `"hybrid"` *(default)* | `"subagent"` | `"swarm"`
   - `crossPoolRouting`: `true` *(default; enables Gemini ↔ Claude ↔ GPT balancing)*
   - `quotaFloorPercent`: `10` *(default; configurable e.g. `5`, `10`, `15`, `20`)*
   - `protectModels`: `["argon"]` *(default; protected from routine dispatch)*
   - `projectAgentPrecedence`: `true` *(default)*
2. Call `swarm(action: "models", all: true)` once (zero worker cost) to get:
   - Enabled model IDs including thinking variants (`-low`, `-medium`, `-high`, `-extra`, `-thinking`)
   - Live `quota_remaining` and `quota_resets` for every model

## Step 2: Build 3 Relative Demand Tiers (Account-Adaptive)

Filter out models with `quota_remaining <= quotaFloorPercent` and protect `protectModels` from routine tiers (respecting `crossPoolRouting`):

- **Tier 1 — Light (Recon / lookups):** lightest healthy model+thinking available (e.g., `gemini-3.8-flash-low`, `gemini-4-hydrogen-low`, or lightest model in another healthy pool when the current pool is at/below floor).
- **Tier 2 — Medium (Mechanical & scoped edits):** mid-tier healthy model+thinking (e.g., `gemini-3.8-flash-medium`, `claude-sonnet-4-6`, `gemini-4-hydrogen-medium`).
- **Tier 3 — Frontier (Plan review, security, verification):** strongest healthy model+thinking available (e.g., `claude-opus-4-6-thinking` when cross-pool is on and healthy, `gemini-4-hydrogen-high`/`extra` on Pro, or `gemini-3.8-flash-high` on Flash-only accounts).

## Step 3: Classify Shape, Risk & Specialists

1. **Interaction Shape:** `co_discover` (unclear → `ask_question`) | `explore_then_plan` (broad/high-impact → read-only first turn, wait for approval) | `execute` (clear & bounded).
2. **Risk Triggers:** explicit review request, security/trust boundaries, destructive/irreversible/external mutation, schema/migration, release/packaging, material cross-component acceptance.
3. **Check Project Specialists & Installed Skills FIRST:**
   - If the workspace has domain subagents (e.g., `vega-*`, `iptv-*` in `firetv-dev`) or domain skills/MCPs, prioritize them for domain work while keeping Pilotfish gates.
   - Use native Antigravity tools where they excel: `browser` for live web UI, `research` for strict sandboxed read-only recon, `image-generator` for visual assets, `run_workflow` for multi-item fan-out, `schedule` for timers/crons, `ask_question` for design alignment.

## Step 4: Execute According to `routingMode`

| Phase | Preferred Role | `invoke_subagent` Model Enum (quota-safe) | `swarm` Model ID (when exact thinking / cross-pool needed) |
| --- | --- | --- | --- |
| Recon | Project auditor OR `pf-scout` / `research` | `"flash_lite"` | Tier 1 exact ID |
| Mechanical edits | Project specialist OR `pf-mech-executor` | `"flash"` | Tier 2 exact ID |
| Scoped feature/fix | Project specialist OR `pf-executor` | `"flash"` | Tier 2 exact ID |
| Pre-approval security | `pf-security-reviewer` | `"inherit"` (or `"pro"` only if safe) | Tier 3 exact ID |
| Pre-approval plan gate | `pf-plan-verifier` | `"inherit"` (or `"pro"` only if safe) | Tier 3 exact ID |
| Security implementation | `pf-security-executor` | `"inherit"` (or `"pro"` only if safe) | Tier 3 exact ID |
| Fresh verification | `pf-verifier` | `"inherit"` (or `"pro"` only if safe) | Tier 3 exact ID |

- In **`hybrid`** mode (default): use `invoke_subagent` for project specialists and capability-bounded `pf-*` roles; switch to `swarm` with exact Tier 1/2/3 IDs when cross-pool balancing (`Gemini ↔ Claude`) or exact thinking-level separation (`Low`/`Medium`/`High`/`Extra`) is needed, or when active pool quota hits `<= quotaFloorPercent`.
- Always state chosen models + live quota snapshot briefly when switching pools/models.

## Step 5: Verify & Synthesize

- Integrate any `Workspace: "share"` branches before completing.
- Disposition `pf-verifier` findings explicitly (`FIX` / `DEFER` / `REJECT`).
- Report outcomes, verification evidence, active routing/quota decisions, and any deferred/paused items.
