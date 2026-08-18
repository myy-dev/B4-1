# 요구사항 수행 내역서

> 이 문서는 Ubuntu 적용 후 `bin/collect-evidence.sh`가 생성한 파일을 연결하는 제출용 템플릿입니다. 실행하지 않은 항목을 완료로 표시하지 마십시오.

## 수행 환경

| 항목 | 값 |
| --- | --- |
| 수행 일시 | `YYYY-MM-DD HH:MM:SS` |
| 호스트명 | `<hostname>` |
| 운영체제 | Ubuntu 22.04 LTS |
| 아키텍처 | x86_64 / arm64 |
| AGENT_HOME | `/home/agent-admin/agent-app` |

## 설정 및 명령어 기록

### 자동 설치

```bash
sudo ./bin/setup-system.sh --apply --reset-firewall --start-app
```

- 실행 결과: `<성공/실패 및 특이사항>`
- 증빙: `evidence/runs/<run-id>/README.md`

### SSH

- 포트: `20022`
- Root 로그인: `PermitRootLogin no`
- 증빙: `01-sshd-effective.txt`, `02-listening-ports.txt`

### 방화벽

- 구현: UFW
- 허용 포트: `20022/tcp`, `15034/tcp`
- 기본 인바운드 정책: deny
- 증빙: `03-firewall.txt`

### 계정 및 그룹

- 계정: `agent-admin`, `agent-dev`, `agent-test`
- 그룹: `agent-common`, `agent-core`
- 증빙: `04-agent-admin.txt`~`06-agent-test.txt`

### 디렉토리 및 권한

- `$AGENT_HOME/upload_files`: `agent-common`, mode `2770`, ACL 적용
- `$AGENT_HOME/api_keys`: `agent-core`, mode `2770`, ACL 적용
- `/var/log/agent-app`: `agent-core`, mode `2770`, ACL 적용
- 증빙: `07-agent-home.txt`~`10-log-acl.txt`

### 환경 변수

- `AGENT_HOME=/home/agent-admin/agent-app`
- `AGENT_PORT=15034`
- `AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files`
- `AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key`
- `AGENT_LOG_DIR=/var/log/agent-app`
- 증빙: `11-environment.txt`

### cron

- 실행 계정: `agent-admin`
- 주기: 매분
- 증빙: `12-crontab.txt`

## 필수 증거 자료 체크리스트

- [ ] SSH 포트 `20022` 및 Root 원격 접속 차단 확인
- [ ] UFW 활성화 및 `20022/tcp`, `15034/tcp`만 허용 확인
- [ ] 세 계정과 두 그룹의 구성원 확인
- [ ] 디렉토리 구조·소유권·권한·ACL 확인
- [ ] Boot Sequence 5단계 `[OK]`와 `Agent READY` 확인
- [ ] `monitor.sh` 프로세스·포트·리소스·경고 출력 확인
- [ ] `monitor.log` 최근 누적 기록 확인
- [ ] cron 등록 전후 로그 행 수 증가 확인
- [ ] 제출본의 `monitor.sh`와 서버 설치본 일치 확인

## 앱 실행 결과

- 증빙: `14-agent-boot.txt`
- Boot Sequence 결과: `<5/5 PASS 여부>`
- `Agent READY`: `<확인 여부>`

## 모니터링 결과

- 수동 실행 증빙: `16-monitor-run.txt`
- 누적 로그 증빙: `15-monitor-log.txt`
- 전체 검증: `17-system-verification.txt`

## cron 자동 실행 확인

| 시점 | `monitor.log` 행 수 |
| --- | ---: |
| 등록 직후 | `<값>` |
| 70초 후 | `<값>` |

판정: `<증가/미증가>`

## 보너스 수행 결과

- `report.sh` 통계 결과: `<첨부 경로>`
- 기간 필터 통계 결과: `<첨부 경로>`
- 로그 압축·아카이브 결과: `<첨부 경로>`
- 30일 경과 아카이브 삭제 결과: `<첨부 경로>`
