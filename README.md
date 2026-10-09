# 컴퓨터가 알아서 자기 상태를 점검하게 만들기

## 프로젝트 개요 (Project Overview)

Linux 서버의 보안, 계정·권한, 네트워크 정책을 구성하고 Bash 스크립트로 애플리케이션과 시스템 상태를 자동 점검하는 프로젝트

## 실행 환경 (Environment)

- **운영체제**: Ubuntu 24.04 LTS
- **언어**: Bash (자동화 스크립트), Python 3 (참조 앱)
- **검증 환경**: Docker Desktop의 Ubuntu 24.04 ARM64 컨테이너 (검증 완료)
- **실행 애플리케이션**: `app/agent_app.py` (참조 앱으로 검증 완료)
- **실행 스크립트**: `bin/start-agent.sh`
- **실행 계정**: `root`가 아닌 일반 사용자 `agent-admin`
- **사용 도구**: OpenSSH, UFW 또는 firewalld, cron, ACL, `monitor.sh`, `ps`, `ss`, `df` 등
- **네트워크**: SSH `20022/tcp`, 애플리케이션 `0.0.0.0:15034`

## 프로젝트 구조 (Project Structure)

```text
.
├── README.md                       # 프로젝트 설명 및 수행 항목 체크리스트
├── Makefile                        # 로컬·Ubuntu 통합 테스트 명령
├── app/
│   └── agent_app.py                # 제공 앱이 없을 때 사용하는 참조 앱
├── bin/
│   ├── setup-system.sh             # Ubuntu 보안·계정·앱·cron 자동 구성
│   ├── start-agent.sh              # 일반 계정 앱 실행 래퍼
│   ├── monitor.sh                  # 프로세스·포트·자원 점검 및 로깅
│   ├── run-monitor.sh              # cron용 환경 로드 래퍼
│   ├── report.sh                   # 통계 및 기간 필터 리포트
│   ├── archive-logs.sh             # 로그 압축·보관·삭제
│   ├── verify-system.sh            # 적용 결과 37개 항목 검증
│   └── collect-evidence.sh          # 제출용 시스템 증빙 수집
├── config/
│   ├── agent-app.env.example       # 앱·모니터 환경 변수 예시
│   ├── agent-app.cron.example      # agent-admin cron 예시
│   └── sshd-agent-app.conf         # SSH 보안 설정
├── docs/
│   ├── operations.md               # 설치·검증·운영 가이드
│   └── execution-report.md         # 완료된 요구사항 수행 내역서
├── evidence/
│   ├── README.md                    # 실제 VM 증빙 수집 안내
│   ├── ubuntu-integration-summary.md # Ubuntu 격리 검증 요약
│   ├── ubuntu-24.04/                 # Ubuntu 24.04 원본 명령 출력과 제출 소스
│   └── ubuntu-22.04/                 # 기존 Ubuntu 22.04 검증 증빙
└── tests/
    ├── run.sh                       # 기능·실패·예외 경로 35개 테스트
    └── run-ubuntu-integration.sh    # Ubuntu 24.04 전체 통합 테스트
```

## 수행 항목 체크리스트

### 기본 보안 및 네트워크 설정

- [x] SSH 접속 포트를 `20022`로 변경
- [x] Root 원격 로그인 차단(`PermitRootLogin no`)
- [x] SSH 설정 파일에서 포트와 Root 로그인 차단 설정 확인
- [x] `ss -tulnp`로 SSH 포트 리슨 상태 확인
- [x] UFW 또는 firewalld 중 하나를 선택해 활성화
- [x] 인바운드 TCP `20022`(SSH), `15034`(APP) 포트만 허용
- [x] 그 외 불필요한 인바운드 포트 차단
- [x] `ufw status` 또는 `firewall-cmd --list-all`로 방화벽 정책 확인

### 계정·그룹 및 권한 체계

