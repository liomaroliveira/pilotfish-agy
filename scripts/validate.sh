#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="${1:-$ROOT_DIR/plugin}"
VERSION_FILE="$ROOT_DIR/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "FAIL: Missing VERSION file at $VERSION_FILE" >&2
  exit 1
fi

EXPECTED_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ -z "$EXPECTED_VERSION" ]]; then
  echo "FAIL: VERSION file is empty" >&2
  exit 1
fi

python3 - "$PLUGIN_DIR" "$EXPECTED_VERSION" <<'PY'
import ast
import json
import os
import re
import sys

plugin_dir = sys.argv[1]
expected_version = sys.argv[2]
errors = []

def err(msg):
    errors.append(msg)

# 1. Manifest validation
manifest_path = os.path.join(plugin_dir, "plugin.json")
if not os.path.isfile(manifest_path):
    err(f"Missing plugin.json at {manifest_path}")
    manifest = {}
else:
    try:
        with open(manifest_path, "r", encoding="utf-8") as f:
            manifest = json.load(f)
    except Exception as e:
        err(f"Invalid JSON in plugin.json: {e}")
        manifest = {}

allowed_keys = {
    "name", "displayName", "version", "description", "logo",
    "suggestedPrompts", "author", "homepage", "repository", "disabled"
}
unknown_keys = set(manifest.keys()) - allowed_keys
if unknown_keys:
    err(f"plugin.json contains unsupported top-level keys: {sorted(unknown_keys)}")

if manifest.get("name") != "pilotfish-agy":
    err(f"plugin.json name must be 'pilotfish-agy', got {manifest.get('name')!r}")

if manifest.get("version") != expected_version:
    err(f"plugin.json version {manifest.get('version')!r} != VERSION {expected_version!r}")

if not isinstance(manifest.get("description"), str) or not manifest["description"].strip():
    err("plugin.json description must be a non-empty string")

logo = manifest.get("logo")
if logo:
    if logo.startswith("/") or "://" in logo:
        err(f"plugin.json logo must be a relative path, got {logo!r}")
    elif not logo.endswith((".svg", ".png", ".jpg", ".jpeg", ".webp")):
        err(f"plugin.json logo has unsupported extension: {logo!r}")
    elif not os.path.isfile(os.path.join(plugin_dir, logo)):
        err(f"plugin.json logo file does not exist: {logo}")

prompts = manifest.get("suggestedPrompts", [])
if prompts:
    if not isinstance(prompts, list) or len(prompts) > 3:
        err("plugin.json suggestedPrompts must be a list of at most 3 strings")
    elif any(not isinstance(p, str) or not p.strip() for p in prompts):
        err("plugin.json suggestedPrompts contains empty or non-string entry")

# 2. Default config.json validation
config_path = os.path.join(plugin_dir, "config.json")
if not os.path.isfile(config_path):
    err(f"Missing config.json at {config_path}")
else:
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception as e:
        err(f"Invalid JSON in config.json: {e}")
        cfg = {}
    if cfg.get("routingMode") not in ("hybrid", "subagent", "swarm"):
        err(f"config.json routingMode must be hybrid|subagent|swarm, got {cfg.get('routingMode')!r}")
    if not isinstance(cfg.get("crossPoolRouting"), bool):
        err("config.json crossPoolRouting must be boolean")
    qf = cfg.get("quotaFloorPercent")
    if not isinstance(qf, int) or isinstance(qf, bool) or not (0 <= qf <= 90):
        err(f"config.json quotaFloorPercent must be integer 0..90, got {qf!r}")
    if not isinstance(cfg.get("protectModels"), list) or not all(isinstance(x, str) for x in cfg["protectModels"]):
        err("config.json protectModels must be a list of strings")
    if not isinstance(cfg.get("projectAgentPrecedence"), bool):
        err("config.json projectAgentPrecedence must be boolean")
    if not isinstance(cfg.get("autoResumeOnQuotaReset"), bool):
        err("config.json autoResumeOnQuotaReset must be boolean")
    rb = cfg.get("resumeBufferSeconds")
    if not isinstance(rb, int) or isinstance(rb, bool) or not (0 <= rb <= 600):
        err(f"config.json resumeBufferSeconds must be integer 0..600, got {rb!r}")
    sg = cfg.get("safetyGuard")
    if not isinstance(sg, dict):
        err("config.json safetyGuard must be an object")
    else:
        for flag in ("enabled", "blockHardcodedSecrets", "blockSecretWebEgress", "protectSensitiveFiles", "confirmDestructiveCommands"):
            if not isinstance(sg.get(flag), bool):
                err(f"config.json safetyGuard.{flag} must be boolean")
    ng = cfg.get("networkGuard")
    if ng is not None:
        if not isinstance(ng, dict):
            err("config.json networkGuard must be an object")
        else:
            if not isinstance(ng.get("enabled"), bool):
                err("config.json networkGuard.enabled must be boolean")
            if not isinstance(ng.get("sentinelEnabled"), bool):
                err("config.json networkGuard.sentinelEnabled must be boolean")
            cs = ng.get("consecutiveSuccessesRequired")
            if not isinstance(cs, int) or isinstance(cs, bool) or not (1 <= cs <= 20):
                err(f"config.json networkGuard.consecutiveSuccessesRequired must be int 1..20, got {cs!r}")
            pi = ng.get("probeIntervalSeconds")
            if not isinstance(pi, (int, float)) or isinstance(pi, bool) or not (0.5 <= pi <= 120):
                err(f"config.json networkGuard.probeIntervalSeconds must be number 0.5..120, got {pi!r}")
            eps = ng.get("endpoints")
            if not isinstance(eps, list) or not all(isinstance(x, str) and ":" in x for x in eps):
                err("config.json networkGuard.endpoints must be a list of 'host:port' strings")

