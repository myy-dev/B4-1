#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AGENT_ENV_FILE="${AGENT_ENV_FILE:-/etc/agent-app/agent-app.env}"

if ((EUID == 0)); then
  printf '[ERROR] The Agent application must not run as root.\n' >&2
  exit 1
fi

if [[ ! -r "$AGENT_ENV_FILE" ]]; then
  printf '[ERROR] Cannot read environment file: %s\n' "$AGENT_ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$AGENT_ENV_FILE"
set +a

for candidate in agent-app agent-app-linux-x86 agent-app-linux-arm64; do
  if [[ -x "${AGENT_HOME}/${candidate}" ]]; then
    exec "${AGENT_HOME}/${candidate}"
  fi
done

if [[ -x "${AGENT_HOME}/agent_app.py" ]]; then
  exec python3 "${AGENT_HOME}/agent_app.py"
fi

printf '[ERROR] No executable Agent application found in %s.\n' "$AGENT_HOME" >&2
printf 'Expected agent-app, an architecture-specific provided binary, or agent_app.py.\n' >&2
exit 1
