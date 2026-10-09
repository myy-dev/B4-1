#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

APPLY=0
RESET_FIREWALL=0
START_APP=0
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
ENV_DIR="${ENV_DIR:-/etc/agent-app}"
SSHD_DROPIN="${SSHD_DROPIN:-/etc/ssh/sshd_config.d/99-agent-app.conf}"

usage() {
  cat <<'EOF'
Usage: sudo ./bin/setup-system.sh [options]

By default, prints the planned Ubuntu changes without modifying the system.

Options:
  --apply                 Apply account, directory, application, SSH, and cron changes.
  --reset-firewall        Reset UFW and allow only 20022/tcp and 15034/tcp.
                          Required with --apply to enforce the assignment policy.
  --start-app             Start the reference app as agent-admin after setup.
  --agent-home PATH       Override AGENT_HOME.
  -h, --help              Show this help.

WARNING: --apply --reset-firewall replaces existing UFW rules. Run from a VM or
container console so an SSH configuration mistake cannot lock you out.
EOF
}

quote_command() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run() {
  if ((APPLY)); then
    "$@"
  else
    quote_command "$@"
  fi
}

write_file() {
  local destination="$1" owner="$2" group="$3" mode="$4" content="$5" temporary
  if ((APPLY)); then
    temporary=$(mktemp)
    printf '%s' "$content" >"$temporary"
    install -o "$owner" -g "$group" -m "$mode" "$temporary" "$destination"
    rm -f "$temporary"
  else
    printf '+ write %s owner=%s group=%s mode=%s\n' "$destination" "$owner" "$group" "$mode"
  fi
}

ensure_group() {
  local group="$1"
  if ((APPLY)) && getent group "$group" >/dev/null 2>&1; then
    return
  fi
  run groupadd "$group"
}

ensure_user() {
  local user="$1"
  if ((APPLY)) && id -u "$user" >/dev/null 2>&1; then
    return
  fi
  run useradd --create-home --shell /bin/bash "$user"
}

install_packages() {
  run env DEBIAN_FRONTEND=noninteractive apt-get update
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    openssh-server ufw acl cron procps iproute2 python3 gzip unzip
}

configure_accounts() {
  local group user
  for group in agent-common agent-core; do
    ensure_group "$group"
  done
  for user in agent-admin agent-dev agent-test; do
    ensure_user "$user"
  done

  run usermod -aG agent-common agent-admin
  run usermod -aG agent-common agent-dev
  run usermod -aG agent-common agent-test
  run usermod -aG agent-core agent-admin
  run usermod -aG agent-core agent-dev
}

configure_directories() {
  run install -d -o agent-admin -g agent-core -m 2770 "$AGENT_HOME"
  run install -d -o agent-admin -g agent-common -m 2770 "${AGENT_HOME}/upload_files"
  run install -d -o agent-admin -g agent-core -m 2770 "${AGENT_HOME}/api_keys"
  run install -d -o agent-dev -g agent-core -m 2770 "${AGENT_HOME}/bin"
  run install -d -o agent-admin -g agent-core -m 2770 "$AGENT_LOG_DIR"

  run setfacl -m g:agent-common:rwx,m:rwx "${AGENT_HOME}/upload_files"
  run setfacl -d -m g:agent-common:rwx,m:rwx "${AGENT_HOME}/upload_files"
  run setfacl -m g:agent-common:--x,m:rwx "$AGENT_HOME"
  run setfacl -m g:agent-core:rwx,m:rwx "${AGENT_HOME}/api_keys" "$AGENT_LOG_DIR"
  run setfacl -d -m g:agent-core:rwx,m:rwx "${AGENT_HOME}/api_keys" "$AGENT_LOG_DIR"
}

