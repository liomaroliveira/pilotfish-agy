#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[1/5] Validating source plugin..."
bash "$ROOT_DIR/scripts/validate.sh" "$ROOT_DIR/plugin"

echo "[2/5] Validating built bundle..."
if [[ ! -d "$ROOT_DIR/dist/pilotfish-agy" ]]; then
  bash "$ROOT_DIR/scripts/build.sh"
fi
bash "$ROOT_DIR/scripts/validate.sh" "$ROOT_DIR/dist/pilotfish-agy"

echo "[3/5] Testing dry-run + project install + upgrade backup + uninstall..."
MOCK_PROJ="$TMP_DIR/sample-project"
mkdir -p "$MOCK_PROJ"

bash "$ROOT_DIR/scripts/install.sh" --project "$MOCK_PROJ" --dry-run >/dev/null
if [[ -e "$MOCK_PROJ/.agents/plugins/pilotfish-agy" ]]; then
  echo "FAIL: --dry-run created files unexpectedly" >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/install.sh" --project "$MOCK_PROJ" >/dev/null
bash "$ROOT_DIR/scripts/validate.sh" "$MOCK_PROJ/.agents/plugins/pilotfish-agy"

sleep 1
bash "$ROOT_DIR/scripts/install.sh" --project "$MOCK_PROJ" >/dev/null
BACKUP_COUNT="$(find "$MOCK_PROJ/.agents/.backups" -maxdepth 1 -type d -name 'pilotfish-agy-*' | wc -l)"
if [[ "$BACKUP_COUNT" -lt 1 ]]; then
  echo "FAIL: Expected backup directory on reinstall" >&2
  exit 1
fi

echo "[4/5] Testing scripts/configure.sh project override..."
bash "$ROOT_DIR/scripts/configure.sh" --project "$MOCK_PROJ" --mode swarm --cross-pool off --quota-floor 5 --protect-models "argon,carbon" >/dev/null
python3 - "$MOCK_PROJ/.agents/pilotfish.config.json" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    cfg = json.load(f)
assert cfg["routingMode"] == "swarm", cfg
assert cfg["crossPoolRouting"] is False, cfg
assert cfg["quotaFloorPercent"] == 5, cfg
assert cfg["protectModels"] == ["argon", "carbon"], cfg
PY

bash "$ROOT_DIR/scripts/install.sh" --project "$MOCK_PROJ" --uninstall --no-backup >/dev/null
if [[ -e "$MOCK_PROJ/.agents/plugins/pilotfish-agy" ]]; then
  echo "FAIL: --uninstall failed to remove plugin directory" >&2
  exit 1
fi

echo "[5/5] Checking no Claude Code legacy paths leak into Antigravity bundle..."
if grep -rnE 'CLAUDE_PLUGIN_ROOT|CLAUDE_CONFIG_DIR|CLAUDE_CODE_SUBAGENT_MODEL|NotebookEdit' "$ROOT_DIR/dist/pilotfish-agy/"; then
  echo "FAIL: Found legacy Claude Code references in built Antigravity bundle" >&2
  exit 1
fi

echo "ALL TESTS PASSED."
