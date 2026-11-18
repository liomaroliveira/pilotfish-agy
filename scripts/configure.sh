#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_NAME="pilotfish-agy"

TARGET_SCOPE="global"
PROJECT_DIR=""
MODE=""
CROSS_POOL=""
QUOTA_FLOOR=""
PROTECT_MODELS=""
PROJECT_PRECEDENCE=""
SHOW_ONLY=0
RESET=0

usage() {
  cat <<'EOF'
Pilotfish for Antigravity — Configuration Tool

Usage:
  configure.sh [target] [options]

Targets:
  --global                        Edit ~/.gemini/config/plugins/pilotfish-agy/config.json (default)
  --project <dir>                 Edit <dir>/.agents/pilotfish.config.json (project-level override)
  --source                        Edit plugin/config.json inside this repository (default for future builds)

Options:
  --mode <hybrid|subagent|swarm>  Set routingMode (default: hybrid)
  --cross-pool <on|off>           Enable/disable cross-pool Gemini <-> Claude <-> GPT routing (default: on)
  --quota-floor <0-90>            Minimum remaining quota % before protecting a pool/model (default: 10)
  --protect-models <csv>          Comma-separated model substrings to protect (default: argon; use "" to clear)
  --project-precedence <on|off>   Project domain subagents beat generic pf-* roles (default: on)
  --show                          Print current effective config and exit
  --reset                         Restore default config values
  -h, --help                      Show this help message

Examples:
  configure.sh --mode hybrid --cross-pool on --quota-floor 10
  configure.sh --project /path/to/repo --mode subagent --quota-floor 5 --cross-pool off
  configure.sh --global --protect-models "argon,carbon" --quota-floor 5
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)
      TARGET_SCOPE="global"
      shift
      ;;
    --project)
      TARGET_SCOPE="project"
      PROJECT_DIR="${2:-}"
      if [[ -z "$PROJECT_DIR" ]]; then
        echo "Error: --project requires a directory" >&2
        exit 1
      fi
      shift 2
      ;;
    --source)
      TARGET_SCOPE="source"
      shift
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --cross-pool)
      CROSS_POOL="${2:-}"
      shift 2
      ;;
    --quota-floor)
      QUOTA_FLOOR="${2:-}"
      shift 2
      ;;
    --protect-models)
      PROTECT_MODELS="${2:-}"
      shift 2
      ;;
    --project-precedence)
      PROJECT_PRECEDENCE="${2:-}"
      shift 2
      ;;
    --show)
      SHOW_ONLY=1
      shift
      ;;
    --reset)
      RESET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$TARGET_SCOPE" in
  global)
    BASE_CONFIG="${ANTIGRAVITY_CONFIG_DIR:-$HOME/.gemini/config}"
    CONFIG_PATH="$BASE_CONFIG/plugins/$PLUGIN_NAME/config.json"
    ;;
  project)
    if [[ ! -d "$PROJECT_DIR" ]]; then
      echo "Error: project directory does not exist: $PROJECT_DIR" >&2
      exit 1
    fi
    ABS_PROJECT="$(cd "$PROJECT_DIR" && pwd)"
    CONFIG_PATH="$ABS_PROJECT/.agents/pilotfish.config.json"
    ;;
  source)
    CONFIG_PATH="$ROOT_DIR/plugin/config.json"
    ;;
esac

DEFAULT_CONFIG="$ROOT_DIR/plugin/config.json"

if [[ "$SHOW_ONLY" -eq 1 ]]; then
  if [[ -f "$CONFIG_PATH" ]]; then
    echo "# Active config: $CONFIG_PATH"
    cat "$CONFIG_PATH"
  else
    echo "# No custom config at $CONFIG_PATH (falling back to defaults):"
    cat "$DEFAULT_CONFIG"
  fi
  exit 0
fi

python3 - "$CONFIG_PATH" "$DEFAULT_CONFIG" "$RESET" "$MODE" "$CROSS_POOL" "$QUOTA_FLOOR" "$PROTECT_MODELS" "$PROJECT_PRECEDENCE" <<'PY'
import json
import os
import sys

config_path, default_path, reset_s, mode, cross_pool, quota_floor, protect_models, proj_prec = sys.argv[1:9]
reset = reset_s == "1"

with open(default_path, "r", encoding="utf-8") as f:
    defaults = json.load(f)

if not reset and os.path.isfile(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
else:
    cfg = dict(defaults)

def parse_bool(val, flag):
    v = val.strip().lower()
    if v in ("on", "true", "1", "yes"):
        return True
    if v in ("off", "false", "0", "no"):
        return False
    raise SystemExit(f"Error: {flag} expects on|off (got {val!r})")

if mode:
    if mode not in ("hybrid", "subagent", "swarm"):
        raise SystemExit(f"Error: --mode must be hybrid|subagent|swarm (got {mode!r})")
    cfg["routingMode"] = mode

if cross_pool:
    cfg["crossPoolRouting"] = parse_bool(cross_pool, "--cross-pool")

if quota_floor:
    try:
        qf = int(quota_floor)
    except ValueError:
        raise SystemExit(f"Error: --quota-floor must be an integer 0..90 (got {quota_floor!r})")
    if not (0 <= qf <= 90):
        raise SystemExit(f"Error: --quota-floor must be between 0 and 90 (got {qf})")
    cfg["quotaFloorPercent"] = qf

if protect_models or "--protect-models" in os.environ.get("PF_FLAGS", ""):
    items = [s.strip() for s in protect_models.split(",") if s.strip()]
    cfg["protectModels"] = items

if proj_prec:
    cfg["projectAgentPrecedence"] = parse_bool(proj_prec, "--project-precedence")

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print(f"Updated config: {config_path}")
print(json.dumps(cfg, indent=2))
PY