install_application() {
  local script machine binary_name provided_source archive_source temporary
  for script in monitor.sh run-monitor.sh report.sh archive-logs.sh start-agent.sh verify-system.sh collect-evidence.sh; do
    run install -o agent-dev -g agent-core -m 0750 "${SCRIPT_DIR}/${script}" "${AGENT_HOME}/bin/${script}"
  done

  machine=$(uname -m)
  case "$machine" in
    x86_64|amd64) binary_name='agent-app-linux-x86' ;;
    arm64|aarch64) binary_name='agent-app-linux-arm64' ;;
    *) binary_name='' ;;
  esac

  provided_source=''
  if [[ -n "$binary_name" ]]; then
    for temporary in "${REPO_ROOT}/app/${binary_name}" "${REPO_ROOT}/${binary_name}"; do
      if [[ -f "$temporary" ]]; then
        provided_source="$temporary"
        break
      fi
    done
  fi

  archive_source=''
  for temporary in "${REPO_ROOT}/app/agent-app.zip" "${REPO_ROOT}/agent-app.zip"; do
    if [[ -f "$temporary" ]]; then
      archive_source="$temporary"
      break
    fi
  done

  if [[ -n "$provided_source" ]]; then
    run install -o agent-admin -g agent-core -m 0750 "$provided_source" "${AGENT_HOME}/${binary_name}"
    printf '[INFO] Selected provided application: %s\n' "$binary_name"
  elif [[ -n "$archive_source" && -n "$binary_name" ]]; then
    if ((APPLY)); then
      temporary=$(mktemp)
      unzip -p "$archive_source" "$binary_name" >"$temporary" \
        || { rm -f "$temporary"; printf '[ERROR] %s is missing from %s.\n' "$binary_name" "$archive_source" >&2; exit 1; }
      install -o agent-admin -g agent-core -m 0750 "$temporary" "${AGENT_HOME}/${binary_name}"
      rm -f "$temporary"
    else
      printf '+ extract %s from %s to %s/%s\n' "$binary_name" "$archive_source" "$AGENT_HOME" "$binary_name"
    fi
    printf '[INFO] Selected provided application from ZIP: %s\n' "$binary_name"
  else
    run install -o agent-admin -g agent-core -m 0750 "${REPO_ROOT}/app/agent_app.py" "${AGENT_HOME}/agent_app.py"
    printf '[INFO] Provided application not found; installed the contract-compatible reference app.\n'
  fi

  if ((APPLY)); then
    install -o agent-admin -g agent-core -m 0660 /dev/null "${AGENT_HOME}/api_keys/t_secret.key"
    printf '%s\n' 'agent_api_key_test' >"${AGENT_HOME}/api_keys/t_secret.key"
  else
    printf '+ write %s owner=agent-admin group=agent-core mode=0660\n' "${AGENT_HOME}/api_keys/t_secret.key"
  fi

  run install -d -o root -g agent-core -m 0750 "$ENV_DIR"
  write_file "${ENV_DIR}/agent-app.env" root agent-core 0640 "AGENT_HOME=${AGENT_HOME}
AGENT_PORT=${AGENT_PORT}
AGENT_UPLOAD_DIR=${AGENT_HOME}/upload_files
AGENT_KEY_PATH=${AGENT_HOME}/api_keys/t_secret.key
AGENT_LOG_DIR=${AGENT_LOG_DIR}
AGENT_EXPECTED_USER=agent-admin
AGENT_PROCESS_PATTERN='agent_app.py|agent-app-linux-(x86|arm64)'
CPU_THRESHOLD=20
MEM_THRESHOLD=10
DISK_THRESHOLD=80
LOG_MAX_BYTES=10485760
LOG_MAX_FILES=10
"
}

configure_firewall() {
  run ufw --force reset
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw allow 20022/tcp comment 'Agent SSH'
  run ufw allow 15034/tcp comment 'Agent APP'
  run ufw --force enable
}

restart_ssh() {
  if command -v systemctl >/dev/null 2>&1 && systemctl show-environment >/dev/null 2>&1; then
    # Reload Ubuntu 24.04's generator before restarting socket-activated SSH.
    systemctl daemon-reload
    if systemctl is-active --quiet ssh.socket || systemctl is-enabled --quiet ssh.socket; then
      systemctl restart ssh.socket ssh.service
    else
      systemctl restart ssh.service || systemctl restart sshd.service
    fi
  else
    service ssh restart || service sshd restart
  fi
}

configure_ssh() {
  local content
  content=$(<"${REPO_ROOT}/config/sshd-agent-app.conf")
  run install -d -o root -g root -m 0755 "$(dirname "$SSHD_DROPIN")"
  run install -d -o root -g root -m 0755 /run/sshd

  if ((APPLY)); then
    local sshd_file
    shopt -s nullglob
    for sshd_file in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
      [[ "$sshd_file" == "$SSHD_DROPIN" ]] && continue
      if grep -Eq '^[[:space:]]*(Port|PermitRootLogin)[[:space:]]+' "$sshd_file"; then
        cp -n "$sshd_file" "${sshd_file}.pre-agent-app" 2>/dev/null || true
        sed -Ei 's/^([[:space:]]*)(Port|PermitRootLogin)([[:space:]]+)/# agent-app disabled: \2\3/' "$sshd_file"
      fi
    done
    shopt -u nullglob
  else
    printf '+ disable active Port and PermitRootLogin directives outside %s\n' "$SSHD_DROPIN"
  fi

  write_file "$SSHD_DROPIN" root root 0644 "${content}
"

  if ((APPLY)); then
    sshd -t
    [[ "$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }' | sort -u)" == "20022" ]] \
      || { printf '[ERROR] Effective SSH ports are not restricted to 20022.\n' >&2; exit 1; }
    sshd -T 2>/dev/null | awk '$1 == "permitrootlogin" && $2 == "no" { found=1 } END { exit(found ? 0 : 1) }' \
      || { printf '[ERROR] PermitRootLogin is not effectively disabled.\n' >&2; exit 1; }
    restart_ssh
  else
    printf '+ sshd -t\n'
    printf '+ reload systemd SSH socket configuration when available\n'
    printf '+ restart ssh service\n'
  fi
}

