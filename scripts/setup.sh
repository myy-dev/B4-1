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

# SSH·방화벽 설정
# 공개 키 인증용 디렉토리와 authorized_keys 설치 및 SSH 필수 권한 적용
install -d -o agent-admin -g agent-admin -m 0700 /home/agent-admin/.ssh

install -o agent-admin -g agent-admin -m 0600 \
  /run/agent-admin.pub \
  /home/agent-admin/.ssh/authorized_keys

# SSH 20022 포트 및 agent-admin 공개 키 로그인 전용 설정
printf 'Port 20022\nPermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nAllowUsers agent-admin\n' \
  > /etc/ssh/sshd_config.d/00-agent-app.conf

# 모니터링용 SSH·방화벽 조회 명령에 한정된 비밀번호 없는 sudo 허용
printf 'agent-admin ALL=(root) NOPASSWD: /usr/sbin/sshd -T, /usr/sbin/ufw status verbose\n' \
  > /etc/sudoers.d/agent-admin
chmod 0440 /etc/sudoers.d/agent-admin

# sudoers 설정 오류 방지를 위한 문법 검사
visudo -cf /etc/sudoers.d/agent-admin

# SSH 로그인 셸에서 앱 환경 변수 사용을 위한 설정
# 현재 컨테이너 환경 변수 값을 로그인 셸 설정으로 저장
cat > /etc/profile.d/agent-app.sh <<EOF
export AGENT_HOME="$AGENT_HOME"
export AGENT_PORT="$AGENT_PORT"
export AGENT_UPLOAD_DIR="$AGENT_UPLOAD_DIR"
export AGENT_KEY_PATH="$AGENT_KEY_PATH"
export AGENT_LOG_DIR="$AGENT_LOG_DIR"
EOF

# SSH 실행 디렉토리·서버 호스트 키 준비 및 SSH 설정 문법 검사
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
