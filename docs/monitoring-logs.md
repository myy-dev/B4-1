# 모니터링 로그 읽기

## cron.log와 monitor.log의 차이

| 파일 | 기록 내용 | 기록 방식 |
| --- | --- | --- |
| `cron.log` | 실행 과정의 `[OK]`, `[FAIL]`, 자원 사용률, 경고·오류 메시지 | cron 명령의 `>> /var/log/agent-app/cron.log 2>&1`이 일반 출력과 오류 출력을 파일 끝에 추가 |
| `monitor.log` | 점검 시간, PID, CPU·메모리·디스크 사용률을 한 줄로 요약 | `monitor.sh`가 직접 파일에 기록 |

`monitor.sh`가 실행되면서 두 로그를 각각 기록합니다.

```text
cron이 매분 monitor.sh 실행
          │
          ├─ 실행 중 출력한 메시지·경고·오류
          │      └─ cron.log에 저장 (>> .../cron.log 2>&1)
          │
          └─ 점검 결과를 한 줄로 요약
                 └─ monitor.log에 스크립트가 직접 저장
```

실행 중 문제를 찾을 때는 `cron.log`, 시간별 자원 상태를 확인할 때는 `monitor.log`를 봅니다.

## cron.log 조회 명령과 출력

```bash
tail -n 20 /var/log/agent-app/cron.log
```

시연에서 확인한 출력은 다음과 같습니다.

```text
CPU Usage : 1.0%
MEM Usage : 12.5%
DISK Used : 1.0%
[WARNING] MEM threshold exceeded (12.5% > 10%)

[INFO] Log appended: /var/log/agent-app/monitor.log
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process '^/home/agent-admin/agent-app/agent-app$'... [OK] (PID: 265)
Checking port 15034... [OK]
Checking firewall... [OK]

[RESOURCE MONITORING]
CPU Usage : 0.6%
MEM Usage : 12.5%
DISK Used : 1.0%
[WARNING] MEM threshold exceeded (12.5% > 10%)

[INFO] Log appended: /var/log/agent-app/monitor.log
```

| 출력 | 의미 |
| --- | --- |
| `SYSTEM MONITOR RESULT` | 한 번의 모니터링 실행 결과가 시작되는 구분선 |
| `[HEALTH CHECK]` | 프로세스·포트·방화벽 점검 결과 |
| `Checking process ... [OK] (PID: 265)` | 지정한 앱 프로세스가 실행 중이며 프로세스 번호는 `265` |
| `Checking port 15034... [OK]` | TCP `15034` 포트가 연결을 기다리는 LISTEN 상태 |
| `Checking firewall... [OK]` | UFW가 활성 상태임을 확인 |
| `[RESOURCE MONITORING]` | 자원 사용률 측정 결과 |
| `CPU Usage : 0.6%` | `/proc/stat`으로 측정한 시스템 CPU 사용률 |
| `MEM Usage : 12.5%` | `free`로 계산한 시스템 메모리 사용률. 앱 하나의 메모리 사용률이 아님 |
| `DISK Used : 1.0%` | 루트 파일시스템(`/`)의 디스크 사용률 |
| `[WARNING] MEM threshold exceeded (12.5% > 10%)` | 메모리 사용률이 설정된 경고 기준 `10%`를 초과 |
| `[INFO] Log appended: .../monitor.log` | 이번 점검의 요약 한 줄을 `monitor.log`에 추가했음을 알림 |

## monitor.log 조회 명령과 형식

```bash
tail -n 1 /var/log/agent-app/monitor.log
```

가장 최근에 기록된 요약 한 줄을 출력합니다.

```text
[2026-10-17 09:00:01] PID:265 CPU:0.6% MEM:12.5% DISK_USED:1.0%
```

앞에서부터 점검 시간, 앱 프로세스 번호, 시스템 CPU 사용률, 시스템 메모리 사용률, 루트 파일시스템 사용률입니다.
