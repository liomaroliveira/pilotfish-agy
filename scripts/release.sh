#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      NEW_VER="${2:-}"
      if [[ -z "$NEW_VER" ]]; then
        echo "Error: --version requires a value (e.g. 1.5.0-agy.3)" >&2
        exit 1
      fi
      printf '%s\n' "$NEW_VER" > "$ROOT_DIR/VERSION"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--version <semver>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
BUNDLE_TAR="$RELEASE_DIR/pilotfish-agy-v${VERSION}.tar.gz"
BUNDLE_ZIP="$RELEASE_DIR/pilotfish-agy-v${VERSION}.zip"
PORTABLE_TAR="$RELEASE_DIR/pilotfish-agy-portable-v${VERSION}.tar.gz"

echo "==> Running build (v$VERSION)..."
bash "$ROOT_DIR/scripts/build.sh" --sync-version

echo "==> Running test suite..."
bash "$ROOT_DIR/tests/test-plugin.sh"

echo "==> Packaging release artifacts into $RELEASE_DIR..."
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

tar -C "$DIST_DIR" -czf "$BUNDLE_TAR" pilotfish-agy

python3 - "$DIST_DIR/pilotfish-agy" "$BUNDLE_ZIP" <<'PY'
import os
import sys
import zipfile

src_dir, zip_path = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for root, _, files in os.walk(src_dir):
        for fn in sorted(files):
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, os.path.dirname(src_dir))
            zf.write(full, arcname=rel)
PY

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
KIT_ROOT="$STAGE_DIR/pilotfish-agy-kit-v${VERSION}"
mkdir -p "$KIT_ROOT/scripts"
cp -R "$DIST_DIR/pilotfish-agy" "$KIT_ROOT/plugin"
cp "$ROOT_DIR/scripts/install.sh" "$KIT_ROOT/scripts/"
cp "$ROOT_DIR/scripts/validate.sh" "$KIT_ROOT/scripts/"
cp "$ROOT_DIR/scripts/configure.sh" "$KIT_ROOT/scripts/"
cp "$ROOT_DIR/VERSION" "$ROOT_DIR/LICENSE" "$ROOT_DIR/ATTRIBUTION.md" "$ROOT_DIR/CHANGELOG.md" "$ROOT_DIR/README.md" "$KIT_ROOT/"
chmod +x "$KIT_ROOT/scripts/install.sh" "$KIT_ROOT/scripts/validate.sh" "$KIT_ROOT/scripts/configure.sh"
tar -C "$STAGE_DIR" -czf "$PORTABLE_TAR" "pilotfish-agy-kit-v${VERSION}"

(
  cd "$RELEASE_DIR"
  sha256sum \
    "pilotfish-agy-v${VERSION}.tar.gz" \
    "pilotfish-agy-v${VERSION}.zip" \
    "pilotfish-agy-portable-v${VERSION}.tar.gz" > SHA256SUMS.txt
)

BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$RELEASE_DIR/RELEASE-NOTES.md" <<EOF
# Pilotfish for Antigravity — v${VERSION}

- **Built at (UTC):** ${BUILD_DATE}
- **Upstream base:** [Nanako0129/pilotfish](https://github.com/Nanako0129/pilotfish) \`v1.5.0\` (MIT)

## Highlights in v${VERSION}
- **Live model + thinking + quota discovery** via \`swarm(action="models", all=true)\` (adapts automatically to Plus, Pro, Flash-only, Gemini 4 Hydrogen/Argon, Claude 4.6, GPT-OSS, etc.).
- **Configurable Hybrid mode** (\`hybrid\` default | \`subagent\` | \`swarm\`), **cross-pool Gemini ↔ Claude ↔ GPT routing** (default \`on\`), **configurable quota floor** (default \`10%\`, adjustable e.g. \`5%\`–\`20%\`), and **protected models** (default \`["argon"]\`) via \`config.json\` / \`.agents/pilotfish.config.json\` / \`scripts/configure.sh\`.
- **Project-specialist precedence:** workspace domain agents (e.g. \`vega-*\` in \`firetv-dev\`) beat generic \`pf-*\` roles for domain/MCP work; \`pf-*\` act as complementary governance, verification, and fallback roles.
- **Explicit Antigravity ecosystem integration:** composes with native subagents (\`research\`, \`browser\`, \`image-generator\`), \`run_workflow\`, \`swarm\`, \`ask_question\`, \`schedule\`, MCP servers, global/workspace skills, plugins, and slash commands.

## Artifacts

| File | Purpose |
| --- | --- |
| \`pilotfish-agy-v${VERSION}.tar.gz\` | Clean Antigravity plugin bundle (\`pilotfish-agy/\`) |
| \`pilotfish-agy-v${VERSION}.zip\` | Same clean plugin bundle in ZIP format |
| \`pilotfish-agy-portable-v${VERSION}.tar.gz\` | Portable kit with plugin + \`install.sh\` + \`configure.sh\` + \`validate.sh\` + docs |
| \`SHA256SUMS.txt\` | SHA-256 checksums for all archives |
EOF

echo "==> Release artifacts created:"
ls -lh "$RELEASE_DIR"
