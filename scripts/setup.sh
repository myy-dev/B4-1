#!/usr/bin/env bash
set -euo pipefail

cd /opt/agent-lab

for group in agent-common agent-core; do
  getent group "$group" >/dev/null || groupadd "$group"
done
for user in agent-admin agent-dev agent-test; do
  id -u "$user" >/dev/null 2>&1 || useradd -m -s /bin/bash "$user"
done
usermod -G agent-common,agent-core agent-admin
usermod -G agent-common,agent-core agent-dev
usermod -G agent-common agent-test

install -d -o agent-admin -g agent-core -m 2770 "$AGENT_HOME" "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"
install -d -o agent-admin -g agent-common -m 2770 "$AGENT_UPLOAD_DIR"
install -d -o agent-dev -g agent-core -m 2750 "$AGENT_HOME/bin"
setfacl -m g:agent-common:--x /home/agent-admin "$AGENT_HOME"
setfacl -m g:agent-common:rwx,m:rwx "$AGENT_UPLOAD_DIR"
setfacl -d -m u::rwx,g::rwx,g:agent-common:rwx,m::rwx,o::--- "$AGENT_UPLOAD_DIR"
setfacl -m g:agent-core:rwx,m:rwx "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"
setfacl -d -m u::rwx,g::rwx,g:agent-core:rwx,m::rwx,o::--- "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"

case "$(uname -m)" in
  x86_64) app=agent-app-linux-x86 ;;
  aarch64) app=agent-app-linux-arm64 ;;
  *) echo 'Unsupported architecture' >&2; exit 1 ;;
esac
install -o agent-admin -g agent-core -m 0750 "app/$app" "$AGENT_HOME/agent-app"
install -o agent-dev -g agent-core -m 0750 scripts/monitor.sh "$AGENT_HOME/bin/monitor.sh"
printf 'agent_api_key_test\n' > "$AGENT_KEY_PATH/secret.key"
chown agent-admin:agent-core "$AGENT_KEY_PATH/secret.key"
chmod 0660 "$AGENT_KEY_PATH/secret.key"

printf 'Port 20022\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/00-agent-app.conf
mkdir -p /run/sshd
ssh-keygen -A
sshd -t

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw --force enable

printf '* * * * * %s/bin/monitor.sh >> %s/cron.log 2>&1\n' \
  "$AGENT_HOME" "$AGENT_LOG_DIR" | crontab -u agent-admin -
