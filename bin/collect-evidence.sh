#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
OUTPUT_ROOT="${1:-$(pwd)/evidence/runs}"
RUN_ID="${EVIDENCE_RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"
OUTPUT_DIR="${OUTPUT_ROOT}/${RUN_ID}"

[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf '[ERROR] EVIDENCE_RUN_ID may contain only letters, numbers, dot, underscore, and hyphen.\n' >&2
  exit 2
}
[[ "$RUN_ID" != '.' && "$RUN_ID" != '..' ]] || {
  printf '[ERROR] EVIDENCE_RUN_ID must not be dot or dot-dot.\n' >&2
  exit 2
}

if [[ -d "$OUTPUT_DIR" ]] && [[ -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  printf '[ERROR] Evidence directory is not empty; choose a new EVIDENCE_RUN_ID: %s\n' "$OUTPUT_DIR" >&2
  exit 2
fi

if ! mkdir -p "$OUTPUT_DIR"; then
  printf '[ERROR] Cannot create evidence directory: %s\n' "$OUTPUT_DIR" >&2
  exit 1
fi

capture_required() {
  local name="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } >"${OUTPUT_DIR}/${name}.txt" 2>&1
}

capture_shell_required() {
  local name="$1" command="$2"
  {
    printf '$ %s\n' "$command"
    bash -o pipefail -c "$command"
  } >"${OUTPUT_DIR}/${name}.txt" 2>&1
}

capture_monitor_warning() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if capture_required 21-monitor-warning runuser -u agent-admin -- env \
      CPU_USAGE_OVERRIDE=25.3 MEM_USAGE_OVERRIDE=11.0 DISK_USAGE_OVERRIDE=81.0 \
      "${AGENT_HOME}/bin/run-monitor.sh"; then
      return 0
    fi
    grep -Fq 'Another monitor process is already running.' "${OUTPUT_DIR}/21-monitor-warning.txt" || break
    sleep 2
  done
  printf '[ERROR] Could not capture the monitor warning path.\n' >&2
  return 1
}

normalize_text_evidence() {
  local file temporary
  while IFS= read -r -d '' file; do
    temporary=$(mktemp "${OUTPUT_DIR}/.normalize.XXXXXX")
    awk '
      {
        sub(/[[:space:]]+$/, "")
        lines[NR] = $0
        if ($0 != "") last_nonblank = NR
      }
      END {
        for (line = 1; line <= last_nonblank; line++) print lines[line]
      }
    ' "$file" >"$temporary"
    chmod 0644 "$temporary"
    mv "$temporary" "$file"
  done < <(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.txt' -print0)
}

capture_shell_required 00-system "cat /etc/os-release; printf '\\nArchitecture: '; uname -m"
capture_required 01-sshd-effective sshd -T
capture_required 02-listening-ports ss -tulnp
capture_required 03-firewall ufw status verbose
capture_required 04-agent-admin id agent-admin
capture_required 05-agent-dev id agent-dev
capture_required 06-agent-test id agent-test
capture_required 07-agent-home ls -la "$AGENT_HOME"
capture_required 08-upload-acl getfacl "${AGENT_HOME}/upload_files"
capture_required 09-api-keys-acl getfacl "${AGENT_HOME}/api_keys"
capture_required 10-log-acl getfacl "$AGENT_LOG_DIR"
capture_required 11-environment sed -n '1,120p' /etc/agent-app/agent-app.env
capture_required 12-crontab crontab -u agent-admin -l
capture_shell_required 13-agent-process "ps -ef | grep -E 'agent_app.py|agent-app-linux-(x86|arm64)' | grep -v grep"
capture_required 14-agent-boot tail -n 30 "${AGENT_LOG_DIR}/agent-app.out"
capture_required 16-monitor-run runuser -u agent-admin -- "${AGENT_HOME}/bin/run-monitor.sh"
cron_before=$(wc -l <"${AGENT_LOG_DIR}/monitor.log" 2>/dev/null || printf 0)
capture_required 17-system-verification "${SCRIPT_DIR}/verify-system.sh" --wait-cron
cron_after=$(wc -l <"${AGENT_LOG_DIR}/monitor.log" 2>/dev/null || printf 0)
{
  printf 'monitor.log lines before verification wait: %d\n' "$cron_before"
  printf 'monitor.log lines after verification wait: %d\n' "$cron_after"
  if ((cron_after > cron_before)); then
    printf 'Result: PASS (cron appended %d line(s))\n' "$((cron_after - cron_before))"
  else
    printf 'Result: FAIL (no cron growth)\n'
    exit 1
  fi
} >"${OUTPUT_DIR}/18-cron-growth.txt"
sleep 3
capture_monitor_warning
capture_required 15-monitor-log tail -n 20 "${AGENT_LOG_DIR}/monitor.log"

cp "${AGENT_HOME}/bin/monitor.sh" "${OUTPUT_DIR}/monitor.sh"
capture_required 19-monitor-source-sha256 sha256sum "${SCRIPT_DIR}/monitor.sh" "${AGENT_HOME}/bin/monitor.sh"
capture_required 20-report "${AGENT_HOME}/bin/report.sh" --log "${AGENT_LOG_DIR}/monitor.log"
normalize_text_evidence

{
  printf '# Evidence Run %s\n\n' "$RUN_ID"
  printf -- '- Host: `%s`\n' "$(hostname)"
  printf -- '- Generated: `%s`\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf -- '- Files: `%d`\n\n' "$(find "$OUTPUT_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  printf 'Each numbered text file contains the command and captured output. Secret key contents are never collected.\n'
} >"${OUTPUT_DIR}/README.md"

printf '[INFO] Evidence collected in: %s\n' "$OUTPUT_DIR"
