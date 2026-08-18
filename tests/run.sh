#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
APP_PID=""
passed=0

cleanup() {
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

pass() {
  passed=$((passed + 1))
  printf '[PASS] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file="$1" text="$2" description="$3"
  if grep -Fq "$text" "$file"; then
    pass "$description"
  else
    printf '%s\n' "--- ${file} ---" >&2
    sed -n '1,120p' "$file" >&2 || true
    fail "$description"
  fi
}

assert_exists() {
  [[ -e "$1" ]] && pass "$2" || fail "$2"
}

test_syntax() {
  local script
  while IFS= read -r script; do
    bash -n "$script" || fail "Syntax: ${script}"
  done < <(find "${REPO_ROOT}/bin" "${REPO_ROOT}/tests" -type f -name '*.sh' | sort)
  python3 -m py_compile "${REPO_ROOT}/app/agent_app.py"
  pass 'All Bash and Python files parse successfully'
}

test_setup_dry_run() {
  local output="${TEST_TMP}/setup-dry-run.txt"
  "${REPO_ROOT}/bin/setup-system.sh" --reset-firewall --start-app >"$output"
  assert_contains "$output" 'ufw --force reset' 'Dry run plans a firewall reset'
  assert_contains "$output" 'ufw allow 20022/tcp' 'Dry run allows SSH port 20022'
  assert_contains "$output" 'ufw allow 15034/tcp' 'Dry run allows app port 15034'
  assert_contains "$output" 'agent-app-monitor' 'Dry run plans the minute cron entry'
  assert_contains "$output" 'start application as agent-admin' 'Dry run plans non-root app startup'
}

test_setup_provided_binary_selection() {
  local fixture_root binary_name output
  fixture_root="${TEST_TMP}/provided-app-repo"
  output="${TEST_TMP}/provided-app-selection.txt"
  case "$(uname -m)" in
    x86_64|amd64) binary_name='agent-app-linux-x86' ;;
    arm64|aarch64) binary_name='agent-app-linux-arm64' ;;
    *)
      pass 'Provided application selection is skipped on an unsupported test architecture'
      return
      ;;
  esac

  mkdir -p "${fixture_root}/bin" "${fixture_root}/app" "${fixture_root}/config"
  cp "${REPO_ROOT}/bin/setup-system.sh" "${fixture_root}/bin/setup-system.sh"
  cp "${REPO_ROOT}/config/sshd-agent-app.conf" "${fixture_root}/config/sshd-agent-app.conf"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"${fixture_root}/app/${binary_name}"

  "${fixture_root}/bin/setup-system.sh" --reset-firewall >"$output"
  assert_contains "$output" "Selected provided application: ${binary_name}" \
    'Setup prefers the provided binary for the current architecture'
}

make_fake_commands() {
  local fake_bin="${TEST_TMP}/fake-bin"
  mkdir -p "$fake_bin"

  cat >"${fake_bin}/pgrep" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOCK_PROCESS_UP:-1}" == "1" ]]; then
  printf '%s\n' 4242
  exit 0
fi
exit 1
EOF

  cat >"${fake_bin}/ss" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOCK_PORT_UP:-1}" == "1" ]]; then
  printf '%s\n' 'LISTEN 0 128 0.0.0.0:15034 0.0.0.0:*'
fi
EOF

  cat >"${fake_bin}/ufw" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'ERROR: You need to be root to run this script' >&2
exit 1
EOF

  chmod +x "${fake_bin}/pgrep" "${fake_bin}/ss" "${fake_bin}/ufw"
  printf '%s\n' "$fake_bin"
}

run_monitor() {
  local fake_bin="$1" output="$2"
  PATH="${fake_bin}:$PATH" \
    PGREP_BIN=pgrep \
    SS_BIN=ss \
    FIREWALL_STATUS_OVERRIDE="${FIREWALL_STATUS_OVERRIDE:-active}" \
    CPU_USAGE_OVERRIDE="${CPU_USAGE_OVERRIDE:-25.3}" \
    MEM_USAGE_OVERRIDE="${MEM_USAGE_OVERRIDE:-5.2}" \
    DISK_USAGE_OVERRIDE="${DISK_USAGE_OVERRIDE:-23}" \
    AGENT_LOG_DIR="${TEST_TMP}/logs" \
    MONITOR_LOG_FILE="${TEST_TMP}/logs/monitor.log" \
    LOG_MAX_BYTES="${LOG_MAX_BYTES:-10485760}" \
    LOG_MAX_FILES="${LOG_MAX_FILES:-10}" \
    MOCK_PROCESS_UP="${MOCK_PROCESS_UP:-1}" \
    MOCK_PORT_UP="${MOCK_PORT_UP:-1}" \
    "${REPO_ROOT}/bin/monitor.sh" >"$output" 2>&1
}

