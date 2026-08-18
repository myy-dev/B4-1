# 컴퓨터가 알아서 자기 상태를 점검하게 만들기

## 프로젝트 개요 (Project Overview)

- Linux 서버의 기본 보안, 계정과 권한, 네트워크 정책을 구성하고 시스템 상태를 자동으로 점검하는 프로젝트입니다.
- 제공된 애플리케이션의 프로세스, 포트, CPU, 메모리, 디스크 상태를 Bash 스크립트로 수집하고 운영 로그로 기록합니다.
- `cron`을 이용한 정기 실행과 로그 보존 정책을 적용해 반복 가능한 서버 관제 환경을 구축합니다.
- **분야**: AI/SW 기초
- **구분**: Linux와 OS
- **학습 시간**: 40시간

## 학습 목표 (Learning Objectives)

- SSH 포트 변경과 Root 원격 접속 차단이 기본 보안에 필요한 이유를 설명할 수 있습니다.
- UFW 또는 firewalld로 필요한 포트만 허용하고 설정 결과를 검증할 수 있습니다.
- 역할 기반 계정·그룹과 ACL로 공유 디렉토리와 보안 디렉토리를 분리할 수 있습니다.
- 환경 변수로 애플리케이션 실행 환경을 고정하고 설정값을 검증할 수 있습니다.
- Bash로 프로세스, 포트, 시스템 자원을 점검하고 운영 로그를 남길 수 있습니다.
- cron으로 모니터링을 자동 실행하고 로그 압축·삭제가 필요한 이유를 설명할 수 있습니다.

## 실행 환경 (Environment)

- **운영체제**: Ubuntu 22.04 LTS 또는 동등한 Linux 환경
- **실습 환경**: 이전 미션에서 구성한 Linux 컨테이너 또는 VM 재사용 권장
- **스크립트 언어**: Bash
- **실행 애플리케이션**: 제공된 Python 애플리케이션
- **보안·운영·자동화 도구**: OpenSSH, UFW 또는 firewalld, cron
- **권한 관리 도구**: Linux 사용자·그룹 권한, ACL
- **제공 데이터**: `agent-app.zip`
- **제공 실행 파일**: `agent-app-linux-x86`, `agent-app-linux-arm64`(Apple Silicon 기반 Linux VM·컨테이너 등 ARM64 Linux 환경용)

## 프로젝트 구조 (Project Structure)

아래는 제출 결과물의 권장 구조입니다.

```text
.
├── README.md                      # 프로젝트 설명 및 수행 항목 체크리스트
├── bin/                           # 자동화 스크립트
│   ├── monitor.sh                 # 시스템 상태 수집 및 로깅 스크립트
│   ├── report.sh                  # 통계 리포트 생성 스크립트 (보너스)
│   └── archive-logs.sh            # 로그 압축·보관·삭제 스크립트 (보너스)
├── docs/
│   └── execution-report.md        # 요구사항 수행 내역 및 설정·명령어 기록
└── evidence/                      # 설정 및 실행 결과 증빙 자료
```

실제 서버에는 다음 디렉토리와 파일을 구성합니다.

```text
$AGENT_HOME/
├── bin/
│   └── monitor.sh
├── upload_files/
└── api_keys/
    └── t_secret.key

/var/log/agent-app/
└── monitor.log
```

## 수행 항목 체크리스트

### 기본 보안 및 네트워크 설정

- [ ] SSH 접속 포트를 `20022`로 변경
- [ ] Root 원격 로그인 차단(`PermitRootLogin no`)
- [ ] SSH 설정 파일에서 포트와 Root 로그인 차단 설정 확인
- [ ] `ss -tulnp`로 SSH 포트 리슨 상태 확인
- [ ] UFW 또는 firewalld 중 하나를 선택해 활성화
- [ ] 인바운드 TCP `20022`(SSH), `15034`(APP) 포트만 허용
- [ ] 그 외 불필요한 인바운드 포트 차단
- [ ] `ufw status` 또는 `firewall-cmd --list-all`로 방화벽 정책 확인

### 계정·그룹 및 권한 체계

