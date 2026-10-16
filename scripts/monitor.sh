#!/usr/bin/env bash
set -Eeuo pipefail

# 점검 대상 및 로그 경로 기본값
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_PROCESS_PATTERN="${AGENT_PROCESS_PATTERN:-^/home/agent-admin/agent-app/agent-app$}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
MONITOR_LOG_FILE="${AGENT_LOG_DIR}/monitor.log"

# 자원 사용률 경고 기준 및 로그 회전 크기 기본값
CPU_THRESHOLD="${CPU_THRESHOLD:-20}"
MEM_THRESHOLD="${MEM_THRESHOLD:-10}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-10485760}"

# 표준 출력용 경고 메시지
warn() {
  printf '[WARNING] %s\n' "$*"
}

# 표준 오류 출력 및 종료 코드 1 반환
die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

# 0 이상의 정수 또는 소수 형식 확인
is_number() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

# 포트·경고 기준·로그 크기 설정값 유효성 검사
validate_config() {
  [[ "$AGENT_PORT" =~ ^[0-9]+$ ]] || die "AGENT_PORT must be an integer."
  [[ "$LOG_MAX_BYTES" =~ ^[1-9][0-9]*$ ]] || die "LOG_MAX_BYTES must be at least 1."

  is_number "$CPU_THRESHOLD" || die "CPU_THRESHOLD must be numeric."
  is_number "$MEM_THRESHOLD" || die "MEM_THRESHOLD must be numeric."
  is_number "$DISK_THRESHOLD" || die "DISK_THRESHOLD must be numeric."
}

# 실행 경로가 일치하는 첫 번째 앱 프로세스 PID 조회
process_pid() {
  pgrep -f -- "$AGENT_PROCESS_PATTERN" 2>/dev/null | awk 'NR == 1 { print }'
}

# 설정된 TCP 포트의 LISTEN 상태 확인
port_is_listening() {
  ss -H -ltn "sport = :${AGENT_PORT}" 2>/dev/null | grep -q .
}

# UFW 활성 상태 확인
firewall_is_active() {
  if ufw status 2>/dev/null \
    | awk '$1 == "Status:" && $2 == "active" { found = 1 } END { exit(found ? 0 : 1) }'; then
    return 0
  fi

  # 일반 계정 cron 실행을 위한 UFW 설정 파일의 활성화 값 확인
  [[ -r /etc/ufw/ufw.conf ]] && grep -Eq '^[[:space:]]*ENABLED=yes([[:space:]]|$)' /etc/ufw/ufw.conf
}

# /proc/stat의 유휴 시간과 전체 CPU 시간 조회
cpu_snapshot() {
  awk '/^cpu / {
    idle = $5 + $6
    total = 0
    for (i = 2; i <= NF; i++) total += $i
    print idle, total
    exit
  }' /proc/stat
}

# 1초 간격의 /proc/stat 차이를 이용한 CPU 사용률 계산
# 계산식: (전체 시간 증가량 - 유휴 시간 증가량) / 전체 시간 증가량 × 100
cpu_usage() {
  local idle1 total1 idle2 total2 delta_idle delta_total

  read -r idle1 total1 < <(cpu_snapshot)
  sleep 1
  read -r idle2 total2 < <(cpu_snapshot)

  delta_idle=$((idle2 - idle1))
  delta_total=$((total2 - total1))

  ((delta_total > 0)) || die "Unable to calculate CPU usage from /proc/stat."
  awk -v idle="$delta_idle" -v total="$delta_total" 'BEGIN { printf "%.1f\n", 100 * (total - idle) / total }'
}

# 시스템 전체 메모리의 used / total 기준 사용률 계산
memory_usage() {
  LC_ALL=C free -b | awk '
    /^Mem:/ && $2 > 0 { printf "%.1f\n", 100 * $3 / $2; found = 1 }
    END { exit(found ? 0 : 1) }
  ' || die "Unable to calculate memory usage from free."
}

# 루트 파일시스템의 Use% 기준 디스크 사용률 조회
disk_usage() {
  df -P / | awk 'NR == 2 { gsub(/%/, "", $5); printf "%.1f\n", $5; found = 1 } END { if (!found) exit 1 }' \
    || die "Unable to calculate root filesystem usage."
}

