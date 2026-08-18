#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AGENT_ENV_FILE="${AGENT_ENV_FILE:-/etc/agent-app/agent-app.env}"

if [[ ! -r "$AGENT_ENV_FILE" ]]; then
  printf '[ERROR] Cannot read environment file: %s\n' "$AGENT_ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$AGENT_ENV_FILE"
set +a

exec "${SCRIPT_DIR}/monitor.sh" "$@"
