#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
OUTPUT_ROOT="${1:-$(pwd)/evidence/runs}"
RUN_ID=$(date '+%Y%m%d-%H%M%S')
OUTPUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"

if ! mkdir -p "$OUTPUT_DIR"; then
  printf '[ERROR] Cannot create evidence directory: %s\n' "$OUTPUT_DIR" >&2
  exit 1
fi

capture() {
  local name="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } >"${OUTPUT_DIR}/${name}.txt" 2>&1 || true
}

capture_shell() {
  local name="$1" command="$2"
  {
    printf '$ %s\n' "$command"
    bash -o pipefail -c "$command"
  } >"${OUTPUT_DIR}/${name}.txt" 2>&1 || true
}

capture 01-sshd-effective sshd -T
capture 02-listening-ports ss -tulnp
capture 03-firewall ufw status verbose
capture 04-agent-admin id agent-admin
capture 05-agent-dev id agent-dev
capture 06-agent-test id agent-test
capture 07-agent-home ls -la "$AGENT_HOME"
capture 08-upload-acl getfacl "${AGENT_HOME}/upload_files"
capture 09-api-keys-acl getfacl "${AGENT_HOME}/api_keys"
capture 10-log-acl getfacl "$AGENT_LOG_DIR"
capture 11-environment sed -n '1,120p' /etc/agent-app/agent-app.env
capture 12-crontab crontab -u agent-admin -l
capture_shell 13-agent-process "ps -ef | grep -E 'agent_app.py|agent-app-linux-(x86|arm64)' | grep -v grep"
capture_shell 14-agent-boot "tail -n 30 '${AGENT_LOG_DIR}/agent-app.out'"
capture_shell 15-monitor-log "tail -n 20 '${AGENT_LOG_DIR}/monitor.log'"
capture 16-monitor-run runuser -u agent-admin -- "${AGENT_HOME}/bin/run-monitor.sh"
capture 17-system-verification "${SCRIPT_DIR}/verify-system.sh" --wait-cron

cp "${AGENT_HOME}/bin/monitor.sh" "${OUTPUT_DIR}/monitor.sh"

{
  printf '# Evidence Run %s\n\n' "$RUN_ID"
  printf -- '- Host: `%s`\n' "$(hostname)"
  printf -- '- Generated: `%s`\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf -- '- Files: `%d`\n\n' "$(find "$OUTPUT_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  printf 'Each numbered text file contains the command and captured output. Secret key contents are never collected.\n'
} >"${OUTPUT_DIR}/README.md"

printf '[INFO] Evidence collected in: %s\n' "$OUTPUT_DIR"
