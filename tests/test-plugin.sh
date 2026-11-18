#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "[1/6] Validating source plugin..."
bash "$ROOT_DIR/scripts/validate.sh" "$ROOT_DIR/plugin"

echo "[2/6] Validating built bundle..."
if [[ ! -d "$ROOT_DIR/dist/pilotfish-agy" ]]; then
  bash "$ROOT_DIR/scripts/build.sh"
fi
bash "$ROOT_DIR/scripts/validate.sh" "$ROOT_DIR/dist/pilotfish-agy"

echo "[3/6] Testing dry-run + project install + upgrade backup + uninstall..."
MOCK_PROJ="$TMP_DIR/sample-project"
mkdir -p "$MOCK_PROJ"

bash "$ROOT_DIR/scripts/install.sh" --project "$MOCK_PROJ" --dry-run >/dev/null
if [[ -e "$MOCK_PROJ/.agents/plugins/pilotfish-agy" ]]; then
  echo "FAIL: --dry-run created files unexpectedly" >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/install.sh" --project "$MOCK_PROJ" >/dev/null
bash "$ROOT_DIR/scripts/validate.sh" "$MOCK_PROJ/.agents/plugins/pilotfish-agy"

# Verify install.sh rewrote hooks.json to an absolute path and executes cleanly from an unrelated CWD
python3 - "$MOCK_PROJ/.agents/plugins/pilotfish-agy" "$TMP_DIR" <<'PY'
import json, os, subprocess, sys
installed_dir, unrelated_cwd = sys.argv[1], sys.argv[2]
expected_guard = os.path.join(installed_dir, "hooks", "safety-guard.py")
with open(os.path.join(installed_dir, "hooks.json"), "r", encoding="utf-8") as f:
    data = json.load(f)
cmd = data["pilotfish-safety-guard"]["PreToolUse"][0]["hooks"][0]["command"]
assert expected_guard in cmd and "./hooks/" not in cmd, f"Expected absolute guard path in hooks.json, got: {cmd!r}"
p = subprocess.run(
    ["sh", "-c", cmd],
    cwd=unrelated_cwd,
    input=json.dumps({"toolCall": {"name": "read_file", "args": {"Path": "/repo/src/app.ts"}}}),
    text=True,
    capture_output=True,
    check=True,
)
assert p.stdout == "", f"Expected empty stdout pass-through from unrelated CWD, got: {p.stdout!r}"
PY

sleep 1
bash "$ROOT_DIR/scripts/install.sh" --project "$MOCK_PROJ" >/dev/null
BACKUP_COUNT="$(find "$MOCK_PROJ/.agents/.backups" -maxdepth 1 -type d -name 'pilotfish-agy-*' | wc -l)"
if [[ "$BACKUP_COUNT" -lt 1 ]]; then
  echo "FAIL: Expected backup directory on reinstall" >&2
  exit 1
fi

echo "[4/6] Testing scripts/configure.sh project override..."
bash "$ROOT_DIR/scripts/configure.sh" --project "$MOCK_PROJ" --mode swarm --cross-pool off --quota-floor 5 --protect-models "argon,carbon" --auto-resume off --safety-guard off >/dev/null
python3 - "$MOCK_PROJ/.agents/pilotfish.config.json" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    cfg = json.load(f)
assert cfg["routingMode"] == "swarm", cfg
assert cfg["crossPoolRouting"] is False, cfg
assert cfg["quotaFloorPercent"] == 5, cfg
assert cfg["protectModels"] == ["argon", "carbon"], cfg
assert cfg["autoResumeOnQuotaReset"] is False, cfg
assert cfg["safetyGuard"]["enabled"] is False, cfg
PY

echo "[5/6] Testing deterministic PreToolUse safety-guard.py hook..."
python3 - "$ROOT_DIR/dist/pilotfish-agy" "$MOCK_PROJ" <<'PY'
import json
import os
import subprocess
import sys

plugin_dir, mock_proj = sys.argv[1], sys.argv[2]
guard = os.path.join(plugin_dir, "hooks", "safety-guard.py")

def run_guard(payload, ws=None):
    env = dict(os.environ, PLUGIN_ROOT=plugin_dir)
    if ws:
        payload = dict(payload, workspacePaths=[ws], cwd=ws)
    p = subprocess.run(
        ["python3", guard],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=True,
        env=env,
    )
    return {} if not p.stdout.strip() else json.loads(p.stdout)

