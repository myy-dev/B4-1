# Ubuntu 설치 및 운영 가이드

이 문서는 깨끗한 Ubuntu 22.04 VM 또는 컨테이너에서 프로젝트를 적용하고 검증하는 절차입니다.

## 사전 준비

- VM 또는 컨테이너의 콘솔 접근 권한
- `sudo` 사용 권한
- 저장소 체크아웃
- 기존 SSH·방화벽 규칙을 초기화해도 되는 실습 환경

`setup-system.sh --apply --reset-firewall`은 UFW 규칙을 초기화합니다. 원격 SSH 세션만 사용할 수 있는 운영 서버에서는 실행하지 마십시오.

## 1. 로컬 테스트

```bash
make test
```

테스트는 Bash·Python 문법, 설치 드라이런, 모니터 성공·실패 경로, 임계값 경고, 로그 회전, 통계, 보존 정책과 참조 앱의 Boot Sequence를 확인합니다.

## 2. 변경 계획 확인

```bash
./bin/setup-system.sh --reset-firewall --start-app
```

기본 모드는 드라이런입니다. 출력된 계정, 경로, UFW 초기화와 SSH 재시작 작업을 검토합니다.

Docker Desktop이 실행 중이면 격리된 Ubuntu 22.04 컨테이너에서 설치부터 cron 증가 확인까지 통합 테스트할 수 있습니다.

```bash
make test-ubuntu
```

## 3. Ubuntu에 적용

VM 콘솔에서 실행합니다.

```bash
sudo ./bin/setup-system.sh --apply --reset-firewall --start-app
```

스크립트가 수행하는 작업은 다음과 같습니다.

1. OpenSSH, UFW, ACL, cron, 프로세스·네트워크 도구 설치
2. `agent-admin`, `agent-dev`, `agent-test` 계정 생성
3. `agent-common`, `agent-core` 그룹 및 구성원 설정
4. `$AGENT_HOME`, 공유·보안·로그 디렉토리와 ACL 구성
5. 참조 앱과 Bash 자동화 스크립트 설치
6. 환경 변수와 과제용 키 파일 생성
7. UFW 초기화 후 `20022/tcp`, `15034/tcp`만 허용
8. SSH 포트 변경, Root 원격 접속 차단, 설정 검증 후 재시작
9. `agent-admin` crontab에 매분 모니터링 등록
10. 참조 앱을 `agent-admin` 계정으로 실행

## 4. 즉시 검증

```bash
sudo /home/agent-admin/agent-app/bin/verify-system.sh --wait-cron
```

모든 줄이 `[PASS]`이고 마지막 결과의 `failed=0`인지 확인합니다. `--wait-cron`은 70초 동안 기다린 뒤 `monitor.log`가 실제로 증가했는지도 검증합니다.

앱의 Boot Sequence도 확인합니다.

```bash
sudo tail -n 30 /var/log/agent-app/agent-app.out
curl http://127.0.0.1:15034/health
```

## 5. cron 자동 실행 확인

등록 직후 로그 행 수를 기록하고 70초 후 다시 확인합니다.

```bash
sudo wc -l /var/log/agent-app/monitor.log
sleep 70
sudo wc -l /var/log/agent-app/monitor.log
sudo tail -n 5 /var/log/agent-app/monitor.log
```

두 번째 행 수가 증가해야 합니다.

## 6. 증빙 수집

저장소 루트에서 실행하면 `evidence/runs/<timestamp>/`에 결과가 생성됩니다.

```bash
sudo AGENT_HOME=/home/agent-admin/agent-app \
  ./bin/collect-evidence.sh "$(pwd)/evidence/runs"
```

비밀 키 값은 수집하지 않습니다. 생성된 파일을 확인한 뒤 필요한 증빙만 제출합니다.

## 7. 통계 리포트

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh \
  --from '2026-02-25 13:00:00' \
  --to '2026-02-25 14:00:00'
```

## 8. 보너스 로그 보존 자동화

7일 이상 지난 로그를 압축하고 30일 이상 지난 압축 파일을 삭제합니다.

```bash
sudo /home/agent-admin/agent-app/bin/archive-logs.sh
```

매일 실행하려면 Root crontab 등에 다음 항목을 추가할 수 있습니다.

```cron
15 2 * * * /home/agent-admin/agent-app/bin/archive-logs.sh >> /var/log/agent-app/archive-cron.log 2>&1
```

## 문제 해결

### SSH 재시작 실패

```bash
sudo sshd -t
sudo journalctl -u ssh --no-pager -n 50
```

설정 오류를 해결한 후에만 SSH를 재시작합니다.

### 앱이 시작되지 않음

```bash
sudo tail -n 50 /var/log/agent-app/agent-app.out
sudo -u agent-admin AGENT_ENV_FILE=/etc/agent-app/agent-app.env \
  /home/agent-admin/agent-app/bin/start-agent.sh
```

### monitor.sh가 종료 코드 1을 반환함

프로세스와 포트 Health Check 중 하나가 실패한 것입니다.

```bash
pgrep -af 'agent_app.py|agent-app-linux-(x86|arm64)'
ss -ltnp | grep ':15034'
```
