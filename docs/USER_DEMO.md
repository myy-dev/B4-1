# 평가 시연 가이드

## 0. 시연용 SSH 키 준비

```bash
mkdir -p "$HOME/.ssh"
test -f "$HOME/.ssh/b4-1-demo" || \
  ssh-keygen -t ed25519 -f "$HOME/.ssh/b4-1-demo" -N "" -C b4-1-demo
```

## 1. 서버 실행

```bash
docker compose up --build --wait
docker compose ps
```

## 2. 앱 부팅과 환경 변수 확인

```bash
docker compose logs server
docker compose exec server printenv AGENT_HOME AGENT_PORT AGENT_UPLOAD_DIR AGENT_KEY_PATH AGENT_LOG_DIR
```

```bash
nc -vz 127.0.0.1 20022
nc -vz 127.0.0.1 15034
```

## 3. SSH 접속과 SSH·포트·방화벽 확인

```bash
ssh -i "$HOME/.ssh/b4-1-demo" -p 20022 agent-admin@127.0.0.1
```

```bash
whoami
sudo /usr/sbin/sshd -T | sed -n '/^port /p; /^permitrootlogin /p'
ss -ltn
sudo /usr/sbin/ufw status verbose
```

## 4. 계정과 그룹 확인

```bash
id agent-admin
id agent-dev
id agent-test
```

계정별 역할과 그룹 구성은 [계정·그룹별 권한](permissions.md#계정과-그룹)을 참고합니다.

## 5. 디렉토리·파일 권한 확인

```bash
ls -l /home/agent-admin/agent-app
ls -ld /var/log/agent-app
ls -l /home/agent-admin/agent-app/bin/monitor.sh
ls -l /home/agent-admin/agent-app/api_keys/secret.key
getfacl -p \
  /home/agent-admin \
  /home/agent-admin/agent-app \
  /home/agent-admin/agent-app/upload_files \
  /home/agent-admin/agent-app/api_keys \
  /var/log/agent-app
```

권한 해석은 [디렉토리 접근 권한](permissions.md#디렉토리-접근-권한), [주요 파일 권한](permissions.md#주요-파일-권한), [ACL과 권한 상속](permissions.md#접근-권한과-상속을-나누는-기준)을 참고합니다.

## 6. 모니터링 수동 실행과 로그 확인

```bash
/home/agent-admin/agent-app/bin/monitor.sh
tail -n 5 /var/log/agent-app/monitor.log
```

요약 로그의 각 항목은 [monitor.log 조회 명령과 형식](monitoring-logs.md#monitorlog-조회-명령과-형식)을 참고합니다.

## 7. cron 자동 실행 확인

```bash
crontab -l
```

시간 항목의 순서와 실행 예시는 [cron 실행 주기](cron.md)를 참고합니다.

```bash
wc -l /var/log/agent-app/monitor.log
tail -n 1 /var/log/agent-app/monitor.log
sleep 70
wc -l /var/log/agent-app/monitor.log
tail -n 1 /var/log/agent-app/monitor.log
```

```bash
tail -n 20 /var/log/agent-app/cron.log
```

로그 파일의 차이와 조회 결과 해석은 [모니터링 로그 읽기](monitoring-logs.md)를 참고합니다.

## 8. 프로세스·포트 장애 처리 확인

```bash
AGENT_PROCESS_PATTERN='^없는프로세스$' \
  /home/agent-admin/agent-app/bin/monitor.sh
echo $?
```

```bash
AGENT_PORT=15035 \
  /home/agent-admin/agent-app/bin/monitor.sh
echo $?
```

## 9. 재시작과 로그 보존 확인

```bash
wc -l /var/log/agent-app/monitor.log
tail -n 5 /var/log/agent-app/monitor.log
exit
```

이후 명령은 맥북 터미널에서 실행합니다.

```bash
docker compose restart server
docker compose up --wait
docker compose ps
docker compose logs server
ssh -i "$HOME/.ssh/b4-1-demo" -p 20022 agent-admin@127.0.0.1
```

```bash
wc -l /var/log/agent-app/monitor.log
tail -n 5 /var/log/agent-app/monitor.log
ls -lh /var/log/agent-app
exit
```

## 10. 시연 종료

```bash
docker compose down --volumes
ssh-keygen -R '[127.0.0.1]:20022'
```

