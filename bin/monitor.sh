#!/usr/bin/env bash
set -Eeuo pipefail

AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_PROCESS_PATTERN="${AGENT_PROCESS_PATTERN:-agent_app.py|agent-app-linux-(x86|arm64)}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
MONITOR_LOG_FILE="${MONITOR_LOG_FILE:-${AGENT_LOG_DIR}/monitor.log}"
CPU_THRESHOLD="${CPU_THRESHOLD:-20}"
MEM_THRESHOLD="${MEM_THRESHOLD:-10}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-10485760}"
LOG_MAX_FILES="${LOG_MAX_FILES:-10}"
CPU_SAMPLE_INTERVAL="${CPU_SAMPLE_INTERVAL:-1}"

PGREP_BIN="${PGREP_BIN:-pgrep}"
SS_BIN="${SS_BIN:-ss}"
DF_BIN="${DF_BIN:-df}"
UFW_BIN="${UFW_BIN:-ufw}"
FIREWALL_CMD_BIN="${FIREWALL_CMD_BIN:-firewall-cmd}"
UFW_CONF="${UFW_CONF:-/etc/ufw/ufw.conf}"
PROC_ROOT="${PROC_ROOT:-/proc}"

warn() {
  printf '[WARNING] %s\n' "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

is_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

validate_config() {
  [[ "$AGENT_PORT" =~ ^[0-9]+$ ]] || die "AGENT_PORT must be an integer."
  [[ "$LOG_MAX_BYTES" =~ ^[1-9][0-9]*$ ]] || die "LOG_MAX_BYTES must be at least 1."
  [[ "$LOG_MAX_FILES" =~ ^[1-9][0-9]*$ ]] || die "LOG_MAX_FILES must be at least 1."
  is_number "$CPU_SAMPLE_INTERVAL" || die "CPU_SAMPLE_INTERVAL must be numeric."
  is_number "$CPU_THRESHOLD" || die "CPU_THRESHOLD must be numeric."
  is_number "$MEM_THRESHOLD" || die "MEM_THRESHOLD must be numeric."
  is_number "$DISK_THRESHOLD" || die "DISK_THRESHOLD must be numeric."
}

process_pid() {
  local pids
  if ! pids=$("$PGREP_BIN" -f -- "$AGENT_PROCESS_PATTERN" 2>/dev/null); then
    return 1
  fi
  printf '%s\n' "$pids" | awk 'NF { print; exit }'
}

port_is_listening() {
  "$SS_BIN" -H -ltn 2>/dev/null | awk -v suffix=":${AGENT_PORT}" '
    $4 ~ suffix "$" { found = 1 }
    END { exit(found ? 0 : 1) }
  '
}

firewall_is_active() {
  case "${FIREWALL_STATUS_OVERRIDE:-}" in
    active) return 0 ;;
    inactive) return 1 ;;
  esac

  if command -v "$UFW_BIN" >/dev/null 2>&1; then
    if "$UFW_BIN" status 2>/dev/null \
      | awk '$1 == "Status:" && $2 == "active" { found = 1 } END { exit(found ? 0 : 1) }'; then
      return 0
    fi

    # `ufw status` commonly requires root. Cron runs as agent-admin, so use
    # UFW's world-readable enable flag as a non-privileged fallback.
    if [[ -r "$UFW_CONF" ]] && grep -Eq '^[[:space:]]*ENABLED=yes([[:space:]]|$)' "$UFW_CONF"; then
      return 0
    fi
  fi

  if command -v "$FIREWALL_CMD_BIN" >/dev/null 2>&1; then
    [[ "$("$FIREWALL_CMD_BIN" --state 2>/dev/null || true)" == "running" ]]
    return
  fi

  return 1
}

cpu_snapshot() {
  awk '/^cpu / {
    idle = $5 + $6
    total = 0
    for (i = 2; i <= NF; i++) total += $i
    print idle, total
    exit
  }' "${PROC_ROOT}/stat"
}

cpu_usage() {
  if [[ -n "${CPU_USAGE_OVERRIDE:-}" ]]; then
    printf '%.1f\n' "$CPU_USAGE_OVERRIDE"
    return
  fi

  local idle1 total1 idle2 total2 delta_idle delta_total
  read -r idle1 total1 < <(cpu_snapshot)
  sleep "$CPU_SAMPLE_INTERVAL"
  read -r idle2 total2 < <(cpu_snapshot)
  delta_idle=$((idle2 - idle1))
  delta_total=$((total2 - total1))
  ((delta_total > 0)) || die "Unable to calculate CPU usage from ${PROC_ROOT}/stat."
  awk -v idle="$delta_idle" -v total="$delta_total" 'BEGIN { printf "%.1f\n", 100 * (total - idle) / total }'
}

