#!/usr/bin/env bash
set -uo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
ENV_FILE="${AGENT_ENV_FILE:-/etc/agent-app/agent-app.env}"
MONITOR_LOG_FILE="${MONITOR_LOG_FILE:-${AGENT_LOG_DIR}/monitor.log}"
PROCESS_PATTERN="${AGENT_PROCESS_PATTERN:-agent_app.py|agent-app-linux-(x86|arm64)}"
WAIT_CRON=0

passed=0
failed=0

pass() {
  passed=$((passed + 1))
  printf '[PASS] %s\n' "$*"
}

fail() {
  failed=$((failed + 1))
  printf '[FAIL] %s\n' "$*"
}

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description"
  fi
}

user_in_group() {
  local user="$1" expected="$2"
  id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$expected"
}

path_has_group_and_mode() {
  local path="$1" expected_group="$2" expected_mode="$3" group mode
  group=$(stat -c %G "$path" 2>/dev/null) || return 1
  mode=$(stat -c %a "$path" 2>/dev/null) || return 1
  [[ "$group" == "$expected_group" && "$mode" == "$expected_mode" ]]
}

sshd_effective_contains() {
  local key="$1" value="$2"
  sshd -T 2>/dev/null | awk -v key="$key" -v value="$value" '$1 == key && $2 == value { found = 1 } END { exit(found ? 0 : 1) }'
}

sshd_only_port_20022() {
  [[ "$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }' | sort -u)" == "20022" ]]
}

port_listening() {
  ss -H -ltn 2>/dev/null | awk -v suffix=":${AGENT_PORT}" '$4 ~ suffix "$" { found = 1 } END { exit(found ? 0 : 1) }'
}

ufw_only_required_ports() {
  local status rules
  status=$(ufw status 2>/dev/null) || return 1
  grep -q '^Status: active' <<<"$status" || return 1
  rules=$(awk '$2 == "ALLOW" { print $1 }' <<<"$status" | sed 's#/tcp$##' | sort -u)
  [[ "$rules" == $'15034\n20022' ]]
}

cron_installed() {
  crontab -u agent-admin -l 2>/dev/null | grep -Fq '# agent-app-monitor'
}

valid_monitor_log() {
  [[ -r "$MONITOR_LOG_FILE" ]] || return 1
  tail -n 1 "$MONITOR_LOG_FILE" | grep -Eq '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] PID:[0-9]+ CPU:[0-9]+([.][0-9]+)?% MEM:[0-9]+([.][0-9]+)?% DISK_USED:[0-9]+([.][0-9]+)?%$'
}

agent_runs_as_admin() {
  local pid owner
  pid=$(pgrep -f "$PROCESS_PATTERN" 2>/dev/null | head -n 1) || return 1
  owner=$(ps -o user= -p "$pid" 2>/dev/null | awk '{ print $1 }')
  [[ "$owner" == "agent-admin" ]]
}

boot_sequence_passed() {
  local output="${AGENT_LOG_DIR}/agent-app.out"
  [[ -r "$output" ]] || return 1
  [[ $(grep -Ec '^\[[1-5]/5\].*\[OK\]$' "$output") -eq 5 ]] || return 1
  grep -Fxq 'Agent READY' "$output"
}

cron_adds_log_line() {
  local before after
  before=$(wc -l <"$MONITOR_LOG_FILE" 2>/dev/null || printf 0)
  printf '[INFO] Waiting 70 seconds for the next cron run...\n'
  sleep 70
  after=$(wc -l <"$MONITOR_LOG_FILE" 2>/dev/null || printf 0)
  ((after > before))
}

while (($# > 0)); do
  case "$1" in
    --wait-cron) WAIT_CRON=1; shift ;;
    -h|--help)
      printf 'Usage: verify-system.sh [--wait-cron]\n'
      exit 0
      ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

printf '====== AGENT SYSTEM VERIFICATION ======\n'

check 'SSH effective port is only 20022' sshd_only_port_20022
check 'Root SSH login is disabled' sshd_effective_contains permitrootlogin no
check 'SSH port 20022 is listening' bash -c "ss -H -ltn | awk '\$4 ~ /:20022\$/ { found=1 } END { exit(found ? 0 : 1) }'"
check 'UFW is active and allows only 20022/tcp and 15034/tcp' ufw_only_required_ports