# 3. Hooks validation (must live at plugin root: hooks.json + hooks/safety-guard.py)
hooks_json_path = os.path.join(plugin_dir, "hooks.json")
guard_script_path = os.path.join(plugin_dir, "hooks", "safety-guard.py")
if not os.path.isfile(hooks_json_path):
    err(f"Missing hooks.json at plugin root: {hooks_json_path}")
else:
    try:
        with open(hooks_json_path, "r", encoding="utf-8") as f:
            hooks_data = json.load(f)
        if "pilotfish-safety-guard" not in hooks_data:
            err("hooks.json missing 'pilotfish-safety-guard' hook entry")
        elif "PreToolUse" not in hooks_data["pilotfish-safety-guard"]:
            err("hooks.json 'pilotfish-safety-guard' missing PreToolUse list")
        else:
            for entry in hooks_data["pilotfish-safety-guard"].get("PreToolUse", []):
                for h in entry.get("hooks", []):
                    cmd = str(h.get("command", ""))
                    if "./hooks/" in cmd:
                        err(f"hooks.json command must not use relative './hooks/' path (breaks when Antigravity runs hook from workspace CWD): {cmd!r}")
    except Exception as e:
        err(f"Invalid JSON in hooks.json: {e}")

if not os.path.isfile(guard_script_path):
    err(f"Missing hooks/safety-guard.py at {guard_script_path}")
else:
    try:
        with open(guard_script_path, "r", encoding="utf-8") as f:
            ast.parse(f.read(), filename=guard_script_path)
    except SyntaxError as e:
        err(f"Python syntax error in hooks/safety-guard.py: {e}")

watchdog_script = os.path.join(plugin_dir, "scripts", "pilotfish-net-watchdog.py")
if os.path.isfile(watchdog_script):
    try:
        with open(watchdog_script, "r", encoding="utf-8") as f:
            ast.parse(f.read(), filename=watchdog_script)
    except SyntaxError as e:
        err(f"Python syntax error in scripts/pilotfish-net-watchdog.py: {e}")

# 4. Rule validation (plain markdown, no frontmatter, <= 24KB)
rule_path = os.path.join(plugin_dir, "rules", "AGENTS.md")
if not os.path.isfile(rule_path):
    err(f"Missing rules/AGENTS.md at {rule_path}")
else:
    rule_bytes = os.path.getsize(rule_path)
    if rule_bytes == 0:
        err("rules/AGENTS.md is empty")
    if rule_bytes > 24576:
        err(f"rules/AGENTS.md exceeds Antigravity 24 KB limit ({rule_bytes} bytes)")
    with open(rule_path, "r", encoding="utf-8") as f:
        rule_text = f.read()
    if rule_text.lstrip().startswith("---"):
        err("rules/AGENTS.md inside a plugin should be plain markdown without YAML frontmatter")
    if expected_version not in rule_text:
        err(f"rules/AGENTS.md does not reference current version {expected_version}")

# 5. Skill validation
skill_path = os.path.join(plugin_dir, "skills", "pilotfish", "SKILL.md")
if not os.path.isfile(skill_path):
    err(f"Missing skills/pilotfish/SKILL.md at {skill_path}")
else:
    with open(skill_path, "r", encoding="utf-8") as f:
        skill_text = f.read()
    m = re.match(r"^---\n(.*?)\n---\n", skill_text, re.DOTALL)
    if not m:
        err("skills/pilotfish/SKILL.md is missing YAML frontmatter")
    else:
        fm = m.group(1)
        if not re.search(r"^name:\s*pilotfish\s*$", fm, re.MULTILINE):
            err("skills/pilotfish/SKILL.md frontmatter 'name' must equal 'pilotfish'")
        if not re.search(r"^description:\s*\S+", fm, re.MULTILINE):
            err("skills/pilotfish/SKILL.md frontmatter 'description' must be non-empty")

