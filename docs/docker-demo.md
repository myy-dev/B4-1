# Docker 시연 가이드

Docker Desktop을 실행한 뒤 저장소 루트에서 진행합니다.

```bash
docker compose up --build --wait
docker compose ps
docker compose exec server head -n 15 /var/log/agent-app/agent-app.out
```

컨테이너 시작 시 설정을 적용하고 제공 앱을 실행합니다. Boot Sequence 5단계의 `[OK]`와 `Agent READY`를 확인합니다. `scripts/setup.sh`는 컨테이너 내부에서 자동 실행됩니다.

일반 사용자로 모니터링을 실행합니다.

```bash
docker compose exec --user agent-admin server /home/agent-admin/agent-app/bin/monitor.sh
docker compose exec server tail -n 5 /var/log/agent-app/monitor.log
```

cron은 같은 스크립트를 매분 실행합니다. 수동 실행을 멈추고 1~2분 뒤 로그 시간이 갱신되는지 확인합니다.

서버 내부 설정은 다음 명령으로 확인합니다.

```bash
docker compose exec server bash
sshd -T | sed -n '/^port /p; /^permitrootlogin /p'
ufw status verbose
id agent-admin
id agent-dev
id agent-test
getfacl /home/agent-admin/agent-app/upload_files
getfacl /home/agent-admin/agent-app/api_keys
getfacl /var/log/agent-app
crontab -u agent-admin -l
ss -tulnp
exit
```

로컬 PC에서는 `127.0.0.1:20022`와 `127.0.0.1:15034`로 접근합니다. 앱의 TCP 연결은 `nc -vz 127.0.0.1 15034`로 확인할 수 있습니다.

```bash
docker compose restart  # 서버 재시작
docker compose down     # 서버 종료 (로그 볼륨 보존)
```

ARM64 서버를 사용하려면 `AGENT_PLATFORM=linux/arm64 docker compose up --build --wait`로 실행합니다. 이후 Compose 명령에도 같은 환경 변수를 붙입니다.
