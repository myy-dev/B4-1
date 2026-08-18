# 요구사항 수행 내역서

## 수행 환경

| 항목 | 값 |
| --- | --- |
| 수행 일시 | `2026-08-18 07:06:21 +0000` |
| 수행 환경 | Docker Desktop 격리 컨테이너 |
| 운영체제 | Ubuntu 22.04.5 LTS |
| 아키텍처 | `aarch64` |
| AGENT_HOME | `/home/agent-admin/agent-app` |
| 애플리케이션 | 제공 파일 부재로 계약 호환 참조 앱 사용 |
| 원본 증빙 | [`evidence/ubuntu-22.04/integration-20260818/`](../evidence/ubuntu-22.04/integration-20260818/) |

운영체제와 아키텍처 원본 출력은 [`00-system.txt`](../evidence/ubuntu-22.04/integration-20260818/00-system.txt)에서 확인할 수 있습니다.

## 설정 및 명령어 기록

### 자동 설치

```bash
./bin/setup-system.sh --apply --reset-firewall --start-app
./bin/setup-system.sh --apply --reset-firewall --start-app
```

Root로 실행되는 격리 컨테이너에서 같은 명령을 연속 두 번 실행해 신규 설치와 재실행이 모두 성공하는지 확인했습니다. 두 번째 실행은 기존 계정·그룹·설정을 재사용하고 실행 중인 앱을 중복 기동하지 않았습니다. 일반 Ubuntu VM에서는 같은 명령 앞에 `sudo`를 붙입니다.

### SSH 및 방화벽

- SSH 유효 포트: `20022` 하나
- Root 로그인: `PermitRootLogin no`
- UFW: active
- 기본 인바운드 정책: deny
- 허용 인바운드: `20022/tcp`, `15034/tcp`만 허용
- 증빙: [`01-sshd-effective.txt`](../evidence/ubuntu-22.04/integration-20260818/01-sshd-effective.txt), [`02-listening-ports.txt`](../evidence/ubuntu-22.04/integration-20260818/02-listening-ports.txt), [`03-firewall.txt`](../evidence/ubuntu-22.04/integration-20260818/03-firewall.txt)

### 계정 및 그룹

- `agent-admin`: `agent-common`, `agent-core`
- `agent-dev`: `agent-common`, `agent-core`
- `agent-test`: `agent-common`만 포함
- 증빙: [`04-agent-admin.txt`](../evidence/ubuntu-22.04/integration-20260818/04-agent-admin.txt), [`05-agent-dev.txt`](../evidence/ubuntu-22.04/integration-20260818/05-agent-dev.txt), [`06-agent-test.txt`](../evidence/ubuntu-22.04/integration-20260818/06-agent-test.txt)

### 디렉토리 및 권한

- `$AGENT_HOME/upload_files`: `agent-admin:agent-common`, mode `2770`, `agent-common:rwx` ACL
- `$AGENT_HOME/api_keys`: `agent-admin:agent-core`, mode `2770`, `agent-core:rwx` ACL
- `/var/log/agent-app`: `agent-admin:agent-core`, mode `2770`, `agent-core:rwx` ACL
- `monitor.sh`: `agent-dev:agent-core`, mode `750`
- 증빙: [`07-agent-home.txt`](../evidence/ubuntu-22.04/integration-20260818/07-agent-home.txt), [`08-upload-acl.txt`](../evidence/ubuntu-22.04/integration-20260818/08-upload-acl.txt), [`09-api-keys-acl.txt`](../evidence/ubuntu-22.04/integration-20260818/09-api-keys-acl.txt), [`10-log-acl.txt`](../evidence/ubuntu-22.04/integration-20260818/10-log-acl.txt)

### 환경 변수와 cron

- `AGENT_HOME=/home/agent-admin/agent-app`
- `AGENT_PORT=15034`
- `AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files`
- `AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key`
- `AGENT_LOG_DIR=/var/log/agent-app`
- cron 실행 계정: `agent-admin`
- cron 주기: 매분
- 증빙: [`11-environment.txt`](../evidence/ubuntu-22.04/integration-20260818/11-environment.txt), [`12-crontab.txt`](../evidence/ubuntu-22.04/integration-20260818/12-crontab.txt)

## 필수 증거 자료 체크리스트