test_monitor_success_and_warnings() {
  local fake_bin output log
  fake_bin=$(make_fake_commands)
  output="${TEST_TMP}/monitor-success.txt"
  log="${TEST_TMP}/logs/monitor.log"

  run_monitor "$fake_bin" "$output"
  assert_contains "$output" '[OK] (PID: 4242)' 'Monitor validates the process'
  assert_contains "$output" 'Checking port 15034... [OK]' 'Monitor validates port 15034'
  assert_contains "$output" '[WARNING] CPU threshold exceeded' 'Monitor prints threshold warnings'
  assert_contains "$log" 'PID:4242 CPU:25.3% MEM:5.2% DISK_USED:23.0%' 'Monitor appends the required log format'
}

test_monitor_all_warning_paths() {
  local fake_bin output
  fake_bin="${TEST_TMP}/fake-bin"
  output="${TEST_TMP}/monitor-all-warnings.txt"

  FIREWALL_STATUS_OVERRIDE=inactive \
    CPU_USAGE_OVERRIDE=21 \
    MEM_USAGE_OVERRIDE=11 \
    DISK_USAGE_OVERRIDE=81 \
    run_monitor "$fake_bin" "$output"

  assert_contains "$output" '[WARNING] Firewall is inactive' 'Inactive firewall produces a non-fatal warning'
  assert_contains "$output" '[WARNING] CPU threshold exceeded' 'CPU above 20 percent produces a warning'
  assert_contains "$output" '[WARNING] MEM threshold exceeded' 'Memory above 10 percent produces a warning'
  assert_contains "$output" '[WARNING] DISK_USED threshold exceeded' 'Disk above 80 percent produces a warning'
}

test_monitor_unprivileged_ufw_fallback() {
  local fake_bin output ufw_conf
  fake_bin="${TEST_TMP}/fake-bin"
  output="${TEST_TMP}/monitor-ufw-fallback.txt"
  ufw_conf="${TEST_TMP}/ufw.conf"
  printf '%s\n' 'ENABLED=yes' >"$ufw_conf"

  FIREWALL_STATUS_OVERRIDE=auto UFW_CONF="$ufw_conf" run_monitor "$fake_bin" "$output"
  assert_contains "$output" 'Checking firewall... [OK]' 'Non-root cron detects active UFW from its enable flag'
}

test_monitor_health_failures() {
  local fake_bin output
  fake_bin="${TEST_TMP}/fake-bin"
  output="${TEST_TMP}/monitor-process-fail.txt"
  if MOCK_PROCESS_UP=0 run_monitor "$fake_bin" "$output"; then
    fail 'Monitor must exit non-zero when the process is down'
  fi
  assert_contains "$output" "Checking process" 'Process failure is reported'

  output="${TEST_TMP}/monitor-port-fail.txt"
  if MOCK_PROCESS_UP=1 MOCK_PORT_UP=0 run_monitor "$fake_bin" "$output"; then
    fail 'Monitor must exit non-zero when the port is down'
  fi
  assert_contains "$output" 'Checking port 15034... [FAIL]' 'Port failure is reported'
}

test_monitor_rotation() {
  local fake_bin output log
  fake_bin="${TEST_TMP}/fake-bin"
  output="${TEST_TMP}/monitor-rotation.txt"
  log="${TEST_TMP}/logs/monitor.log"
  printf '%0200d' 0 >"$log"

  LOG_MAX_BYTES=10 LOG_MAX_FILES=3 run_monitor "$fake_bin" "$output"
  assert_exists "${log}.1" 'Oversized monitor.log is rotated'
  [[ $(find "${TEST_TMP}/logs" -maxdepth 1 -name 'monitor.log*' | wc -l | tr -d ' ') -le 3 ]] \
    && pass 'Log rotation respects the maximum file count' \
    || fail 'Log rotation exceeds the maximum file count'
}

test_report() {
  local log output filtered bounded
  log="${TEST_TMP}/report.log"
  output="${TEST_TMP}/report.txt"
  filtered="${TEST_TMP}/report-filtered.txt"
  bounded="${TEST_TMP}/report-bounded.txt"
  cat >"$log" <<'EOF'
[2026-02-25 13:58:01] PID:1 CPU:10.0% MEM:5.0% DISK_USED:20.0%
[2026-02-25 13:59:01] PID:1 CPU:20.0% MEM:10.0% DISK_USED:40.0%
[2026-02-25 14:00:01] PID:1 CPU:30.0% MEM:15.0% DISK_USED:60.0%
EOF

  "${REPO_ROOT}/bin/report.sh" --log "$log" >"$output"
  assert_contains "$output" 'Average : 20.0%' 'Report calculates CPU average'
  assert_contains "$output" 'Maximum : 60.0% at 2026-02-25 14:00:01' 'Report calculates disk maximum'
  assert_contains "$output" 'Data Points: 3 samples' 'Report counts samples'

  "${REPO_ROOT}/bin/report.sh" --log "$log" --from '2026-02-25 13:59:01' >"$filtered"
  assert_contains "$filtered" 'Data Points: 2 samples' 'Report filters by time range'

  "${REPO_ROOT}/bin/report.sh" --log "$log" \
    --from '2026-02-25 13:59:01' --to '2026-02-25 13:59:01' >"$bounded"
  assert_contains "$bounded" 'Data Points: 1 samples' 'Report applies both start and end boundaries'
}