# 측정값의 경고 기준 초과 여부 비교
greater_than() {
  awk -v value="$1" -v threshold="$2" 'BEGIN { exit(value > threshold ? 0 : 1) }'
}

# 새 로그 추가 시 크기 제한 도달 여부 확인 및 로그 회전
rotate_log_if_needed() {
  local incoming_bytes="${1:-0}"

  [[ -f "$MONITOR_LOG_FILE" ]] || return 0

  local size index

  size=$(wc -c <"$MONITOR_LOG_FILE")
  ((size + incoming_bytes >= LOG_MAX_BYTES)) || return 0

  # 가장 오래된 .9 삭제 및 .8부터 역순 이동을 통한 덮어쓰기 방지
  # 현재 로그의 .1 이동 및 현재 파일을 포함한 최대 10개 로그 보존
  rm -f -- "${MONITOR_LOG_FILE}.9"

  for ((index = 8; index >= 1; index--)); do
    if [[ -f "${MONITOR_LOG_FILE}.${index}" ]]; then
      mv -- "${MONITOR_LOG_FILE}.${index}" "${MONITOR_LOG_FILE}.$((index + 1))"
    fi
  done

  mv -- "$MONITOR_LOG_FILE" "${MONITOR_LOG_FILE}.1"
}

main() {
  # 설정값 검증 및 로그 디렉토리 준비
  validate_config
  mkdir -p -- "$AGENT_LOG_DIR"

  # cron·수동 실행 간 중복 기록과 동시 로그 회전 방지를 위한 잠금
  exec 9>"${AGENT_LOG_DIR}/monitor.lock"
  flock -n 9 || die "Another monitor process is already running."

  # 점검 결과 제목 출력
  printf '====== SYSTEM MONITOR RESULT ======\n\n'
  printf '[HEALTH CHECK]\n'

  local pid cpu mem disk timestamp log_line

  # 앱 프로세스 상태 확인 및 비정상 시 종료 코드 1 반환
  if ! pid=$(process_pid); then
    printf "Checking process '%s'... [FAIL]\n" "$AGENT_PROCESS_PATTERN"
    exit 1
  fi

  printf "Checking process '%s'... [OK] (PID: %s)\n" "$AGENT_PROCESS_PATTERN" "$pid"

  # 앱 포트 LISTEN 상태 확인 및 비정상 시 종료 코드 1 반환
  if ! port_is_listening; then
    printf 'Checking port %s... [FAIL]\n' "$AGENT_PORT"
    exit 1
  fi

  printf 'Checking port %s... [OK]\n' "$AGENT_PORT"

  # 방화벽 상태 확인 및 비활성 시 경고 후 점검 계속
  if firewall_is_active; then
    printf 'Checking firewall... [OK]\n'
  else
    warn 'Firewall is inactive or its status could not be determined.'
  fi

  # CPU·메모리·디스크 사용률 수집
  cpu=$(cpu_usage)
  mem=$(memory_usage)
  disk=$(disk_usage)

  # 자원 사용률 출력
  printf '\n[RESOURCE MONITORING]\n'
  printf 'CPU Usage : %s%%\n' "$cpu"
  printf 'MEM Usage : %s%%\n' "$mem"
  printf 'DISK Used : %s%%\n' "$disk"

  # 자원별 기준 초과 경고 출력
  greater_than "$cpu" "$CPU_THRESHOLD" && warn "CPU threshold exceeded (${cpu}% > ${CPU_THRESHOLD}%)"
  greater_than "$mem" "$MEM_THRESHOLD" && warn "MEM threshold exceeded (${mem}% > ${MEM_THRESHOLD}%)"
  greater_than "$disk" "$DISK_THRESHOLD" && warn "DISK_USED threshold exceeded (${disk}% > ${DISK_THRESHOLD}%)"

  # 한 줄 형식의 점검 결과 생성 및 필요 시 로그 회전
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  log_line="[${timestamp}] PID:${pid} CPU:${cpu}% MEM:${mem}% DISK_USED:${disk}%"
  rotate_log_if_needed "$((${#log_line} + 1))"

  # monitor.log 누적 기록 및 저장 경로 출력
  printf '%s\n' "$log_line" >>"$MONITOR_LOG_FILE"
  printf '\n[INFO] Log appended: %s\n' "$MONITOR_LOG_FILE"
}

main "$@"
