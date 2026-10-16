#!/usr/bin/env bash
set -euo pipefail

cd /opt/agent-lab
./scripts/setup.sh
/usr/sbin/sshd
/usr/sbin/cron

install -o agent-admin -g agent-core -m 0660 /dev/null "$AGENT_LOG_DIR/agent-app.out"
exec runuser -u agent-admin -- "$AGENT_HOME/agent-app" \
  > >(tee "$AGENT_LOG_DIR/agent-app.out") 2>&1