- [x] 운영·관리 계정 `agent-admin` 생성
- [x] 개발·운영 계정 `agent-dev` 생성
- [x] QA·테스트 계정 `agent-test` 생성
- [x] 공통 그룹 `agent-common` 생성 후 `agent-admin`, `agent-dev`, `agent-test` 계정 추가
- [x] 핵심 그룹 `agent-core` 생성 후 `agent-admin`, `agent-dev` 계정 추가
- [x] `$AGENT_HOME/upload_files` 디렉토리 생성
- [x] `$AGENT_HOME/api_keys` 디렉토리 생성
- [x] `/var/log/agent-app` 디렉토리 생성
- [x] `upload_files`의 그룹을 `agent-common`으로 설정하고 그룹 읽기·쓰기 권한 부여
- [x] `api_keys`와 `/var/log/agent-app`의 그룹을 `agent-core`로 설정
- [x] `api_keys`와 `/var/log/agent-app`에 `agent-core` 구성원만 읽기·쓰기 가능하도록 설정
- [x] 필요 시 ACL을 적용해 디렉토리별 접근 권한 고정
- [x] `id`, `ls -l`로 계정·그룹·권한 확인하고 ACL 사용 시 `getfacl`로 추가 확인

### 애플리케이션 실행 환경

> 제공된 `agent-app.zip` 또는 아키텍처별 실행 파일이 저장소에 있으면 설치 스크립트가 이를 우선 선택합니다. 현재 저장소에는 제공 파일이 없어 동일한 Boot 계약을 구현한 `app/agent_app.py`로 자동 검증했으며, 실제 제공 앱 결과는 해당 파일을 추가한 뒤 다시 확인해야 합니다.

- [x] `AGENT_HOME` 설정(예: `/home/agent-admin/agent-app`)
- [x] `AGENT_PORT=15034` 설정
- [x] `AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files` 설정
- [x] `AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key` 설정
- [x] (권장) `AGENT_LOG_DIR=/var/log/agent-app` 설정(미지정 시 같은 경로를 기본값으로 사용)
- [x] `$AGENT_HOME/api_keys/t_secret.key` 파일 생성
- [x] 키 파일에 과제용 값 `agent_api_key_test`를 한 줄로 저장
- [x] 애플리케이션을 Root가 아닌 일반 계정으로 실행(참조 앱 검증 완료)
- [x] Boot Sequence 5단계가 모두 `[OK]`인지 확인(참조 앱 검증 완료)
- [x] 마지막 출력에서 `Agent READY` 확인(참조 앱 검증 완료)
- [x] 애플리케이션이 `0.0.0.0:15034`에서 LISTEN 상태인지 확인(참조 앱 검증 완료)
- [ ] 실제 제공 앱으로 위 실행 결과 재확인(제공 파일 필요)

### 시스템 관제 자동화 (`monitor.sh`)

- [x] 스크립트를 `$AGENT_HOME/bin/monitor.sh`에 작성
- [x] 소유자를 `agent-dev`, 그룹을 `agent-core`로 설정
- [x] 파일 권한을 `750`(`rwxr-x---`)으로 설정
- [x] `agent-admin` 계정이 스크립트를 실행할 수 있는지 확인
- [x] `agent_app.py` 또는 제공된 앱 프로세스의 실행 상태 확인
- [x] 프로세스가 비정상이면 종료 코드 `1` 반환
- [x] TCP `15034` 포트의 LISTEN 상태 확인
- [x] 포트가 비정상이면 종료 코드 `1` 반환
- [x] UFW 또는 firewalld 활성화 상태 확인
- [x] 방화벽이 비활성 상태이면 `[WARNING]`만 출력하고 점검 계속 진행
- [x] CPU 사용률(%) 수집
- [x] 메모리 사용률(%) 수집
- [x] 루트 파티션 디스크 사용률(%) 수집
- [x] CPU 사용률이 20%를 초과하면 `[WARNING]` 출력
- [x] 메모리 사용률이 10%를 초과하면 `[WARNING]` 출력
- [x] 디스크 사용률이 80%를 초과하면 `[WARNING]` 출력
- [x] `/var/log/agent-app/monitor.log`에 점검 결과 누적 기록
- [x] 로그 포맷을 `[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%`로 구성
- [x] logrotate 또는 스크립트 로직으로 로그 파일을 최대 10MB, 10개까지 유지

### 자동 실행 (`cron`)

- [x] `agent-admin` 계정의 crontab에 `monitor.sh` 매분 실행 등록
- [x] 등록 후 1~2분 내 `monitor.log`에 새 로그가 추가되는지 확인

> cron 실행 환경에 필요한 환경 변수를 명시하고, 권한 오류나 경로 오류가 없는지 확인합니다.

### 요구사항 수행 내역서 및 증빙