for user in agent-admin agent-dev agent-test; do
  check "Account exists: ${user}" id -u "$user"
  check "${user} belongs to agent-common" user_in_group "$user" agent-common
done
check 'agent-admin belongs to agent-core' user_in_group agent-admin agent-core
check 'agent-dev belongs to agent-core' user_in_group agent-dev agent-core
if user_in_group agent-test agent-core; then
  fail 'agent-test must not belong to agent-core'
else
  pass 'agent-test is excluded from agent-core'
fi

check 'upload_files group/mode is agent-common/2770' path_has_group_and_mode "${AGENT_HOME}/upload_files" agent-common 2770
check 'api_keys group/mode is agent-core/2770' path_has_group_and_mode "${AGENT_HOME}/api_keys" agent-core 2770
check 'log directory group/mode is agent-core/2770' path_has_group_and_mode "$AGENT_LOG_DIR" agent-core 2770
check 'upload_files ACL grants agent-common rwx' bash -c "getfacl -cp '${AGENT_HOME}/upload_files' | grep -Eq '^group:agent-common:rwx$'"
check 'AGENT_HOME ACL lets agent-common traverse to upload_files' bash -c "getfacl -cp '${AGENT_HOME}' | grep -Eq '^group:agent-common:--x$'"
check 'api_keys ACL grants agent-core rwx' bash -c "getfacl -cp '${AGENT_HOME}/api_keys' | grep -Eq '^group:agent-core:rwx$'"
check 'log ACL grants agent-core rwx' bash -c "getfacl -cp '${AGENT_LOG_DIR}' | grep -Eq '^group:agent-core:rwx$'"

check 'Environment file exists and is readable' test -r "$ENV_FILE"
check 'AGENT_HOME is configured' grep -Fxq "AGENT_HOME=${AGENT_HOME}" "$ENV_FILE"
check 'AGENT_PORT is 15034' grep -Fxq 'AGENT_PORT=15034' "$ENV_FILE"
check 'AGENT_UPLOAD_DIR is configured' grep -Fxq "AGENT_UPLOAD_DIR=${AGENT_HOME}/upload_files" "$ENV_FILE"
check 'AGENT_KEY_PATH is configured' grep -Fxq "AGENT_KEY_PATH=${AGENT_HOME}/api_keys/t_secret.key" "$ENV_FILE"
check 'AGENT_LOG_DIR is configured' grep -Fxq "AGENT_LOG_DIR=${AGENT_LOG_DIR}" "$ENV_FILE"
check 'Key content is correct' bash -c "[[ \$(< '${AGENT_HOME}/api_keys/t_secret.key') == agent_api_key_test ]]"
check 'Key owner/group/mode is agent-admin/agent-core/660' bash -c \
  "[[ \$(stat -c '%U:%G:%a' '${AGENT_HOME}/api_keys/t_secret.key') == agent-admin:agent-core:660 ]]"

check 'monitor.sh owner/group/mode is agent-dev/agent-core/750' bash -c \
  "[[ \$(stat -c '%U:%G:%a' '${AGENT_HOME}/bin/monitor.sh') == agent-dev:agent-core:750 ]]"
check 'agent-admin can execute monitor.sh' runuser -u agent-admin -- test -x "${AGENT_HOME}/bin/monitor.sh"
check 'Agent process is running' pgrep -f "$PROCESS_PATTERN"
check 'Agent process runs as agent-admin' agent_runs_as_admin
check 'Boot Sequence has five OK steps and Agent READY' boot_sequence_passed
check 'Application port 15034 is listening' port_listening
check 'agent-admin cron entry is installed' cron_installed
if ((WAIT_CRON)); then
  check 'cron adds a monitor.log line within 70 seconds' cron_adds_log_line
else
  printf '[INFO] Cron growth check skipped. Re-run with --wait-cron for automatic verification.\n'
fi
check 'monitor.log contains a valid recent record' valid_monitor_log

printf '%s\n' '----------------------------------------'
printf 'Verification result: passed=%d failed=%d\n' "$passed" "$failed"
((failed == 0))