- [x] SSH 포트 `20022` 및 Root 원격 접속 차단 확인
- [x] UFW 활성화 및 `20022/tcp`, `15034/tcp`만 허용 확인
- [x] 세 계정과 두 그룹의 구성원 확인
- [x] 디렉토리 구조·소유권·권한·ACL 확인
- [x] Boot Sequence 5단계 `[OK]`와 `Agent READY` 확인
- [x] `monitor.sh` 프로세스·포트·리소스·경고 출력 확인
- [x] `monitor.log` 최근 누적 기록 확인
- [x] cron 등록 전후 로그 행 수 증가 확인
- [x] 제출본의 `monitor.sh`와 서버 설치본 일치 확인

## 애플리케이션 실행 결과

- 프로세스 소유자: `agent-admin`
- Boot Sequence: 5/5 `[OK]`
- 최종 상태: `Agent READY`
- LISTEN: `0.0.0.0:15034`
- 증빙: [`13-agent-process.txt`](../evidence/ubuntu-22.04/integration-20260818/13-agent-process.txt), [`14-agent-boot.txt`](../evidence/ubuntu-22.04/integration-20260818/14-agent-boot.txt)

제공된 `agent-app.zip`이 저장소에 없어 이번 실행은 동일한 Boot Sequence와 포트 계약을 구현한 참조 앱으로 수행했습니다. 설치 스크립트는 제공 ZIP 또는 아키텍처별 실행 파일이 추가되면 이를 우선 설치합니다.

## 모니터링 및 cron 결과

- 수동 실행: 프로세스, TCP `15034`, UFW 모두 `[OK]`
- 수집값: CPU, 메모리, 루트 디스크 사용률 정상 출력
- 경고 경로: CPU `25.3%`, 메모리 `11.0%`, 디스크 `81.0%`에서 세 `[WARNING]` 출력 후 로그 기록
- 누적 로그: 지정된 PID·CPU·MEM·DISK 포맷과 일치
- cron 대기 전 로그: 1줄
- cron 대기 후 로그: 2줄
- 판정: 70초 이내 1줄 증가, PASS
- 전체 검증: `passed=37 failed=0`
- 증빙: [`15-monitor-log.txt`](../evidence/ubuntu-22.04/integration-20260818/15-monitor-log.txt), [`16-monitor-run.txt`](../evidence/ubuntu-22.04/integration-20260818/16-monitor-run.txt), [`17-system-verification.txt`](../evidence/ubuntu-22.04/integration-20260818/17-system-verification.txt), [`18-cron-growth.txt`](../evidence/ubuntu-22.04/integration-20260818/18-cron-growth.txt), [`21-monitor-warning.txt`](../evidence/ubuntu-22.04/integration-20260818/21-monitor-warning.txt)

저장소와 서버에 설치된 `monitor.sh`의 SHA-256 값도 일치합니다. 증빙은 [`19-monitor-source-sha256.txt`](../evidence/ubuntu-22.04/integration-20260818/19-monitor-source-sha256.txt), 제출 소스는 [`monitor.sh`](../evidence/ubuntu-22.04/integration-20260818/monitor.sh)입니다.

## 보너스 수행 결과

- 통계 리포트: CPU·메모리·디스크 평균·최대·최소와 샘플 3개 출력 — [`20-report.txt`](../evidence/ubuntu-22.04/integration-20260818/20-report.txt)
- 기간 필터: `tests/run.sh`에서 지정 구간 샘플 수를 검증
- 로그 보존: `tests/run.sh`에서 압축, 아카이브 이동, 30일 경과 삭제를 검증
- 예외 처리: 대상 디렉토리 미존재 시 경고 후 안전 종료를 검증

## 설계 근거

- 기본 SSH 포트를 변경하고 Root 로그인을 차단하면 자동 스캔 노출과 고권한 직접 로그인의 위험을 줄일 수 있습니다.
- UFW 기본 인바운드를 차단하고 필요한 두 포트만 허용해 서비스 공격 표면을 제한합니다.
- 공용 그룹과 핵심 그룹을 분리해 업로드 영역은 협업 가능하게 하고 키·로그 영역은 최소 인원만 접근하게 합니다.
- 환경 변수로 경로와 포트를 고정하면 수동 실행과 cron 실행이 같은 설정을 사용합니다.
- 매분 상태와 자원값을 동일 포맷으로 축적하면 장애 시점의 상태를 추적하고 통계로 분석할 수 있습니다.
- 크기 기반 회전과 시간 기반 압축·삭제는 디스크 고갈을 방지하면서 필요한 기간의 기록을 보존합니다.