- [x] SSH 포트 `20022` 변경 및 Root 원격 접속 차단 설정 기록
- [x] 방화벽 활성화 및 TCP `20022`, `15034`만 허용한 내역 기록
- [x] 계정 `agent-admin`, `agent-dev`, `agent-test` 생성 내역 기록
- [x] 그룹 `agent-common`, `agent-core`와 구성원 설정 내역 기록
- [x] 디렉토리 구조와 일반 권한·ACL 확인 내역 기록
- [x] 환경 변수와 cron 등록 명령 기록
- [x] 앱 Boot Sequence 5단계 `[OK]` 및 `Agent READY` 출력 첨부(참조 앱)
- [x] `monitor.sh`의 프로세스·포트·리소스·경고 출력 첨부
- [x] `/var/log/agent-app/monitor.log` 최근 누적 로그 첨부
- [x] cron 등록 전후 로그를 비교해 자동 실행 증명
- [x] `monitor.sh` 전체 소스코드 제출

### 보너스 과제

- [x] **통계 리포트**: `report.sh`로 CPU, 메모리, 디스크의 평균·최대·최소와 샘플 수 출력
- [x] **기간 필터링**: 시작·종료 시간을 입력받아 해당 구간의 로그만 분석
- [x] **로그 압축**: `/var/log/agent-app/*.log` 중 7일 이상 지난 파일 압축
- [x] **로그 아카이브**: 압축 파일을 `/var/log/monitor/agent-app/archive/`로 이동
- [x] **오래된 로그 삭제**: 아카이브의 `.gz` 파일 중 30일 이상 지난 파일 삭제
- [x] **예외 처리**: 디렉토리 미존재, 권한 부족, 대상 파일 없음 상황을 안전하게 처리

## 제약 사항 (Constraints)

- **구현 언어**: 자동화 스크립트는 Bash로만 작성하며 Python 등으로 대체하지 않습니다.
- **권한 원칙**: 필요한 경우에만 `sudo`를 사용하고 가능한 작업은 일반 계정으로 수행합니다.
- **애플리케이션 범위**: 제공된 Python 앱은 실행 대상이며 과제의 핵심은 관제 및 자동화 스크립트 구현입니다.
- **실행 계정**: 애플리케이션은 Root 계정으로 실행하지 않습니다.
- **방화벽 정책**: 인바운드 포트는 TCP `20022`, `15034`만 허용합니다.
- **Health Check 정책**: 프로세스 또는 포트 점검 실패 시 즉시 종료 코드 `1`을 반환합니다.
- **경고 정책**: 방화벽 및 자원 임계값 경고는 스크립트를 종료시키지 않습니다.

- `t_secret.key`와 실제 인증 정보는 Git 저장소에 커밋하지 않습니다.
- 수행 내역서만 보고도 설정 과정과 검증 결과를 재현할 수 있도록 명령어와 결과를 기록합니다.

## 결과물 (Deliverables)

### 사용자 가이드 (User Guide)

- [operations.md](docs/operations.md): 설치, 환경 변수 설정, 실행, 검증 및 증빙 수집 절차
- 로컬 기능·실패·예외 경로 검증: `make test`
- Docker Desktop 실행 후 Ubuntu 24.04 통합 검증: `make test-ubuntu`

### 자동화 스크립트 (Automation Scripts)

- [setup-system.sh](bin/setup-system.sh): 보안, 계정, 권한, 앱 및 cron 구성
- [start-agent.sh](bin/start-agent.sh): 일반 계정 앱 실행
- [monitor.sh](bin/monitor.sh): 프로세스, 포트, 방화벽 및 시스템 자원 점검
- [run-monitor.sh](bin/run-monitor.sh): cron 실행 환경 로드
- [report.sh](bin/report.sh): 자원 통계 및 기간 필터링
- [archive-logs.sh](bin/archive-logs.sh): 로그 압축, 보관 및 삭제
- [verify-system.sh](bin/verify-system.sh): 시스템 설정 검증
- [collect-evidence.sh](bin/collect-evidence.sh): 제출용 증빙 수집

### 참고 문서 (Additional Documentation)

- [execution-report.md](docs/execution-report.md): 요구사항 수행 내역서
- [증빙 수집 안내](evidence/README.md)
- [Ubuntu 통합 검증 요약](evidence/ubuntu-integration-summary.md)
- [Ubuntu 24.04 원본 증빙](evidence/ubuntu-24.04/integration-20261010-refactor/)
- [기존 Ubuntu 22.04 원본 증빙](evidence/ubuntu-22.04/integration-20260818/)
