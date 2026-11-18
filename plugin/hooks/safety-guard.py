#!/usr/bin/env python3
"""Pilotfish for Antigravity — Deterministic PreToolUse Safety Guard.

Inspects tool calls before execution to:
1. Hard-block (`deny`) hardcoded private keys / API tokens in write_file / edit_file
   and secret egress in search_web queries.
2. Hard-block (`deny`) catastrophic destructive shell commands (rm -rf /, mkfs, dd to disk).
3. Require explicit user confirmation (`force_ask`) before accessing sensitive local
   secret files (.env, *.pem, *.key, id_rsa, credentials.json, config.local.ts, *.m3u*)
   or running high-risk destructive commands (git push --force, git reset --hard,
   DROP TABLE / TRUNCATE / unguarded DELETE, broad rm -rf).

Returns empty stdout (exit 0 pass-through) on normal calls so Antigravity's native
permission policy remains intact (Antigravity treats `{}` JSON without a decision as deny).
Configurable via `.agents/pilotfish.config.json` or plugin `config.json`.
"""

import json
import os
import re
import sys
from pathlib import Path

PLUGIN_ROOT = Path(os.environ.get("PLUGIN_ROOT") or Path(__file__).resolve().parent.parent)

# Real secret patterns (never match obvious placeholders)
SECRET_PATTERNS = [
    ("Private Key Block", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----")),
    ("AWS Access Key ID", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("GitHub Token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}\b")),
    ("GitHub Fine-Grained PAT", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}\b")),
    ("Anthropic API Key", re.compile(r"\bsk-ant-[A-Za-z0-9\-_]{20,}\b")),
    ("OpenAI/Stripe Secret Key", re.compile(r"\bsk-(?:live|proj)?-?[A-Za-z0-9]{32,}\b")),
    ("Google API Key", re.compile(r"\bAIza[0-9A-Za-z\-_]{35}\b")),
    ("Slack Token", re.compile(r"\bxox[baprs]-[0-9A-Za-z\-]{10,}\b")),
]

PLACEHOLDER_HINTS = ("example", "sample", "dummy", "placeholder", "your_", "xxxx", "fake_", "test_")

SENSITIVE_BASENAME_RE = re.compile(
    r"^(?:\.env(?:\..+)?|.*\.pem|.*\.key|.*\.p12|.*\.pfx|id_rsa|id_ed25519|id_ecdsa|"
    r"credentials\.json|secrets\.json|service[-_]?account.*\.json|"
    r"config\.local\.(?:ts|js|json)|.*\.m3u8?)$",
    re.IGNORECASE,
)

SAFE_TEMPLATE_RE = re.compile(
    r"(?:\.example|\.sample|\.template|\.dist|\.mock|\.spec\.|\.test\.)",
    re.IGNORECASE,
)

CATASTROPHIC_CMD_PATTERNS = [
    ("rm -rf targeting root/home", re.compile(r"\brm\s+-[^\n]*r[^\n]*f[^\n]*\s+(?:/\s*$|/\*|~|\$HOME(?:\s|$|/))")),
    ("mkfs filesystem format", re.compile(r"\bmkfs(?:\.[a-z0-9]+)?\b")),
    ("raw block device write (dd)", re.compile(r"\bdd\b[^\n]*\bof=/dev/(?:sd|nvme|vd|hd|mmcblk)")),
    ("fork bomb", re.compile(r":\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;")),
]

CONFIRM_CMD_PATTERNS = [
    ("git force push", re.compile(r"\bgit\s+push\b[^\n]*(?:--force\b|--force-with-lease\b|\s-f\b)")),
    ("git reset --hard", re.compile(r"\bgit\s+reset\s+--hard\b")),
    ("git clean -fd", re.compile(r"\bgit\s+clean\b[^\n]*-[a-zA-Z]*f[a-zA-Z]*d|\bgit\s+clean\b[^\n]*-[a-zA-Z]*d[a-zA-Z]*f")),
    ("SQL destructive DDL (DROP/TRUNCATE)", re.compile(r"\b(?:DROP\s+(?:TABLE|DATABASE|SCHEMA|VIEW)|TRUNCATE\s+TABLE)\b", re.IGNORECASE)),
    ("SQL unguarded DELETE", re.compile(r"\bDELETE\s+FROM\s+[`\"'\w.]+(?:\s*;|\s*$|\s+WHERE\s+1\s*=\s*1\b)", re.IGNORECASE)),
    ("Cloud bucket/project deletion", re.compile(r"\b(?:gcloud\s+projects\s+delete|gsutil\s+(?:-m\s+)?rm|gcloud\s+storage\s+rm)\b")),
]

SAFE_RM_TARGET_RE = re.compile(
    r"(?:^|/|\s)(?:dist|build|out|coverage|node_modules|\.tmp|\.cache|\.next|\.turbo|tmp)(?:/|$|\s)|/tmp/|mktemp|\$(?:TMP|TEMP|STAGE|BUNDLE|BACKUP)",
    re.IGNORECASE,
)


def load_safety_config(payload: dict) -> dict:
    defaults = {
        "enabled": True,
        "blockHardcodedSecrets": True,
        "blockSecretWebEgress": True,
        "protectSensitiveFiles": True,
        "confirmDestructiveCommands": True,
    }
    cfg_candidates = [PLUGIN_ROOT / "config.json"]
    ws_paths = payload.get("workspacePaths") or []
    cwd = payload.get("cwd")
    if isinstance(ws_paths, list) and ws_paths and isinstance(ws_paths[0], str):
        cfg_candidates.append(Path(ws_paths[0]) / ".agents" / "pilotfish.config.json")
    if isinstance(cwd, str) and cwd:
        cfg_candidates.append(Path(cwd) / ".agents" / "pilotfish.config.json")

    merged = dict(defaults)
    for path in cfg_candidates:
        try:
            if path.is_file():
                data = json.loads(path.read_text(encoding="utf-8"))
                sg = data.get("safetyGuard")
                if isinstance(sg, dict):
                    for k in defaults:
                        if isinstance(sg.get(k), bool):
                            merged[k] = sg[k]
        except Exception:
            continue
    return merged


def is_guard_self_or_test(path_str: str) -> bool:
    norm = path_str.replace("\\", "/").lower()
    return (
        norm.endswith("/hooks/safety-guard.py")
        or norm.endswith("/tests/test-plugin.sh")
        or norm.endswith("/tests/test-safety-guard.sh")
    )


def find_secret(text: str) -> str | None:
    if not text:
        return None
    for label, pat in SECRET_PATTERNS:
        for m in pat.finditer(text):
            snippet = m.group(0).lower()
            ctx_start = max(0, m.start() - 24)
            ctx_end = min(len(text), m.end() + 24)
            ctx = text[ctx_start:ctx_end].lower()
            if any(h in snippet or h in ctx for h in PLACEHOLDER_HINTS):
                continue
            return label
    return None


def is_sensitive_file(path_str: str) -> bool:
    if not path_str or is_guard_self_or_test(path_str):
        return False
    norm = path_str.replace("\\", "/")
    if "/test/" in norm or "/tests/" in norm or "/__mocks__/" in norm:
        return False
    base = os.path.basename(norm)
    if SAFE_TEMPLATE_RE.search(base):
        return False
    if SENSITIVE_BASENAME_RE.match(base):
        return True
    if "/.ssh/" in norm and not base.endswith(".pub") and base not in ("config", "known_hosts"):
        return True
    return False


def check_rm_rf(cmd: str) -> bool:
    if not re.search(r"\brm\s+[^\n]*(?:-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive[^\n]*--force)", cmd):
        return False
    # Allow cleanup of known safe ephemeral/build directories
    if SAFE_RM_TARGET_RE.search(cmd):
        return False
    return True


def emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")


def main() -> None:
    try:
        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        return

    sg = load_safety_config(payload)
    if not sg.get("enabled", True):
        return

    tc = payload.get("toolCall") or {}
    tool_name = str(tc.get("name") or "").strip().lower()
    args = tc.get("args") if isinstance(tc.get("args"), dict) else {}

    # 1. File read/write/edit checks
    if tool_name in ("read_file", "edit_file", "write_file"):
        path_str = str(args.get("Path") or args.get("path") or "")
        if sg["protectSensitiveFiles"] and is_sensitive_file(path_str):
            emit({
                "decision": "force_ask",
                "reason": f"[pilotfish-safety-guard] Sensitive file access requires explicit user confirmation: {os.path.basename(path_str)}",
            })
            return

        if sg["blockHardcodedSecrets"] and tool_name in ("edit_file", "write_file") and not is_guard_self_or_test(path_str):
            content = str(args.get("Content") or args.get("Replacement") or "")
            hit = find_secret(content)
            if hit:
                emit({
                    "decision": "deny",
                    "reason": f"[pilotfish-safety-guard] Blocked hardcoded secret ({hit}) in {tool_name}. Use environment variables or a secret manager instead.",
                })
                return

    # 2. Web search egress secret check
    elif tool_name == "search_web":
        if sg["blockSecretWebEgress"]:
            query = str(args.get("query") or "")
            hit = find_secret(query)
            if hit:
                emit({
                    "decision": "deny",
                    "reason": f"[pilotfish-safety-guard] Blocked outbound web query containing potential secret ({hit}).",
                })
                return

    # 3. Shell command checks
    elif tool_name == "run_command":
        cmd = str(args.get("CommandLine") or args.get("command") or "")
        if sg["confirmDestructiveCommands"]:
            for label, pat in CATASTROPHIC_CMD_PATTERNS:
                if pat.search(cmd):
                    emit({
                        "decision": "deny",
                        "reason": f"[pilotfish-safety-guard] Blocked catastrophic destructive command ({label}).",
                    })
                    return
            for label, pat in CONFIRM_CMD_PATTERNS:
                if pat.search(cmd):
                    emit({
                        "decision": "force_ask",
                        "reason": f"[pilotfish-safety-guard] High-risk command ({label}) requires explicit user confirmation.",
                    })
                    return
            if check_rm_rf(cmd):
                emit({
                    "decision": "force_ask",
                    "reason": "[pilotfish-safety-guard] Recursive force delete (rm -rf) outside build/tmp directories requires explicit user confirmation.",
                })
                return

    # Pass-through: empty stdout + exit 0 defers to Antigravity's native permission system
    return


if __name__ == "__main__":
    main()