memory_usage() {
  if [[ -n "${MEM_USAGE_OVERRIDE:-}" ]]; then
    printf '%.1f\n' "$MEM_USAGE_OVERRIDE"
    return
  fi

  awk '
    $1 == "MemTotal:" { total = $2 }
    $1 == "MemAvailable:" { available = $2 }
    END {
      if (total <= 0) exit 1
      printf "%.1f\n", 100 * (total - available) / total
    }
  ' "${PROC_ROOT}/meminfo" || die "Unable to calculate memory usage from ${PROC_ROOT}/meminfo."
}

disk_usage() {
  if [[ -n "${DISK_USAGE_OVERRIDE:-}" ]]; then
    printf '%.1f\n' "$DISK_USAGE_OVERRIDE"
    return
  fi

  "$DF_BIN" -P / | awk 'NR == 2 { gsub(/%/, "", $5); printf "%.1f\n", $5; found = 1 } END { if (!found) exit 1 }' \
    || die "Unable to calculate root filesystem usage."
}

greater_than() {
  awk -v value="$1" -v threshold="$2" 'BEGIN { exit(value > threshold ? 0 : 1) }'
}

file_size() {
  if stat -c %s "$1" >/dev/null 2>&1; then
    stat -c %s "$1"
  else
    stat -f %z "$1"
  fi
}

rotate_log_if_needed() {
  local incoming_bytes="${1:-0}"
  [[ -f "$MONITOR_LOG_FILE" ]] || return 0

  local size max_rotated index
  size=$(file_size "$MONITOR_LOG_FILE")
  ((size + incoming_bytes >= LOG_MAX_BYTES)) || return 0

  if ((LOG_MAX_FILES == 1)); then
    : >"$MONITOR_LOG_FILE"
    return 0
  fi

  max_rotated=$((LOG_MAX_FILES - 1))
  rm -f -- "${MONITOR_LOG_FILE}.${max_rotated}"
  for ((index = max_rotated - 1; index >= 1; index--)); do
    if [[ -f "${MONITOR_LOG_FILE}.${index}" ]]; then
      mv -- "${MONITOR_LOG_FILE}.${index}" "${MONITOR_LOG_FILE}.$((index + 1))"
    fi
  done
  mv -- "$MONITOR_LOG_FILE" "${MONITOR_LOG_FILE}.1"
}

main() {
  validate_config
  mkdir -p -- "$AGENT_LOG_DIR"

  if command -v flock >/dev/null 2>&1; then
    exec 9>"${AGENT_LOG_DIR}/monitor.lock"
    flock -n 9 || die "Another monitor process is already running."
  fi

  printf '====== SYSTEM MONITOR RESULT ======\n\n'
  printf '[HEALTH CHECK]\n'

  local pid cpu mem disk timestamp log_line
  if ! pid=$(process_pid); then
    printf "Checking process '%s'... [FAIL]\n" "$AGENT_PROCESS_PATTERN"
    exit 1
  fi
  printf "Checking process '%s'... [OK] (PID: %s)\n" "$AGENT_PROCESS_PATTERN" "$pid"

  if ! port_is_listening; then
    printf 'Checking port %s... [FAIL]\n' "$AGENT_PORT"
    exit 1
  fi
  printf 'Checking port %s... [OK]\n' "$AGENT_PORT"

  if firewall_is_active; then
    printf 'Checking firewall... [OK]\n'
  else
    warn 'Firewall is inactive or its status could not be determined.'
  fi

  cpu=$(cpu_usage)
  mem=$(memory_usage)
  disk=$(disk_usage)

  printf '\n[RESOURCE MONITORING]\n'
  printf 'CPU Usage : %s%%\n' "$cpu"
  printf 'MEM Usage : %s%%\n' "$mem"
  printf 'DISK Used : %s%%\n' "$disk"

  greater_than "$cpu" "$CPU_THRESHOLD" && warn "CPU threshold exceeded (${cpu}% > ${CPU_THRESHOLD}%)"
  greater_than "$mem" "$MEM_THRESHOLD" && warn "MEM threshold exceeded (${mem}% > ${MEM_THRESHOLD}%)"
  greater_than "$disk" "$DISK_THRESHOLD" && warn "DISK_USED threshold exceeded (${disk}% > ${DISK_THRESHOLD}%)"

  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  log_line="[${timestamp}] PID:${pid} CPU:${cpu}% MEM:${mem}% DISK_USED:${disk}%"
  rotate_log_if_needed "$((${#log_line} + 1))"
  printf '%s\n' "$log_line" >>"$MONITOR_LOG_FILE"
  printf '\n[INFO] Log appended: %s\n' "$MONITOR_LOG_FILE"
}

main "$@"