# Normal calls must pass through with empty stdout (Antigravity treats bare {} as deny)
for sample in (
    {"toolCall": {"name": "read_file", "args": {"Path": "/repo/src/app.ts"}}},
    {"toolCall": {"name": "read_file", "args": {"Path": "/repo/.env.example"}}},
    {"toolCall": {"name": "run_command", "args": {"CommandLine": "rm -rf dist/"}}},
    {"toolCall": {"name": "run_command", "args": {"CommandLine": "npm test"}}},
):
    p = subprocess.run(["python3", guard], input=json.dumps(sample), text=True, capture_output=True, check=True, env=dict(os.environ, PLUGIN_ROOT=plugin_dir))
    assert p.stdout == "", (sample, p.stdout)

# Sensitive files -> force_ask
for path in ("/repo/.env", "/repo/.env.production", "/home/u/.ssh/id_ed25519", "/repo/app/src/config.local.ts", "/repo/list.m3u8"):
    r = run_guard({"toolCall": {"name": "read_file", "args": {"Path": path}}})
    assert r.get("decision") == "force_ask", (path, r)

# Hardcoded secrets -> deny (constructed dynamically so test file itself has no raw secret)
fake_aws = "AKIA" + "1234567890ABCDEF"
fake_gh = "ghp_" + "A" * 36
fake_pem = "-----BEGIN " + "PRIVATE KEY-----\nMIIEvAIBADAN"

for secret in (fake_aws, fake_gh, fake_pem):
    r = run_guard({"toolCall": {"name": "write_file", "args": {"Path": "/repo/src/cfg.ts", "Content": f"const k = '{secret}';"}}})
    assert r.get("decision") == "deny", (secret[:8], r)

# Web egress secret -> deny
r = run_guard({"toolCall": {"name": "search_web", "args": {"query": f"debug token {fake_gh}"}}})
assert r.get("decision") == "deny", r

# Catastrophic shell -> deny
for cmd in ("rm -rf /", "mkfs.ext4 /dev/sda1", "dd if=/dev/zero of=/dev/nvme0n1"):
    r = run_guard({"toolCall": {"name": "run_command", "args": {"CommandLine": cmd}}})
    assert r.get("decision") == "deny", (cmd, r)

# High-risk destructive shell -> force_ask
for cmd in ("git push --force origin main", "git reset --hard HEAD~3", "psql -c 'DROP TABLE users;'", "rm -rf /repo/src"):
    r = run_guard({"toolCall": {"name": "run_command", "args": {"CommandLine": cmd}}})
    assert r.get("decision") == "force_ask", (cmd, r)

# Invalid JSON stdin -> empty stdout pass-through (never block on malformed payload)
p_bad = subprocess.run(["python3", guard], input="{not-json", text=True, capture_output=True, check=True, env=dict(os.environ, PLUGIN_ROOT=plugin_dir))
assert p_bad.stdout == "", p_bad.stdout

# Project override safetyGuard.enabled = false -> empty stdout pass-through
p_off = subprocess.run(
    ["python3", guard],
    input=json.dumps({"toolCall": {"name": "read_file", "args": {"Path": "/repo/.env"}}, "workspacePaths": [mock_proj], "cwd": mock_proj}),
    text=True,
    capture_output=True,
    check=True,
    env=dict(os.environ, PLUGIN_ROOT=plugin_dir),
)
assert p_off.stdout == "", p_off.stdout
print("  safety-guard.py assertions passed (all deny, force_ask, empty-stdout pass-through, and override cases).")
PY

bash "$ROOT_DIR/scripts/install.sh" --project "$MOCK_PROJ" --uninstall --no-backup >/dev/null
if [[ -e "$MOCK_PROJ/.agents/plugins/pilotfish-agy" ]]; then
  echo "FAIL: --uninstall failed to remove plugin directory" >&2
  exit 1
fi

echo "[6/6] Checking no Claude Code legacy paths leak into Antigravity bundle..."
if grep -rnE 'CLAUDE_PLUGIN_ROOT|CLAUDE_CONFIG_DIR|CLAUDE_CODE_SUBAGENT_MODEL|NotebookEdit' "$ROOT_DIR/dist/pilotfish-agy/"; then
  echo "FAIL: Found legacy Claude Code references in built Antigravity bundle" >&2
  exit 1
fi

echo "ALL TESTS PASSED."
