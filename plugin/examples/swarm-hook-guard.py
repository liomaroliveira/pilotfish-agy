#!/usr/bin/env python3
"""Example PreToolUse guard for Antigravity (.agents/hooks.json).

Blocks `swarm(action="add")` calls that omit an explicit `model`, or that assign
short-quota / high-cost models (`argon`, `claude-opus`, `*-high`/`xhigh`) to
routine or lightweight workers. Returns `{"decision": "deny", "reason": ...}`
so the orchestrator self-corrects in the same turn without pausing the session.
"""
import json
import sys

LIGHT_ROLES = ("explore", "measure", "scribe", "scout")
CONTINUOUS_ROLES = ("explore", "measure", "scribe", "scout", "builder", "analyst")


def deny(reason: str) -> None:
    print(json.dumps({"decision": "deny", "reason": reason}, ensure_ascii=False))
    sys.exit(0)


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
    check_swarm_add(payload)


if __name__ == "__main__":
    main()