- [ ] 운영·관리 계정 `agent-admin` 생성
- [ ] 개발·운영 계정 `agent-dev` 생성
- [ ] QA·테스트 계정 `agent-test` 생성
- [ ] 공통 그룹 `agent-common` 생성 후 `agent-admin`, `agent-dev`, `agent-test` 계정 추가
- [ ] 핵심 그룹 `agent-core` 생성 후 `agent-admin`, `agent-dev` 계정 추가
- [ ] `$AGENT_HOME/upload_files` 디렉토리 생성
- [ ] `$AGENT_HOME/api_keys` 디렉토리 생성
- [ ] `/var/log/agent-app` 디렉토리 생성
- [ ] `upload_files`의 그룹을 `agent-common`으로 설정하고 그룹 읽기·쓰기 권한 부여
- [ ] `api_keys`와 `/var/log/agent-app`의 그룹을 `agent-core`로 설정
- [ ] `api_keys`와 `/var/log/agent-app`에 `agent-core` 구성원만 읽기·쓰기 가능하도록 설정
- [ ] 필요 시 ACL을 적용해 디렉토리별 접근 권한 고정
- [ ] `id`, `ls -l`로 계정·그룹·권한 확인하고 ACL 사용 시 `getfacl`로 추가 확인

### 애플리케이션 실행 환경

- [ ] `AGENT_HOME` 설정(예: `/home/agent-admin/agent-app`)
- [ ] `AGENT_PORT=15034` 설정
- [ ] `AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files` 설정
- [ ] `AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key` 설정
- [ ] (권장) `AGENT_LOG_DIR=/var/log/agent-app` 설정(미지정 시 같은 경로를 기본값으로 사용)
- [ ] `$AGENT_HOME/api_keys/t_secret.key` 파일 생성
- [ ] 키 파일에 과제용 값 `agent_api_key_test`를 한 줄로 저장
- [ ] 애플리케이션을 Root가 아닌 일반 계정으로 실행
- [ ] Boot Sequence 5단계가 모두 `[OK]`인지 확인
- [ ] 마지막 출력에서 `Agent READY` 확인
- [ ] 애플리케이션이 `0.0.0.0:15034`에서 LISTEN 상태인지 확인

> 애플리케이션을 종료할 때는 `Ctrl+C`를 사용합니다.

### 시스템 관제 자동화 (`monitor.sh`)

- [ ] 스크립트를 `$AGENT_HOME/bin/monitor.sh`에 작성
- [ ] 소유자를 `agent-dev`, 그룹을 `agent-core`로 설정
- [ ] 파일 권한을 `750`(`rwxr-x---`)으로 설정
- [ ] `agent-admin` 계정이 스크립트를 실행할 수 있는지 확인
- [ ] `agent_app.py` 또는 제공된 앱 프로세스의 실행 상태 확인
- [ ] 프로세스가 비정상이면 종료 코드 `1` 반환
- [ ] TCP `15034` 포트의 LISTEN 상태 확인
- [ ] 포트가 비정상이면 종료 코드 `1` 반환
- [ ] UFW 또는 firewalld 활성화 상태 확인
- [ ] 방화벽이 비활성 상태이면 `[WARNING]`만 출력하고 점검 계속 진행
- [ ] CPU 사용률(%) 수집
- [ ] 메모리 사용률(%) 수집
- [ ] 루트 파티션 디스크 사용률(%) 수집
- [ ] CPU 사용률이 20%를 초과하면 `[WARNING]` 출력
- [ ] 메모리 사용률이 10%를 초과하면 `[WARNING]` 출력
- [ ] 디스크 사용률이 80%를 초과하면 `[WARNING]` 출력
- [ ] `/var/log/agent-app/monitor.log`에 점검 결과 누적 기록
- [ ] 로그 포맷을 `[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%`로 구성
- [ ] logrotate 또는 스크립트 로직으로 로그 파일을 최대 10MB, 10개까지 유지

### 자동 실행 (`cron`)

- [ ] `agent-admin` 계정의 crontab에 `monitor.sh` 매분 실행 등록
- [ ] 등록 후 1~2분 내 `monitor.log`에 새 로그가 추가되는지 확인

#### 권장 점검

- cron 실행 환경에 필요한 환경 변수를 명시적으로 설정합니다.
- cron 실행 중 권한 오류나 경로 오류가 없는지 확인합니다.

### 요구사항 수행 내역서 및 증빙

- [ ] SSH 포트 `20022` 변경 및 Root 원격 접속 차단 설정 기록
- [ ] 방화벽 활성화 및 TCP `20022`, `15034`만 허용한 내역 기록
- [ ] 계정 `agent-admin`, `agent-dev`, `agent-test` 생성 내역 기록
- [ ] 그룹 `agent-common`, `agent-core`와 구성원 설정 내역 기록
- [ ] 디렉토리 구조와 일반 권한·ACL 확인 내역 기록
- [ ] 환경 변수와 cron 등록 명령 기록
- [ ] 앱 Boot Sequence 5단계 `[OK]` 및 `Agent READY` 출력 첨부
- [ ] `monitor.sh`의 프로세스·포트·리소스·경고 출력 첨부
- [ ] `/var/log/agent-app/monitor.log` 최근 누적 로그 첨부
- [ ] cron 등록 전후 로그를 비교해 자동 실행 증명
- [ ] `monitor.sh` 전체 소스코드 제출

