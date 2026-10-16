# 컴퓨터가 알아서 자기 상태를 점검하게 만들기

## 프로젝트 개요 (Project Overview)

Linux 서버의 보안·계정·권한을 구성하고, Bash 스크립트로 제공 앱과 시스템 자원을 점검해 로그로 기록합니다.

## 실행 환경 (Environment)

- **운영체제**: Docker의 Ubuntu 24.04 LTS
- **기본 아키텍처**: AMD64 (ARM64 호스트에서는 에뮬레이션)
- **제공 앱**: `app/agent-app-linux-x86`, `app/agent-app-linux-arm64`
- **실행 계정**: 일반 사용자 `agent-admin`
- **사용 도구**: Bash, OpenSSH, UFW, cron, ACL, `ps`, `ss`, `df`
- **포트**: SSH `20022/tcp`, 앱 `15034/tcp`

## 프로젝트 구조 (Project Structure)

```text
.
├── README.md
├── Dockerfile
├── compose.yaml
├── app/
│   ├── agent-app-linux-x86
│   └── agent-app-linux-arm64
├── scripts/
│   ├── setup.sh             # 컨테이너의 계정·권한·SSH·UFW·cron 설정
│   ├── start.sh             # 설정 후 SSH·cron·제공 앱 실행
│   └── monitor.sh           # 상태 점검·경고·로그 기록·크기 기반 로그 회전
└── docs/
    ├── docker-demo.md       # Docker 실행·점검·종료 안내
    └── execution-report.md  # 수행 내역·필수 체크리스트·명령 실행 결과
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
- [x] `$AGENT_HOME` 디렉토리 생성
- [x] `$AGENT_HOME/upload_files` 디렉토리 생성
- [x] `$AGENT_HOME/api_keys` 디렉토리 생성
- [x] `/var/log/agent-app` 디렉토리 생성
- [x] `upload_files`의 그룹을 `agent-common`으로 설정하고 그룹 읽기·쓰기 권한 부여
- [x] `api_keys`와 `/var/log/agent-app`의 그룹을 `agent-core`로 설정
- [x] `api_keys`와 `/var/log/agent-app`에 `agent-core` 구성원만 읽기·쓰기 가능하도록 설정
- [x] 필요 시 ACL을 적용해 디렉토리별 접근 권한 고정
- [x] `id`, `ls -l`로 계정·그룹·권한 확인하고 ACL 사용 시 `getfacl`로 추가 확인

### 애플리케이션 실행 환경

> 과제에서 제공한 ARM64·x86 실행 파일을 사용합니다. 설치 시 아키텍처에 맞는 파일을 `$AGENT_HOME/agent-app`으로 복사합니다. 실제 제공 앱은 `AGENT_KEY_PATH`에 디렉토리를 받고 그 안의 `secret.key`를 읽으므로 해당 실행 규약에 맞춰 구성했습니다.

- [x] `AGENT_HOME` 설정(예: `/home/agent-admin/agent-app`)
- [x] `AGENT_PORT=15034` 설정
- [x] `AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files` 설정
- [x] `AGENT_KEY_PATH=$AGENT_HOME/api_keys` 설정(제공 앱이 요구하는 키 디렉토리)
- [x] (권장) `AGENT_LOG_DIR=/var/log/agent-app` 설정(미지정 시 같은 경로를 기본값으로 사용)
- [x] `$AGENT_HOME/api_keys/secret.key` 파일 생성(제공 앱이 읽는 키 파일)
- [x] 키 파일에 과제용 값 `agent_api_key_test`를 한 줄로 저장
- [x] 애플리케이션을 Root가 아닌 일반 계정으로 실행
- [x] Boot Sequence 5단계가 모두 `[OK]`인지 확인
- [x] 마지막 출력에서 `Agent READY` 확인
- [x] 애플리케이션이 `0.0.0.0:15034`에서 LISTEN 상태인지 확인
- [x] 실제 제공 앱으로 위 실행 결과 재확인

### 시스템 관제 자동화 (`monitor.sh`)

- [x] 스크립트를 `$AGENT_HOME/bin/monitor.sh`에 작성
- [x] 소유자를 `agent-dev`, 그룹을 `agent-core`로 설정
- [x] 파일 권한을 `750`(`rwxr-x---`)으로 설정
- [x] `agent-admin` 계정이 스크립트를 실행할 수 있는지 확인
- [x] 제공된 앱 프로세스의 실행 상태 확인
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

### 구현 언어 및 권한 원칙

- [x] 자동화 스크립트를 Bash로만 구현
- [x] 필요한 경우에만 관리자 권한을 사용하고 가능한 작업은 일반 계정으로 수행

### 요구사항 수행 내역서 및 증빙

- [x] SSH 포트 `20022` 변경 및 Root 원격 접속 차단 설정 기록
- [x] 방화벽 활성화 및 TCP `20022`, `15034`만 허용한 내역 기록
- [x] 계정 `agent-admin`, `agent-dev`, `agent-test` 생성 내역 기록
- [x] 그룹 `agent-common`, `agent-core`와 구성원 설정 내역 기록
- [x] 디렉토리 구조와 일반 권한·ACL 확인 내역 기록
- [x] 환경 변수와 cron 등록 명령 기록
- [x] 앱 Boot Sequence 5단계 `[OK]` 및 `Agent READY` 출력 첨부(제공 앱)
- [x] `monitor.sh`의 프로세스·포트·리소스·경고 출력 첨부
- [x] `/var/log/agent-app/monitor.log` 최근 누적 로그 첨부
- [x] cron 등록 전후 로그를 비교해 자동 실행 증명
- [x] `monitor.sh` 전체 소스코드 제출

## 결과물 (Deliverables)

- [monitor.sh](scripts/monitor.sh): 제출용 관제 스크립트 전체 소스
- [수행 내역서](docs/execution-report.md): 필수 증거 자료 체크리스트, 설정 명령과 실제 출력

제공 앱은 `AGENT_KEY_PATH`에 디렉토리 경로를 받고 그 안의 `secret.key`를 읽습니다. 과제용 값 `agent_api_key_test`는 컨테이너 설정 시 생성됩니다.
