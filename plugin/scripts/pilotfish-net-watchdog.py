#!/usr/bin/env python3
"""Pilotfish Network Watchdog & Auto-Resume Sentinel.

Lightweight, dependency-free network probe and watchdog for Antigravity.
Monitors internet connectivity, detects outages, prevents failed retries during
disconnects, and wakes Antigravity up via background task completion upon restoration.

Usage:
  # Fast one-shot probe (<50ms): returns 0 if online, 1 if offline
  python3 pilotfish-net-watchdog.py --probe

  # Wait until connection is stable (3 consecutive successes), then exit 0:
  python3 pilotfish-net-watchdog.py --wait-for-online [--interval 5] [--consecutive 3]

  # Passive sentinel for long autonomous runs: sleeps while online; if connection drops
  # and returns, exits 0 to trigger reactive wakeup in Antigravity:
  python3 pilotfish-net-watchdog.py --sentinel [--interval 10]
"""

import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_ENDPOINTS = [
    ("1.1.1.1", 53),        # Cloudflare DNS
    ("8.8.8.8", 53),        # Google DNS
    ("9.9.9.9", 53),        # Quad9 DNS
    ("208.67.222.222", 53), # OpenDNS
]

CONFIG_PATH = Path.home() / ".gemini" / "config" / "plugins" / "pilotfish-agy" / "config.json"


def load_config_endpoints() -> list[tuple[str, int]]:
    """Loads configured endpoints from config.json if available."""
    if CONFIG_PATH.is_file():
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
            endpoints_str = data.get("networkGuard", {}).get("endpoints", [])
            parsed = []
            for ep in endpoints_str:
                host, port = ep.split(":")
                parsed.append((host.strip(), int(port.strip())))
            if parsed:
                return parsed
        except Exception:
            pass
    return DEFAULT_ENDPOINTS


def check_endpoint(host: str, port: int, timeout_sec: float) -> tuple[bool, float]:
    """Attempts a TCP connection to the specified endpoint."""
    t0 = time.monotonic()
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout_sec)
    try:
        sock.connect((host, port))
        sock.close()
        latency_ms = (time.monotonic() - t0) * 1000.0
        return True, latency_ms
    except (socket.timeout, OSError):
        try:
            sock.close()
        except Exception:
            pass
        return False, 0.0


def probe_online(endpoints: list[tuple[str, int]], timeout_sec: float = 1.5) -> tuple[bool, str, float]:
    """Probes endpoints sequentially. Returns (is_online, successful_endpoint, latency_ms)."""
    for host, port in endpoints:
        ok, latency = check_endpoint(host, port, timeout_sec)
        if ok:
            return True, f"{host}:{port}", latency
    return False, "", 0.0