### 보너스 과제

- [ ] **통계 리포트**: `report.sh`로 CPU, 메모리, 디스크의 평균·최대·최소와 샘플 수 출력
- [ ] **기간 필터링**: 시작·종료 시간을 입력받아 해당 구간의 로그만 분석
- [ ] **로그 압축**: `/var/log/agent-app/*.log` 중 7일 이상 지난 파일 압축
- [ ] **로그 아카이브**: 압축 파일을 `/var/log/monitor/agent-app/archive/`로 이동
- [ ] **오래된 로그 삭제**: 아카이브의 `.gz` 파일 중 30일 이상 지난 파일 삭제
- [ ] **예외 처리**: 디렉토리 미존재, 권한 부족, 대상 파일 없음 상황을 안전하게 처리

### 제약 사항 (Constraints)

- **구현 언어**: 자동화 스크립트는 Bash로만 작성하며 Python 등으로 대체하지 않습니다.
- **권한 원칙**: 필요한 경우에만 `sudo`를 사용하고 가능한 작업은 일반 계정으로 수행합니다.
- **애플리케이션 범위**: 제공된 Python 앱은 실행 대상이며 과제의 핵심은 관제 및 자동화 스크립트 구현입니다.
- **실행 계정**: 애플리케이션은 Root 계정으로 실행하지 않습니다.
- **방화벽 정책**: 인바운드 포트는 TCP `20022`, `15034`만 허용합니다.
- **Health Check 정책**: 프로세스 또는 포트 점검 실패 시 즉시 종료 코드 `1`을 반환합니다.
- **경고 정책**: 방화벽 및 자원 임계값 경고는 스크립트를 종료시키지 않습니다.

### 권장 운영 사항

- `t_secret.key`와 실제 인증 정보는 Git 저장소에 커밋하지 않습니다.
- 수행 내역서만 보고도 설정 과정과 검증 결과를 재현할 수 있도록 명령어와 결과를 기록합니다.

### 커스텀 설정값 명세

| 항목 | 기준값 | 비고 |
| --- | --- | --- |
| SSH 포트 | `20022/tcp` | 필수 |
| 애플리케이션 포트 | `15034/tcp` | 필수 |
| 애플리케이션 바인딩 | `0.0.0.0:15034` | 필수 |
| CPU 경고 임계값 | 20% 초과 | 경고 후 계속 실행 |
| 메모리 경고 임계값 | 10% 초과 | 경고 후 계속 실행 |
| 디스크 경고 임계값 | 80% 초과 | 루트 파티션 기준 |
| 모니터링 주기 | 매분 | `agent-admin` crontab |
| 로그 파일 | `/var/log/agent-app/monitor.log` | 누적 기록 |
| 로그 파일 최대 크기 | 10MB | 필수 |
| 로그 보관 개수 | 10개 | 필수 |
| 로그 압축 기준 | 7일 경과 | 보너스 |
| 아카이브 삭제 기준 | 30일 경과 | 보너스 |

## 결과물 (Deliverables)

- **요구사항 수행 내역서 1개**
  - 수행 내역
  - SSH, 방화벽, 계정·그룹·ACL, 디렉토리·권한, 환경 변수, cron 설정 및 명령어 기록
  - 필수 증빙 자료
- **자동화 스크립트 소스코드**
  - 필수: `monitor.sh`
  - 보너스: `report.sh`, 로그 보존 자동화 스크립트

## 완료 기준

- SSH와 방화벽 정책이 요구값으로 설정되고 명령어 출력으로 검증되어야 합니다.
- 계정·그룹·디렉토리 권한이 최소 권한 원칙에 맞게 적용되어야 합니다.
- 앱의 Boot Sequence 5단계가 모두 통과하고 `Agent READY`가 출력되어야 합니다.
- `monitor.sh`가 프로세스, 포트, 방화벽, CPU, 메모리, 디스크를 점검하고 로그를 남겨야 합니다.
- cron 등록 후 별도 수동 실행 없이 `monitor.log`가 매분 증가해야 합니다.