test_archive_retention() {
  local log_dir archive_dir output fake_bin
  log_dir="${TEST_TMP}/retention-logs"
  archive_dir="${TEST_TMP}/retention-archive"
  output="${TEST_TMP}/retention.txt"
  mkdir -p "$log_dir" "$archive_dir"
  printf 'old log\n' >"${log_dir}/old.log"
  printf 'fresh log\n' >"${log_dir}/fresh.log"
  touch -t 202001010000 "${log_dir}/old.log"

  AGENT_LOG_DIR="$log_dir" ARCHIVE_DIR="$archive_dir" \
    "${REPO_ROOT}/bin/archive-logs.sh" >"$output"
  assert_exists "${archive_dir}/old.log.gz" 'Logs older than seven days are compressed into the archive'
  [[ ! -e "${log_dir}/old.log" ]] && pass 'Archived source log is removed' || fail 'Archived source log remains'
  assert_exists "${log_dir}/fresh.log" 'Logs newer than seven days remain active'

  touch -t 202001010000 "${archive_dir}/old.log.gz"
  AGENT_LOG_DIR="$log_dir" ARCHIVE_DIR="$archive_dir" \
    "${REPO_ROOT}/bin/archive-logs.sh" >>"$output"
  [[ ! -e "${archive_dir}/old.log.gz" ]] && pass 'Archives older than thirty days are deleted' || fail 'Expired archive remains'
  assert_contains "$output" 'No log files were old enough to archive' 'No matching log files are handled safely'

  AGENT_LOG_DIR="${TEST_TMP}/missing-log-dir" ARCHIVE_DIR="$archive_dir" \
    "${REPO_ROOT}/bin/archive-logs.sh" >"${TEST_TMP}/retention-missing.txt"
  assert_contains "${TEST_TMP}/retention-missing.txt" '[WARNING] Log directory does not exist' 'Missing log directory is handled safely'

  fake_bin="${TEST_TMP}/retention-fake-bin"
  mkdir -p "$fake_bin"
  cat >"${fake_bin}/mkdir" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${fake_bin}/mkdir"
  PATH="${fake_bin}:$PATH" AGENT_LOG_DIR="$log_dir" ARCHIVE_DIR="${TEST_TMP}/permission-denied" \
    "${REPO_ROOT}/bin/archive-logs.sh" >"${TEST_TMP}/retention-permission.txt"
  assert_contains "${TEST_TMP}/retention-permission.txt" '[WARNING] Cannot create archive directory' \
    'Archive permission failures are handled safely'
}

test_reference_app() {
  local home output response attempt
  home="${TEST_TMP}/agent-home"
  output="${TEST_TMP}/agent-app.txt"
  response="${TEST_TMP}/health.json"
  mkdir -p "${home}/upload_files" "${home}/api_keys" "${home}/logs"
  printf '%s\n' agent_api_key_test >"${home}/api_keys/t_secret.key"

  AGENT_HOME="$home" \
    AGENT_PORT=15034 \
    AGENT_UPLOAD_DIR="${home}/upload_files" \
    AGENT_KEY_PATH="${home}/api_keys/t_secret.key" \
    AGENT_LOG_DIR="${home}/logs" \
    AGENT_EXPECTED_USER="$(id -un)" \
    python3 "${REPO_ROOT}/app/agent_app.py" >"$output" 2>&1 &
  APP_PID=$!

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS http://127.0.0.1:15034/health >"$response" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done

  assert_contains "$output" '[5/5] Verifying Log Permission' 'Reference app reaches Boot Sequence step 5'
  assert_contains "$output" 'Agent READY' 'Reference app reports Agent READY'
  assert_contains "$response" '"status": "ok"' 'Reference app listens on 0.0.0.0:15034'

  kill "$APP_PID"
  wait "$APP_PID" 2>/dev/null || true
  APP_PID=""
}

test_syntax
test_setup_dry_run
test_setup_provided_binary_selection
test_monitor_success_and_warnings
test_monitor_all_warning_paths
test_monitor_unprivileged_ufw_fallback
test_monitor_health_failures
test_monitor_rotation
test_report
test_archive_retention
test_reference_app

printf '\nAll tests passed: %d assertions\n' "$passed"
