#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_NAME="pilotfish-agy"

MODE=""
PROJECT_DIR=""
UNINSTALL=0
DRY_RUN=0
NO_BACKUP=0
SOURCE_DIR=""

usage() {
  cat <<'EOF'
Pilotfish for Antigravity — Portable Installer

Usage:
  install.sh --global [options]
  install.sh --project <project-dir> [options]

Targets (choose exactly one):
  --global                Install/uninstall globally in ~/.gemini/config/plugins/pilotfish-agy
                          (honors $ANTIGRAVITY_CONFIG_DIR if set)
  --project <dir>         Install/uninstall inside <dir>/.agents/plugins/pilotfish-agy

Options:
  --uninstall             Remove pilotfish-agy from the chosen target
  --dry-run               Show planned changes without writing or deleting anything
  --no-backup             Skip timestamped backup when replacing/removing an existing install
  --source <dir>          Explicit source plugin directory (defaults to dist/pilotfish-agy or plugin/)
  -h, --help              Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)
      MODE="global"
      shift
      ;;
    --project)
      MODE="project"
      PROJECT_DIR="${2:-}"
      if [[ -z "$PROJECT_DIR" ]]; then
        echo "Error: --project requires a directory path" >&2
        exit 1
      fi
      shift 2
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-backup)
      NO_BACKUP=1
      shift
      ;;
    --source)
      SOURCE_DIR="${2:-}"
      shift 2
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

if [[ -z "$MODE" ]]; then
  echo "Error: specify either --global or --project <dir>" >&2
  usage >&2
  exit 1
fi

if [[ "$MODE" == "global" ]]; then
  BASE_CONFIG="${ANTIGRAVITY_CONFIG_DIR:-$HOME/.gemini/config}"
  PLUGINS_ROOT="$BASE_CONFIG/plugins"
  BACKUP_ROOT="$BASE_CONFIG/backups"
else
  if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Error: project directory does not exist: $PROJECT_DIR" >&2
    exit 1
  fi
  ABS_PROJECT="$(cd "$PROJECT_DIR" && pwd)"
  PLUGINS_ROOT="$ABS_PROJECT/.agents/plugins"
  BACKUP_ROOT="$ABS_PROJECT/.agents/.backups"
fi

TARGET_DIR="$PLUGINS_ROOT/$PLUGIN_NAME"

if [[ -z "$SOURCE_DIR" ]]; then
  if [[ -d "$ROOT_DIR/dist/$PLUGIN_NAME" ]]; then
    SOURCE_DIR="$ROOT_DIR/dist/$PLUGIN_NAME"
  else
    SOURCE_DIR="$ROOT_DIR/plugin"
  fi
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/${PLUGIN_NAME}-${STAMP}"

backup_existing() {
  if [[ ! -e "$TARGET_DIR" ]]; then
    return 0
  fi
  if [[ "$NO_BACKUP" -eq 1 ]]; then
    echo "Note: skipping backup (--no-backup) for existing $TARGET_DIR"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] Would back up $TARGET_DIR -> $BACKUP_DIR"
    return 0
  fi
  mkdir -p "$BACKUP_ROOT"
  cp -Rp "$TARGET_DIR" "$BACKUP_DIR"
  echo "Backup created: $BACKUP_DIR"
}

if [[ "$UNINSTALL" -eq 1 ]]; then
  if [[ ! -e "$TARGET_DIR" ]]; then
    echo "Nothing to uninstall: $TARGET_DIR does not exist."
    exit 0
  fi
  backup_existing
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] Would remove $TARGET_DIR"
    exit 0
  fi
  rm -rf "$TARGET_DIR"
  echo "Uninstalled $PLUGIN_NAME from $TARGET_DIR"
  exit 0
fi

if [[ ! -f "$SOURCE_DIR/plugin.json" ]]; then
  echo "Error: invalid plugin source directory (missing plugin.json): $SOURCE_DIR" >&2
  exit 1
fi

if [[ -x "$ROOT_DIR/scripts/validate.sh" ]]; then
  bash "$ROOT_DIR/scripts/validate.sh" "$SOURCE_DIR"
fi

echo "Install plan:"
echo "  Source: $SOURCE_DIR"
echo "  Target: $TARGET_DIR"
if [[ -e "$TARGET_DIR" ]]; then
  echo "  Action: replace existing installation"
else
  echo "  Action: fresh installation"
fi

backup_existing

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] Would copy $SOURCE_DIR -> $TARGET_DIR"
  exit 0
fi

mkdir -p "$PLUGINS_ROOT"
TMP_TARGET="${TARGET_DIR}.installing.$$"
rm -rf "$TMP_TARGET"
cp -Rp "$SOURCE_DIR" "$TMP_TARGET"
if [[ -f "$TMP_TARGET/hooks.json" ]]; then
  python3 - "$TMP_TARGET/hooks.json" "$TARGET_DIR/hooks/safety-guard.py" <<'PY'
import json, sys
hooks_path, guard_abs = sys.argv[1], sys.argv[2]
with open(hooks_path, "r", encoding="utf-8") as f:
    data = json.load(f)
for entry in data.get("pilotfish-safety-guard", {}).get("PreToolUse", []):
    for h in entry.get("hooks", []):
        if isinstance(h, dict) and "safety-guard.py" in str(h.get("command", "")):
            h["command"] = f'python3 "{guard_abs}"'
with open(hooks_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
fi
rm -rf "$TARGET_DIR"
mv "$TMP_TARGET" "$TARGET_DIR"

echo ""
echo "Installed $PLUGIN_NAME successfully to: $TARGET_DIR"
echo "Note: Antigravity loads plugins automatically on the next turn; manage toggle in Customizations -> pilotfish-agy."