def send_tg_notification(message: str) -> None:
    """Sends a notification via tg-notify if installed."""
    try:
        subprocess.run(["tg-notify", message], timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def run_probe(endpoints: list[tuple[str, int]], timeout_sec: float) -> int:
    online, ep, latency = probe_online(endpoints, timeout_sec)
    res = {
        "status": "online" if online else "offline",
        "endpoint": ep if online else None,
        "latency_ms": round(latency, 2) if online else None,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
    }
    print(json.dumps(res, indent=2))
    sys.stdout.flush()
    return 0 if online else 1


def run_wait_for_online(
    endpoints: list[tuple[str, int]],
    interval: float,
    consecutive_required: int,
    timeout_total: float,
    notify: bool,
    checkpoint_file: str | None,
) -> int:
    start_time = time.monotonic()
    consecutive = 0
    last_ep = ""
    last_latency = 0.0

    print(
        f"[pilotfish-watchdog] Waiting for connection restoration "
        f"(requires {consecutive_required} consecutive stable probes, interval {interval}s)...",
        file=sys.stderr,
    )
    sys.stderr.flush()

    while True:
        if timeout_total > 0 and (time.monotonic() - start_time) > timeout_total:
            print(json.dumps({"status": "timeout_exceeded", "elapsed_sec": round(time.monotonic() - start_time, 1)}))
            sys.stdout.flush()
            return 2

        online, ep, latency = probe_online(endpoints, timeout_sec=2.0)
        if online:
            consecutive += 1
            last_ep = ep
            last_latency = latency
            print(
                f"[pilotfish-watchdog] Probe success {consecutive}/{consecutive_required} via {ep} ({latency:.1f}ms)",
                file=sys.stderr,
            )
            sys.stderr.flush()
            if consecutive >= consecutive_required:
                elapsed = round(time.monotonic() - start_time, 2)
                iso_now = datetime.now(timezone.utc).isoformat()
                result = {
                    "event": "INTERNET_RESTORED",
                    "status": "online",
                    "restored_at_utc": iso_now,
                    "endpoint": last_ep,
                    "latency_ms": round(last_latency, 2),
                    "elapsed_seconds": elapsed,
                    "consecutive_successes": consecutive,
                }
                print(json.dumps(result, indent=2))
                sys.stdout.flush()

                # Update checkpoint file if provided
                if checkpoint_file and os.path.exists(checkpoint_file):
                    try:
                        with open(checkpoint_file, "r", encoding="utf-8") as f:
                            content = f.read()
                        updated = content.replace("PAUSED_NETWORK_OFFLINE", "NETWORK_RESTORED_PENDING_RESUME")
                        with open(checkpoint_file, "w", encoding="utf-8") as f:
                            f.write(updated)
                    except Exception as e:
                        print(f"[pilotfish-watchdog] Warning: failed to update checkpoint: {e}", file=sys.stderr)

                if notify:
                    send_tg_notification("⚠️ <b>Pilotfish:</b> Conexão de rede restabelecida! Retomando tarefas pausadas...")

                return 0
        else:
            if consecutive > 0:
                print("[pilotfish-watchdog] Flapping detected: connection dropped again, resetting counter.", file=sys.stderr)
                sys.stderr.flush()
            consecutive = 0

        time.sleep(interval)


def run_sentinel(
    endpoints: list[tuple[str, int]],
    interval: float,
    consecutive_required: int,
    notify: bool,
    checkpoint_file: str | None,
) -> int:
    """Passive sentinel: monitors connection in background.

    If network drops and subsequently recovers, exits 0 to wake Antigravity up.
    """
    print(f"[pilotfish-sentinel] Passive sentinel started (interval={interval}s). Monitoring connectivity...", file=sys.stderr)
    sys.stderr.flush()

    offline_count = 0
    disconnected_at = None

    while True:
        online, ep, latency = probe_online(endpoints, timeout_sec=1.5)

        if not online:
            offline_count += 1
            if offline_count == 2:  # 2 consecutive failures confirm outage
                disconnected_at = datetime.now(timezone.utc).isoformat()
                print(
                    f"[pilotfish-sentinel] NETWORK OUTAGE CONFIRMED at {disconnected_at}! "
                    f"Switching to recovery mode...",
                    file=sys.stderr,
                )
                sys.stderr.flush()

                # Call wait_for_online logic
                res = run_wait_for_online(
                    endpoints=endpoints,
                    interval=interval,
                    consecutive_required=consecutive_required,
                    timeout_total=0,
                    notify=notify,
                    checkpoint_file=checkpoint_file,
                )
                return res
        else:
            offline_count = 0

        time.sleep(interval)


def main() -> int:
    signal.signal(signal.SIGINT, lambda sig, frame: sys.exit(130))
    signal.signal(signal.SIGTERM, lambda sig, frame: sys.exit(143))

    parser = argparse.ArgumentParser(description="Pilotfish Network Watchdog & Auto-Resume Sentinel")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--probe", "--check", action="store_true", help="One-shot fast connection probe (<50ms)")
    group.add_argument("--wait-for-online", action="store_true", help="Loop until connection is reliably restored, then exit 0")
    group.add_argument("--sentinel", action="store_true", help="Passive background monitor that triggers wakeup after outage recovery")

    parser.add_argument("--interval", type=float, default=5.0, help="Interval in seconds between probes (default: 5.0)")
    parser.add_argument("--consecutive", type=int, default=3, help="Consecutive successes required to declare restored (default: 3)")
    parser.add_argument("--timeout", type=float, default=0.0, help="Max wait time in seconds (0 = unlimited)")
    parser.add_argument("--notify", action="store_true", default=True, help="Send Telegram notification via tg-notify on restore")
    parser.add_argument("--no-notify", action="store_false", dest="notify", help="Disable Telegram notification")
    parser.add_argument("--checkpoint", type=str, default=None, help="Path to pilotfish-checkpoint.md to update on restore")
    parser.add_argument("--endpoints", nargs="*", default=None, help="Custom endpoints e.g. 1.1.1.1:53 8.8.8.8:53")

    args = parser.parse_args()

    if args.endpoints:
        endpoints = []
        for ep in args.endpoints:
            host, port = ep.split(":")
            endpoints.append((host.strip(), int(port.strip())))
    else:
        endpoints = load_config_endpoints()

    if args.probe:
        return run_probe(endpoints, timeout_sec=1.5)
    elif args.wait_for_online:
        return run_wait_for_online(
            endpoints=endpoints,
            interval=args.interval,
            consecutive_required=args.consecutive,
            timeout_total=args.timeout,
            notify=args.notify,
            checkpoint_file=args.checkpoint,
        )
    elif args.sentinel:
        return run_sentinel(
            endpoints=endpoints,
            interval=args.interval,
            consecutive_required=args.consecutive,
            notify=args.notify,
            checkpoint_file=args.checkpoint,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
