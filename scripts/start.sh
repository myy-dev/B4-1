#!/usr/bin/env bash
set -euo pipefail

cd /opt/agent-lab
./scripts/setup.sh
/usr/sbin/sshd
/usr/sbin/cron

exec runuser -u agent-admin -- "$AGENT_HOME/agent-app"

