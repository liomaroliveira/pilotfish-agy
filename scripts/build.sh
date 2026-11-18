#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_DIR="$DIST_DIR/pilotfish-agy"

SYNC_VERSION=0
if [[ "${1:-}" == "--sync-version" ]]; then
  SYNC_VERSION=1
fi

if [[ "$SYNC_VERSION" -eq 1 ]]; then
  python3 - "$ROOT_DIR" "$VERSION" <<'PY'
import json
import os
import re
import sys

root, ver = sys.argv[1], sys.argv[2]

manifest_path = os.path.join(root, "plugin", "plugin.json")
with open(manifest_path, "r", encoding="utf-8") as f:
    data = json.load(f)
data["version"] = ver
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

rule_path = os.path.join(root, "plugin", "rules", "AGENTS.md")
with open(rule_path, "r", encoding="utf-8") as f:
    text = f.read()
updated = re.sub(
    r"<!-- pilotfish-agy v[^\s]+",
    f"<!-- pilotfish-agy v{ver}",
    text,
    count=1,
)
with open(rule_path, "w", encoding="utf-8") as f:
    f.write(updated)
PY
fi

echo "==> Validating source plugin..."
bash "$ROOT_DIR/scripts/validate.sh" "$ROOT_DIR/plugin"

echo "==> Building clean plugin bundle into $BUNDLE_DIR..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

cp "$ROOT_DIR/plugin/plugin.json" "$BUNDLE_DIR/"
cp "$ROOT_DIR/plugin/config.json" "$BUNDLE_DIR/"
cp "$ROOT_DIR/plugin/README.md" "$BUNDLE_DIR/"
cp "$ROOT_DIR/plugin/LICENSE" "$BUNDLE_DIR/"
cp "$ROOT_DIR/plugin/ATTRIBUTION.md" "$BUNDLE_DIR/"
cp -R "$ROOT_DIR/plugin/assets" "$BUNDLE_DIR/"
cp -R "$ROOT_DIR/plugin/rules" "$BUNDLE_DIR/"
cp -R "$ROOT_DIR/plugin/skills" "$BUNDLE_DIR/"
cp -R "$ROOT_DIR/plugin/agents" "$BUNDLE_DIR/"

find "$BUNDLE_DIR" \( -name '.DS_Store' -o -name 'Thumbs.db' -o -name '*.tmp' \) -delete

echo "==> Validating built bundle..."
bash "$ROOT_DIR/scripts/validate.sh" "$BUNDLE_DIR"

echo "Build complete: $BUNDLE_DIR (v$VERSION)"
