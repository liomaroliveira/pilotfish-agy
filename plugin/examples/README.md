# Pilotfish Project Setup Examples

Ready-to-copy templates for configuring Pilotfish per workspace in `<workspace>/.agents/`.

## Files

1. **`project-pilotfish.config.json`** → copy to `<workspace>/.agents/pilotfish.config.json`
   - Enables `hybrid` routing with `crossPoolRouting: true` and `quotaFloorPercent: 15`.
   - Protects short-quota / high-cost models (`["argon", "claude-opus"]`) from routine worker dispatch.
   - Enables `networkGuard` (probe + background `--sentinel` / `--wait-for-online`) and `autoResumeOnQuotaReset`.
   - Distinguishes durable pools (`Gemini Hydrogen` / `3.8 Flash` / `GPT-OSS`) from short-lived pools (`Claude` inside Antigravity, `Argon`) so long autonomous sessions do not stall early.

2. **`swarm-hook-guard.py`** → wire into `<workspace>/.agents/hooks.json` (`PreToolUse`, `matcher: ".*"`)
   - Deterministically blocks `swarm(action="add")` when `model` is omitted (which would silently inherit the orchestrator's high-tier model).
   - Blocks `argon`, `claude-opus` on continuous workers, and `*-high`/`xhigh` on lightweight workers (`explore`, `measure`, `scribe`, `scout`).
   - Returns `{"decision": "deny", "reason": ...}` so the orchestrator self-corrects in the same turn without pausing the session.

## Multi-Account Adaptation Rule (for AI Agents)

Always run `swarm(action="models", all=true)` before delegating:
- **Account with Hydrogen/Neon:** use `gemini-4-hydrogen-medium` for code/analysis (`high` only for hard bugs) and `gemini-3.8-flash-low`/`medium` (or `gpt-oss-120b-medium` when Gemini `<= 15%`) for recon/mechanical workers.
- **Account without Hydrogen/Neon (e.g. only `3.8 Flash` + `Claude 4.6`):** use `gemini-3.8-flash-high` for scoped code workers and `3.8-flash-low`/`medium` for recon/mechanical; reserve Antigravity `Claude` (`4.6` / `5.5`) for 1–2 surgical reviews (`pf-verifier`, `pf-plan-verifier`) because its Antigravity quota depletes in a few prompts.
