#!/usr/bin/env python3
"""Reference Agent application used when the course-provided binary is absent."""

from __future__ import annotations

import http.server
import json
import os
import pathlib
import pwd
from typing import NoReturn


EXPECTED_KEY = "agent_api_key_test"


def fail(step: int, title: str, message: str) -> NoReturn:
    print(f"[{step}/5] {title:<35} [FAIL]", flush=True)
    print(f"... {message}", flush=True)
    raise SystemExit(1)


def ok(step: int, title: str, message: str) -> None:
    print(f"[{step}/5] {title:<35} [OK]", flush=True)
    print(f"... {message}", flush=True)


class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - stdlib callback name
        if self.path != "/health":
            self.send_error(404)
            return

        payload = json.dumps({"status": "ok"}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, _format: str, *_args: object) -> None:
        return


def main() -> None:
    print("Starting Agent Boot Sequence...", flush=True)

    current_user = pwd.getpwuid(os.geteuid()).pw_name
    expected_user = os.environ.get("AGENT_EXPECTED_USER")
    if os.geteuid() == 0:
        fail(1, "Checking User Account", "Root execution is not allowed.")
    if expected_user and current_user != expected_user:
        fail(1, "Checking User Account", f"Expected user {expected_user}, got {current_user}.")
    ok(1, "Checking User Account", f"Running as service user '{current_user}' (uid={os.geteuid()})")

    required = {
        "AGENT_HOME": os.environ.get("AGENT_HOME"),
        "AGENT_PORT": os.environ.get("AGENT_PORT"),
        "AGENT_UPLOAD_DIR": os.environ.get("AGENT_UPLOAD_DIR"),
        "AGENT_KEY_PATH": os.environ.get("AGENT_KEY_PATH"),
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        fail(2, "Verifying Environment Variables", f"Missing: {', '.join(missing)}")

    try:
        port = int(required["AGENT_PORT"] or "")
    except ValueError:
        fail(2, "Verifying Environment Variables", "AGENT_PORT must be an integer.")
    if port != 15034:
        fail(2, "Verifying Environment Variables", "AGENT_PORT must be 15034.")

    home_dir = pathlib.Path(required["AGENT_HOME"] or "")
    expected_upload_dir = home_dir / "upload_files"
    expected_key_path = home_dir / "api_keys" / "t_secret.key"
    if pathlib.Path(required["AGENT_UPLOAD_DIR"] or "") != expected_upload_dir:
        fail(2, "Verifying Environment Variables", f"AGENT_UPLOAD_DIR must be {expected_upload_dir}.")
    if pathlib.Path(required["AGENT_KEY_PATH"] or "") != expected_key_path:
        fail(2, "Verifying Environment Variables", f"AGENT_KEY_PATH must be {expected_key_path}.")
    ok(2, "Verifying Environment Variables", "All required Envs correct")

    key_path = pathlib.Path(required["AGENT_KEY_PATH"] or "")
    upload_dir = pathlib.Path(required["AGENT_UPLOAD_DIR"] or "")
    if not upload_dir.is_dir():
        fail(3, "Checking Required Files", f"Missing upload directory: {upload_dir}")
    try:
        key_value = key_path.read_text(encoding="utf-8").strip()
    except OSError as error:
        fail(3, "Checking Required Files", f"Cannot read key file: {error}")
    if key_value != EXPECTED_KEY:
        fail(3, "Checking Required Files", "Key file content is invalid.")
    ok(3, "Checking Required Files", "Verified key file with correct key string.")

    try:
        server = http.server.ThreadingHTTPServer(("0.0.0.0", port), HealthHandler)
    except OSError as error:
        fail(4, "Checking Port Availability", f"Port {port} is unavailable: {error}")
    with server:
        ok(4, "Checking Port Availability", f"Port {port} is available.")

        log_dir = pathlib.Path(os.environ.get("AGENT_LOG_DIR", "/var/log/agent-app"))
        if not log_dir.is_dir() or not os.access(log_dir, os.W_OK):
            fail(5, "Verifying Log Permission", f"Log directory is not writable: {log_dir}")
        ok(5, "Verifying Log Permission", f"Log directory is writable: {log_dir}")

        print("-" * 60, flush=True)
        print("All Boot Checks Passed!", flush=True)
        print("Agent READY", flush=True)

        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nAgent stopped.", flush=True)


if __name__ == "__main__":
    main()