install_cron() {
  local cron_line current temporary
  cron_line="* * * * * ${AGENT_HOME}/bin/run-monitor.sh >> ${AGENT_LOG_DIR}/cron.log 2>&1 # agent-app-monitor"
  if ((APPLY)); then
    temporary=$(mktemp)
    current=$(crontab -u agent-admin -l 2>/dev/null || true)
    printf '%s\n' "$current" | awk '!/# agent-app-monitor$/ && NF' >"$temporary"
    printf '%s\n' "$cron_line" >>"$temporary"
    crontab -u agent-admin "$temporary"
    rm -f "$temporary"
    systemctl enable --now cron 2>/dev/null || service cron start
  else
    printf '+ install agent-admin crontab: %s\n' "$cron_line"
  fi
}

start_application() {
  if ((APPLY)); then
    local existing_pid existing_user
    existing_pid=$(pgrep -f 'agent_app.py|agent-app-linux-(x86|arm64)' | head -n 1 || true)
    if [[ -n "$existing_pid" ]]; then
      existing_user=$(ps -o user= -p "$existing_pid" | awk '{ print $1 }')
      if [[ "$existing_user" == "agent-admin" ]]; then
        printf '[INFO] Agent application is already running as agent-admin.\n'
        return
      fi
      printf '[ERROR] Agent process %s is running as %s, not agent-admin.\n' "$existing_pid" "$existing_user" >&2
      exit 1
    fi
    install -o agent-admin -g agent-core -m 0660 /dev/null "${AGENT_LOG_DIR}/agent-app.out"
    runuser -u agent-admin -- env AGENT_ENV_FILE="${ENV_DIR}/agent-app.env" \
      nohup "${AGENT_HOME}/bin/start-agent.sh" >"${AGENT_LOG_DIR}/agent-app.out" 2>&1 &
    printf '%s\n' "$!" >"${AGENT_LOG_DIR}/agent-app.pid"
    sleep 2
    pgrep -f 'agent_app.py|agent-app-linux-(x86|arm64)' >/dev/null 2>&1 \
      || { printf '[ERROR] Agent failed to start. Check %s/agent-app.out\n' "$AGENT_LOG_DIR" >&2; exit 1; }
  else
    printf '+ start application as agent-admin\n'
  fi
}

while (($# > 0)); do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --reset-firewall) RESET_FIREWALL=1; shift ;;
    --start-app) START_APP=1; shift ;;
    --agent-home)
      (($# >= 2)) || { printf '[ERROR] --agent-home requires a path.\n' >&2; exit 2; }
      AGENT_HOME="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$AGENT_HOME" == /* ]] || { printf '[ERROR] AGENT_HOME must be an absolute path.\n' >&2; exit 2; }
[[ "$AGENT_HOME" != *[[:space:]]* ]] || { printf '[ERROR] AGENT_HOME must not contain whitespace.\n' >&2; exit 2; }
[[ "$AGENT_PORT" == "15034" ]] || { printf '[ERROR] AGENT_PORT must be 15034.\n' >&2; exit 2; }

if ((APPLY)); then
  ((EUID == 0)) || { printf '[ERROR] --apply must run as root.\n' >&2; exit 1; }
  ((RESET_FIREWALL)) || {
    printf '[ERROR] --apply requires --reset-firewall to enforce the two-port policy.\n' >&2
    exit 2
  }
  [[ -r /etc/os-release ]] || { printf '[ERROR] Linux /etc/os-release not found.\n' >&2; exit 1; }
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *debian* ]] \
    || { printf '[ERROR] This installer supports Ubuntu/Debian systems.\n' >&2; exit 1; }
fi

printf '[INFO] Mode: %s\n' "$([[ "$APPLY" == "1" ]] && printf apply || printf dry-run)"
printf '[INFO] AGENT_HOME: %s\n' "$AGENT_HOME"

install_packages
configure_accounts
configure_directories
install_application
configure_firewall
configure_ssh
install_cron
((START_APP)) && start_application

printf '[INFO] Setup complete.\n'
if ((!START_APP)); then
  printf '[INFO] Start the app with: sudo -u agent-admin AGENT_ENV_FILE=%s/agent-app.env %s/bin/start-agent.sh\n' "$ENV_DIR" "$AGENT_HOME"
fi
printf '[INFO] Verify with: sudo %s/bin/verify-system.sh --wait-cron\n' "$AGENT_HOME"
