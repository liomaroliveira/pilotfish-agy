#!/usr/bin/env python3
"""Example PreToolUse guard for Antigravity (.agents/hooks.json).

Enforces deterministic model & role routing on both `invoke_subagent` and `swarm(action="add")`:
1. Requires explicit `Model` on `invoke_subagent` (omitting `Model` defaults to `'inherit'`,
   silently burning the orchestrator's Argon/Opus quota on lightweight subagents).
2. Enforces project specialist precedence (`projectAgentPrecedence`, e.g. `explore` over `pf-scout`).
3. Blocks `Model="pro"` on Tier 1/Tier 2 subagents and blocks `swarm(action="add")` calls
   that omit `model` or assign protected/high-cost models (`argon`, `claude-opus`, `*-high`/`xhigh`)
   to routine workers (allowing `argon-low`/`medium` only when other pools are <= 15%).
Returns `{"decision": "deny", "reason": ...}` so the orchestrator self-corrects in the same turn.
"""
import json
import sys

LIGHT_ROLES = ("explore", "measure", "scribe", "scout")
CONTINUOUS_ROLES = ("explore", "measure", "scribe", "scout", "builder", "analyst", "pf-executor", "pf-mech-executor")


def deny(reason: str) -> None:
    print(json.dumps({"decision": "deny", "reason": reason}, ensure_ascii=False))
    sys.exit(0)


def check_invoke_subagent(payload: dict) -> None:
    call = payload.get("toolCall")
    if not isinstance(call, dict) or call.get("name") != "invoke_subagent":
        return
    args = call.get("args") or {}
    role = str(args.get("TypeName") or "").strip().lower()
    model = str(args.get("Model") or "").strip().lower()

    if role == "pf-scout":
        deny(
            "projectAgentPrecedence: use project specialist `TypeName='explore'` instead of `pf-scout` "
            "when available in `.agents/agents/`."
        )
    if not model:
        deny(
            "invoke_subagent without explicit `Model` defaults to `'inherit'` and silently inherits "
            "the orchestrator's Argon/Opus model. Pass explicit `Model`: `'flash_lite'` for Tier 1 "
            "(`explore`/`scribe`), `'flash'` for Tier 2 (`measure`/`builder`/`analyst`/`pf-executor`/"
            "`pf-mech-executor`/`browser`), or `'inherit'` for Tier 3 (`pf-plan-verifier`/`pf-verifier`)."
        )
    if role in LIGHT_ROLES and model in ("pro", "inherit"):
        deny(
            f"Light/mechanical subagent `{role}` must not use `Model='{model}'`. "
            "Use `Model='flash_lite'` or `Model='flash'`."
        )
    if role in ("builder", "analyst", "pf-executor", "pf-mech-executor") and model == "pro":
        deny(
            f"Execution subagent `{role}` must not use `Model='pro'` (drains scarce frontier quota). "
            "Use `Model='flash'` (or `swarm(action='add')` with `gemini-4-hydrogen-medium` / `gemini-3.8-flash-high`)."
        )


def check_swarm_add(payload: dict) -> None:
    call = payload.get("toolCall")
    if not isinstance(call, dict) or call.get("name") != "swarm":
        return
    args = call.get("args") or {}
    if args.get("action") != "add":
        return

    name = str(args.get("name") or "").strip().lower()
    model = str(args.get("model") or "").strip().lower()

    if not model:
        deny(
            "swarm(action='add') without explicit `model` inherits the orchestrator model. "
            "Pass a role-appropriate model (e.g. `gemini-3.8-flash-low` for explore/scribe, "
            "`gemini-3.8-flash-medium` or `gpt-oss-120b-medium` for measure, "
            "`gemini-4-hydrogen-medium` for builder/analyst)."
        )
    if "argon" in model:
        deny("`argon` is protected in protectModels (short weekly quota).")
    if "claude-opus" in model and name.startswith(CONTINUOUS_ROLES):
        deny(
            f"Worker `{name}` must not use `{model}` for continuous work "
            "(exhausts Antigravity Claude quota in a few prompts). "
            "Reserve `claude-opus` for surgical checks (`pf-verifier`, `pf-plan-verifier`)."
        )
    if "claude-sonnet" in model and name.startswith(LIGHT_ROLES):
        deny(
            f"Light worker `{name}` must not use `{model}`. "
            "Use `gemini-3.8-flash-low`/`medium` or `gpt-oss-120b-medium`."
        )
    if any(t in model for t in ("hydrogen-high", "hydrogen-xhigh", "neon-high", "neon-xhigh")) and name.startswith(LIGHT_ROLES):
        deny(
            f"Light worker `{name}` does not need `{model}`. "
            "Use `gemini-3.8-flash-low`/`medium` or `gpt-oss-120b-medium`."
        )


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    check_invoke_subagent(payload)
    check_swarm_add(payload)


if __name__ == "__main__":
    main()