# 6. Agents validation + capability invariants
expected_agents = {
    "pf-scout": {
        "required_tools": {"read_file", "run_command"},
        "forbidden_tools": {"edit_file", "write_file", "search_web"},
    },
    "pf-plan-verifier": {
        "exact_tools": {"read_file"},
    },
    "pf-security-reviewer": {
        "exact_tools": {"read_file", "search_web"},
    },
    "pf-mech-executor": {
        "required_tools": {"read_file", "edit_file", "write_file", "run_command", "manage_task"},
    },
    "pf-executor": {
        "required_tools": {"read_file", "edit_file", "write_file", "run_command", "manage_task", "search_web"},
    },
    "pf-verifier": {
        "exact_tools": {"read_file", "run_command", "manage_task"},
    },
    "pf-security-executor": {
        "required_tools": {"read_file", "edit_file", "write_file", "run_command", "manage_task", "search_web"},
    },
}

valid_native_tools = {
    "read_file", "edit_file", "write_file", "run_command", "manage_task", "search_web"
}
disallowed_leaf_tools = {"invoke_subagent", "define_subagent", "run_workflow", "swarm"}
legacy_claude_keys = ("model:", "effort:", "disallowedTools:", "color:")

agents_dir = os.path.join(plugin_dir, "agents")
if not os.path.isdir(agents_dir):
    err(f"Missing agents directory at {agents_dir}")
else:
    found_files = {
        fn[:-3] for fn in os.listdir(agents_dir) if fn.endswith(".md")
    }
    missing = set(expected_agents.keys()) - found_files
    extra = found_files - set(expected_agents.keys())
    if missing:
        err(f"Missing expected agent files: {sorted(missing)}")
    if extra:
        err(f"Unexpected extra agent files: {sorted(extra)}")

    for agent_name, spec in expected_agents.items():
        path = os.path.join(agents_dir, f"{agent_name}.md")
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        m = re.match(r"^---\n(.*?)\n---\n(.*)$", content, re.DOTALL)
        if not m:
            err(f"{agent_name}.md missing valid YAML frontmatter")
            continue
        fm, body = m.group(1), m.group(2)

        if not body.strip():
            err(f"{agent_name}.md has empty system prompt body")
        if not re.search(rf"^name:\s*{re.escape(agent_name)}\s*$", fm, re.MULTILINE):
            err(f"{agent_name}.md frontmatter name does not match filename")
        if not re.search(r"^description:\s*\S+", fm, re.MULTILINE):
            err(f"{agent_name}.md missing description")
        if not re.search(r"^subagent:\s*true\s*$", fm, re.MULTILINE):
            err(f"{agent_name}.md must set subagent: true")
        if not re.search(r"^mainAgent:\s*false\s*$", fm, re.MULTILINE):
            err(f"{agent_name}.md must set mainAgent: false")

        for bad_key in legacy_claude_keys:
            if re.search(rf"^{re.escape(bad_key)}", fm, re.MULTILINE):
                err(f"{agent_name}.md contains legacy Claude Code key '{bad_key}'")

        tm = re.search(r"^tools:\s*\[(.*?)\]\s*$", fm, re.MULTILINE)
        if not tm:
            err(f"{agent_name}.md missing inline tools: [...] list")
            continue
        tools = {t.strip() for t in tm.group(1).split(",") if t.strip()}
        unknown_tools = tools - valid_native_tools
        if unknown_tools:
            err(f"{agent_name}.md uses unknown/non-native tools: {sorted(unknown_tools)}")
        if tools & disallowed_leaf_tools:
            err(f"{agent_name}.md violates leaf invariant (has subagent/workflow tools)")

        if "exact_tools" in spec and tools != spec["exact_tools"]:
            err(f"{agent_name}.md tools {sorted(tools)} != exact {sorted(spec['exact_tools'])}")
        if "required_tools" in spec and not spec["required_tools"].issubset(tools):
            err(f"{agent_name}.md missing required tools: {sorted(spec['required_tools'] - tools)}")
        if "forbidden_tools" in spec and (tools & spec["forbidden_tools"]):
            err(f"{agent_name}.md contains forbidden tools: {sorted(tools & spec['forbidden_tools'])}")

if errors:
    print("VALIDATION FAILED:", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

print(f"OK: {plugin_dir} passed all Antigravity plugin, hook & Pilotfish capability checks (v{expected_version}).")
PY
