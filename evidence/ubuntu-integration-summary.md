# Ubuntu 22.04 통합 검증 요약

- 검증 환경: Docker Desktop의 격리된 `ubuntu:22.04` ARM64 컨테이너
- 검증 명령: `make test-ubuntu`
- 검증 일자: 2026-08-18
- 최종 결과: `passed=37 failed=0`
- 원본 명령 출력: [`ubuntu-22.04/integration-20260818/`](ubuntu-22.04/integration-20260818/)

## 검증 범위

`tests/run-ubuntu-integration.sh`는 권한이 격리된 Ubuntu 컨테이너에서 다음 명령을 실행했습니다.

```bash
./bin/setup-system.sh --apply --reset-firewall --start-app
./bin/setup-system.sh --apply --reset-firewall --start-app
./bin/verify-system.sh --wait-cron
```

설치 과정에서 Ubuntu 패키지를 설치하고 UFW를 실제 활성화했으며 OpenSSH와 cron 데몬을 시작했습니다. 동일한 설치 명령을 연속 두 번 실행해 기존 계정·설정·실행 중인 앱을 안전하게 재사용하는 멱등성도 확인했습니다.

## 확인 결과

### SSH 및 방화벽

- `[PASS]` SSH 유효 포트가 `20022` 하나로 제한됨
- `[PASS]` `PermitRootLogin no` 적용
- `[PASS]` SSH가 TCP `20022`에서 LISTEN
- `[PASS]` UFW 활성화 및 TCP `20022`, `15034`만 허용

### 계정·그룹·권한

- `[PASS]` `agent-admin`, `agent-dev`, `agent-test` 계정 생성
- `[PASS]` 세 계정의 `agent-common` 그룹 구성
- `[PASS]` admin, dev의 `agent-core` 구성과 test 제외
- `[PASS]` 공유·보안·로그 디렉토리 mode `2770` 및 그룹 설정
- `[PASS]` `agent-common`, `agent-core` ACL과 상위 경로 탐색 ACL 적용
- `[PASS]` 키 파일 소유권 `agent-admin:agent-core`, mode `660`

### 애플리케이션

- `[PASS]` 필수 환경 변수 5개 설정
- `[PASS]` Root가 아닌 `agent-admin` 계정으로 실행
- `[PASS]` Boot Sequence 5단계 `[OK]` 및 `Agent READY`
- `[PASS]` 애플리케이션 TCP `15034` LISTEN

### 모니터링 및 cron

- `[PASS]` `monitor.sh` 소유권 `agent-dev:agent-core`, mode `750`
- `[PASS]` `agent-admin` 실행 권한
- `[PASS]` `agent-admin` crontab 매분 실행 등록
- `[PASS]` 70초 이내 `monitor.log` 행 증가
- `[PASS]` 최근 로그가 지정된 PID·CPU·MEM·DISK 포맷과 일치

## 자동 테스트

`make test`는 35개 항목에서 현재 아키텍처의 제공 바이너리 우선 선택, 참조 앱의 실제 15034 Health Check, 프로세스·포트 실패 종료, 일반 계정의 UFW 상태 판별, 방화벽·CPU·메모리·디스크 경고, 로그 회전, 시작·종료 기간 필터, 실제 7일 압축·30일 삭제 기준과 디렉토리·권한·대상 없음 예외 처리를 검증했습니다.

이번 Ubuntu 컨테이너의 원본 증빙은 `bin/collect-evidence.sh`로 함께 생성했습니다. 별도의 제출용 VM 또는 운영 서버를 사용한다면 해당 호스트에서도 수집기를 다시 실행해야 합니다.
