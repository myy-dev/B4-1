#!/usr/bin/env bash
set -euo pipefail

cd /opt/agent-lab

# 계정·그룹 구성
# 그룹 목록 순회 및 미생성 그룹 생성
for group in agent-common agent-core; do
  getent group "$group" >/dev/null || groupadd "$group"
done

# 계정 목록 순회 및 홈 디렉토리·Bash 셸을 포함한 미생성 계정 생성
for user in agent-admin agent-dev agent-test; do
  id -u "$user" >/dev/null 2>&1 || useradd -m -s /bin/bash "$user"
done

# -G를 통한 계정별 보조 그룹 전체 목록 지정
# 관리자·개발자의 핵심 영역 접근 및 테스트 계정의 공용 영역 접근 구성
usermod -G agent-common,agent-core agent-admin
usermod -G agent-common,agent-core agent-dev
usermod -G agent-common agent-test

# 디렉토리 접근 권한과 새 파일의 그룹·권한 상속 설정
# 2xxx의 setgid 비트를 통한 하위 항목의 부모 디렉토리 그룹 상속
install -d -o agent-admin -g agent-core -m 2770 \
  "$AGENT_HOME" \
  "$AGENT_KEY_PATH" \
  "$AGENT_LOG_DIR"

install -d -o agent-admin -g agent-common -m 2770 "$AGENT_UPLOAD_DIR"

# agent-dev 소유 및 agent-core 읽기·실행 전용 관제 스크립트 디렉토리 구성
install -d -o agent-dev -g agent-core -m 2750 "$AGENT_HOME/bin"

# agent-common 구성원의 upload_files 접근을 위한 상위 경로 통과 권한 부여
setfacl -m g:agent-common:--x /home/agent-admin "$AGENT_HOME"

# 기존 확장 ACL 제거 및 새 항목의 소유자·그룹 rwx, 그 외 사용자 --- 권한 상속
setfacl -b "$AGENT_UPLOAD_DIR" "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"
setfacl -d --set u::rwx,g::rwx,o::--- \
  "$AGENT_UPLOAD_DIR" \
  "$AGENT_KEY_PATH" \
  "$AGENT_LOG_DIR"

# AMD64 제공 앱과 관제 스크립트·키 파일 배치
# install 명령을 통한 파일 복사와 소유자·그룹·권한 고정
install -o agent-admin -g agent-core -m 0750 \
  app/agent-app-linux-x86 "$AGENT_HOME/agent-app"

install -o agent-dev -g agent-core -m 0750 \
  scripts/monitor.sh "$AGENT_HOME/bin/monitor.sh"

# 제공 앱 시작 시 사용할 과제용 API 키 생성
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

# 인바운드 기본 차단 및 SSH·앱 포트 허용
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw --force enable

# agent-admin 계정으로 매분 모니터링 실행
# agent-admin crontab 등록 및 전체 실행 출력의 cron.log 누적
printf '* * * * * %s/bin/monitor.sh >> %s/cron.log 2>&1\n' \
  "$AGENT_HOME" "$AGENT_LOG_DIR" | crontab -u agent-admin -
