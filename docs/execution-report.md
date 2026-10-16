# 요구사항 수행 내역서

## 수행 환경과 실행 방법

- 검증 일시: 2026-10-16 (아래 출력의 시간은 컨테이너 UTC 기준)
- 환경: Docker Compose의 Ubuntu 24.04 LTS AMD64 서버
- 제공 앱: `app/agent-app-linux-x86` → `/home/agent-admin/agent-app/agent-app`
- 실행 계정: `agent-admin`
- 구성: `scripts/setup.sh`, `scripts/start.sh`, `scripts/monitor.sh`

```bash
docker compose up --build --wait
```

Compose의 환경 변수로 앱 경로와 포트를 지정하고, 시작 스크립트가 계정·권한·SSH·UFW·cron을 설정한 뒤 앱을 실행합니다. 앱과 모니터링 로그는 `/var/log/agent-app` 볼륨에 보존됩니다. 제공 앱이 요구하는 키는 `AGENT_KEY_PATH` 디렉토리의 `secret.key`이며, 설정 시 과제용 값 `agent_api_key_test`를 생성합니다.

## 필수 증거 자료 체크리스트

- [x] SSH 포트 `20022`와 Root 원격 로그인 차단
- [x] UFW 활성화, 기본 인바운드 차단, TCP `20022`·`15034`만 허용
- [x] 세 계정과 `agent-common`·`agent-core` 그룹 구성
- [x] 디렉토리 구조·소유권·권한·ACL과 실제 접근 가능 여부
- [x] 환경 변수와 `agent-admin`의 매분 cron 등록
- [x] 제공 앱의 Boot Sequence 5단계 `[OK]`, `Agent READY`, 일반 계정 실행
- [x] 프로세스·포트·시스템 자원 점검과 경고, 장애 시 종료 코드 `1`
- [x] 지정 포맷의 최근 모니터링 로그와 cron에 의한 로그 증가
- [x] `monitor.sh` 전체 소스 제출 및 설치본 일치

아래에 설정 명령과 실제 실행 출력을 함께 기록했습니다. 명령은 다음으로 진입한 컨테이너 셸 기준입니다.

```bash
docker compose exec server bash
```

## 실행 환경

```bash
date -Is; . /etc/os-release; echo "$PRETTY_NAME"; uname -m
```

```text
2026-10-16T01:22:10+00:00
Ubuntu 24.04.5 LTS
x86_64
```

## SSH·포트·방화벽

```bash
sshd -T | sed -n '/^port /p; /^permitrootlogin /p'; ss -tulnp; ufw status verbose
```

```text
port 20022
permitrootlogin no
Netid State  Recv-Q Send-Q Local Address:Port  Peer Address:PortProcess
udp   UNCONN 0      0         127.0.0.11:50983      0.0.0.0:*
tcp   LISTEN 0      1            0.0.0.0:15034      0.0.0.0:*
tcp   LISTEN 0      4096      127.0.0.11:42839      0.0.0.0:*
tcp   LISTEN 0      128          0.0.0.0:20022      0.0.0.0:*    users:(("sshd",pid=253,fd=3))
tcp   LISTEN 0      128             [::]:20022         [::]:*    users:(("sshd",pid=253,fd=4))
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW IN    Anywhere
15034/tcp                  ALLOW IN    Anywhere
20022/tcp (v6)             ALLOW IN    Anywhere (v6)
15034/tcp (v6)             ALLOW IN    Anywhere (v6)
```

## 계정·그룹

```bash
id agent-admin; id agent-dev; id agent-test; getent group agent-common agent-core
```

```text
uid=1001(agent-admin) gid=1003(agent-admin) groups=1003(agent-admin),1001(agent-common),1002(agent-core)
uid=1002(agent-dev) gid=1004(agent-dev) groups=1004(agent-dev),1001(agent-common),1002(agent-core)
uid=1003(agent-test) gid=1005(agent-test) groups=1005(agent-test),1001(agent-common)
agent-common:x:1001:agent-admin,agent-dev,agent-test
agent-core:x:1002:agent-admin,agent-dev
```

## 디렉토리 권한·ACL

```bash
ls -ld /home/agent-admin/agent-app /home/agent-admin/agent-app/{bin,upload_files,api_keys} /var/log/agent-app; ls -l /home/agent-admin/agent-app/bin/monitor.sh /home/agent-admin/agent-app/api_keys/secret.key; getfacl -p /home/agent-admin /home/agent-admin/agent-app /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app
```

```text
drwxrws---+ 5 agent-admin agent-core   4096 Oct 16 01:21 /home/agent-admin/agent-app
drwxrws---+ 2 agent-admin agent-core   4096 Oct 16 01:21 /home/agent-admin/agent-app/api_keys
drwxr-s---  2 agent-dev   agent-core   4096 Oct 16 01:21 /home/agent-admin/agent-app/bin
drwxrws---+ 2 agent-admin agent-common 4096 Oct 16 01:21 /home/agent-admin/agent-app/upload_files
drwxrws---+ 2 agent-admin agent-core   4096 Oct 16 01:21 /var/log/agent-app
-rw-rw----+ 1 agent-admin agent-core   19 Oct 16 01:21 /home/agent-admin/agent-app/api_keys/secret.key
-rwxr-x---  1 agent-dev   agent-core 5160 Oct 16 01:21 /home/agent-admin/agent-app/bin/monitor.sh
# file: /home/agent-admin
# owner: agent-admin
# group: agent-admin
user::rwx
group::r-x
group:agent-common:--x
mask::r-x
other::---

# file: /home/agent-admin/agent-app
# owner: agent-admin
# group: agent-core
# flags: -s-
user::rwx
group::rwx
group:agent-common:--x
mask::rwx
other::---

# file: /home/agent-admin/agent-app/upload_files
# owner: agent-admin
# group: agent-common
# flags: -s-
user::rwx
group::rwx
group:agent-common:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-common:rwx
default:mask::rwx
default:other::---

# file: /home/agent-admin/agent-app/api_keys
# owner: agent-admin
# group: agent-core
# flags: -s-
user::rwx
group::rwx
group:agent-core:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-core:rwx
default:mask::rwx
default:other::---

# file: /var/log/agent-app
# owner: agent-admin
# group: agent-core
# flags: -s-
user::rwx
group::rwx
group:agent-core:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-core:rwx
default:mask::rwx
default:other::---
```

## 계정별 실제 접근 권한

```bash
runuser -u agent-test -- bash -c 'touch "$AGENT_UPLOAD_DIR/.permission-check" && rm "$AGENT_UPLOAD_DIR/.permission-check" && echo "agent-test: upload write OK"; if cat "$AGENT_KEY_PATH/secret.key" >/dev/null 2>&1; then exit 1; else echo "agent-test: key read DENIED"; fi; if ls "$AGENT_LOG_DIR" >/dev/null 2>&1; then exit 1; else echo "agent-test: log access DENIED"; fi'; runuser -u agent-dev -- bash -c 'test -w "$AGENT_KEY_PATH/secret.key" && test -w "$AGENT_LOG_DIR" && echo "agent-dev: key/log write OK"'
```

```text
agent-test: upload write OK
agent-test: key read DENIED
agent-test: log access DENIED
agent-dev: key/log write OK
```

## 환경 변수·cron 등록

```bash
env | sort | sed -n '/^AGENT_/p'; crontab -u agent-admin -l
```

```text
AGENT_HOME=/home/agent-admin/agent-app
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
AGENT_LOG_DIR=/var/log/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1
```

## 제공 앱 실행

```bash
ps -C agent-app -o user,pid,args; head -n 15 /var/log/agent-app/agent-app.out
```

```text
USER       PID COMMAND
agent-a+   258 /run/rosetta/rosetta /home/agent-admin/agent-app/agent-app /home/agent-admin/agent-app/agent-app
agent-a+   259 /run/rosetta/rosetta /home/agent-admin/agent-app/agent-app /home/agent-admin/agent-app/agent-app
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
   ... Running as service user 'agent-admin' (uid=1001)
[2/5] Verifying Environment Variables     [OK]
   ... All required Envs correct
[3/5] Checking Required Files             [OK]
   ... Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]
   ... Port 15034 is available.
[5/5] Verifying Log Permission            [OK]
   ... Log directory is writable: /var/log/agent-app
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
2026-10-16 01:21:26,258 [INFO] [SafetyGuard] Process priority lowered (nice=10).
```

## 일반 사용자 모니터링·최근 로그

```bash
runuser -u agent-admin -- /home/agent-admin/agent-app/bin/monitor.sh; tail -n 3 /var/log/agent-app/monitor.log
```

```text
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process '^/home/agent-admin/agent-app/agent-app$'... [OK] (PID: 258)
Checking port 15034... [OK]
Checking firewall... [OK]

[RESOURCE MONITORING]
CPU Usage : 3.7%
MEM Usage : 12.1%
DISK Used : 1.0%
[WARNING] MEM threshold exceeded (12.1% > 10%)

[INFO] Log appended: /var/log/agent-app/monitor.log
[2026-10-16 01:21:03] PID:306 CPU:3.8% MEM:12.4% DISK_USED:1.0%
[2026-10-16 01:22:02] PID:258 CPU:4.3% MEM:11.0% DISK_USED:1.0%
[2026-10-16 01:22:14] PID:258 CPU:3.7% MEM:12.1% DISK_USED:1.0%
```

## 자원 임계값 경고

기본 임계값은 CPU 20%, 메모리 10%, 디스크 80%입니다. 아래 실행에만 임계값을 0으로 낮춰 실제 측정값으로 세 경고 경로를 확인했습니다. 서버의 기본 설정은 바꾸지 않았습니다.

```bash
runuser -u agent-admin -- env CPU_THRESHOLD=0 MEM_THRESHOLD=0 DISK_THRESHOLD=0 /home/agent-admin/agent-app/bin/monitor.sh
```

```text
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process '^/home/agent-admin/agent-app/agent-app$'... [OK] (PID: 258)
Checking port 15034... [OK]
Checking firewall... [OK]

[RESOURCE MONITORING]
CPU Usage : 3.0%
MEM Usage : 12.1%
DISK Used : 1.0%
[WARNING] CPU threshold exceeded (3.0% > 0%)
[WARNING] MEM threshold exceeded (12.1% > 0%)
[WARNING] DISK_USED threshold exceeded (1.0% > 0%)

[INFO] Log appended: /var/log/agent-app/monitor.log
```

## 프로세스·포트 실패 시 종료 코드

```bash
set +e
runuser -u agent-admin -- env AGENT_PROCESS_PATTERN="^missing-agent-process$" /home/agent-admin/agent-app/bin/monitor.sh
process_status=$?
echo "process exit=$process_status"
runuser -u agent-admin -- env AGENT_PORT=15035 /home/agent-admin/agent-app/bin/monitor.sh
port_status=$?
echo "port exit=$port_status"
test "$process_status" = 1 && test "$port_status" = 1
```

```text
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process '^missing-agent-process$'... [FAIL]
process exit=1
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process '^/home/agent-admin/agent-app/agent-app$'... [OK] (PID: 258)
Checking port 15035... [FAIL]
port exit=1
```

## 방화벽 비활성 경고

UFW를 잠시 비활성화해 경고 후 정상 종료하는지 확인했습니다. 명령 종료 시 UFW를 다시 활성화합니다.

```bash
(
  trap 'ufw --force enable >/dev/null' EXIT
  ufw disable >/dev/null
  runuser -u agent-admin -- /home/agent-admin/agent-app/bin/monitor.sh
  echo "monitor exit=$?"
)
```

```text
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process '^/home/agent-admin/agent-app/agent-app$'... [OK] (PID: 258)
Checking port 15034... [OK]
[WARNING] Firewall is inactive or its status could not be determined.

[RESOURCE MONITORING]
CPU Usage : 4.5%
MEM Usage : 12.8%
DISK Used : 1.0%
[WARNING] MEM threshold exceeded (12.8% > 10%)

[INFO] Log appended: /var/log/agent-app/monitor.log
monitor exit=0
```

## 크기 기반 로그 회전

파일 크기 기본값은 10MB이며, 현재 로그와 이전 로그 9개를 합쳐 최대 10개로 고정합니다. 아래에서는 임시 로그를 매번 200바이트로 채우고 크기 한도만 200바이트로 낮춰 12번 회전시켰습니다. 가장 오래된 기록이 삭제되어 총 10개가 남는지 확인한 후 임시 로그를 삭제했습니다.

```bash
set -euo pipefail
rotation_dir=$(mktemp -d)
trap 'rm -r "$rotation_dir"' EXIT
chown agent-admin:agent-core "$rotation_dir"
for iteration in {1..12}; do
  printf '%0200d' "$iteration" > "$rotation_dir/monitor.log"
  runuser -u agent-admin -- env AGENT_LOG_DIR="$rotation_dir" LOG_MAX_BYTES=200 /home/agent-admin/agent-app/bin/monitor.sh >/dev/null
done
find "$rotation_dir" -name 'monitor.log*' -printf '%f %s bytes\n' | sort
count=$(find "$rotation_dir" -name 'monitor.log*' | wc -l)
test "$count" = 10
test -f "$rotation_dir/monitor.log.9"
test ! -e "$rotation_dir/monitor.log.10"
grep -qx '0*4' "$rotation_dir/monitor.log.9"
find "$rotation_dir" -name 'monitor.log*' -size +200c | (! read)
echo 'PASS: maximum 10 files; oldest archives discarded'
```

```text
monitor.log 64 bytes
monitor.log.1 200 bytes
monitor.log.2 200 bytes
monitor.log.3 200 bytes
monitor.log.4 200 bytes
monitor.log.5 200 bytes
monitor.log.6 200 bytes
monitor.log.7 200 bytes
monitor.log.8 200 bytes
monitor.log.9 200 bytes
PASS: maximum 10 files; oldest archives discarded
```

## 제출 소스와 설치본 일치

전체 제출 소스는 [scripts/monitor.sh](../scripts/monitor.sh)입니다. 아래 두 해시가 같습니다.

```bash
sha256sum /opt/agent-lab/scripts/monitor.sh /home/agent-admin/agent-app/bin/monitor.sh
```

```text
910ef6098d6998e807ad46daead81de668fff660919aa4db86384a39abfc8627  /opt/agent-lab/scripts/monitor.sh
910ef6098d6998e807ad46daead81de668fff660919aa4db86384a39abfc8627  /home/agent-admin/agent-app/bin/monitor.sh
```

## cron 확인 전 로그

이 시점 이후 수동 모니터링을 실행하지 않고 기다렸습니다. 컨테이너 상태 확인 명령은 모니터링 로그를 기록하지 않습니다.

```bash
date -Is; wc -l /var/log/agent-app/monitor.log; tail -n 1 /var/log/agent-app/monitor.log
```

```text
2026-10-16T01:22:37+00:00
393 /var/log/agent-app/monitor.log
[2026-10-16 01:22:21] PID:258 CPU:4.5% MEM:12.8% DISK_USED:1.0%
```

## cron 확인 후 로그

```bash
date -Is; wc -l /var/log/agent-app/monitor.log; tail -n 3 /var/log/agent-app/monitor.log
```

```text
2026-10-16T01:23:55+00:00
394 /var/log/agent-app/monitor.log
[2026-10-16 01:22:15] PID:258 CPU:3.0% MEM:12.1% DISK_USED:1.0%
[2026-10-16 01:22:21] PID:258 CPU:4.5% MEM:12.8% DISK_USED:1.0%
[2026-10-16 01:23:02] PID:258 CPU:4.2% MEM:11.0% DISK_USED:1.0%
```

확인 전 393줄보다 로그 행 수가 늘었고, 매분 예약 실행 시각의 기록이 추가되었습니다. 위 대기 구간에는 수동 모니터링을 실행하지 않았습니다.

## 재시작 및 로그 보존

```bash
docker compose restart server
docker compose up --wait
docker compose exec server bash
date -Is; ps -C agent-app -o user,pid,args; head -n 15 /var/log/agent-app/agent-app.out; ufw status; crontab -u agent-admin -l
```

```text
2026-10-16T01:24:42+00:00
USER       PID COMMAND
agent-a+   384 /run/rosetta/rosetta /home/agent-admin/agent-app/agent-app /home/agent-admin/agent-app/agent-app
agent-a+   385 /run/rosetta/rosetta /home/agent-admin/agent-app/agent-app /home/agent-admin/agent-app/agent-app
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
   ... Running as service user 'agent-admin' (uid=1001)
[2/5] Verifying Environment Variables     [OK]
   ... All required Envs correct
[3/5] Checking Required Files             [OK]
   ... Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]
   ... Port 15034 is available.
[5/5] Verifying Log Permission            [OK]
   ... Log directory is writable: /var/log/agent-app
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
2026-10-16 01:24:03,619 [INFO] [SafetyGuard] Process priority lowered (nice=10).
Status: active

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW       Anywhere
15034/tcp                  ALLOW       Anywhere
20022/tcp (v6)             ALLOW       Anywhere (v6)
15034/tcp (v6)             ALLOW       Anywhere (v6)

* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1
```

재시작 전 마지막 로그가 재시작 후에도 보존되어 있습니다.

```text
[2026-10-16 01:23:02] PID:258 CPU:4.2% MEM:11.0% DISK_USED:1.0%
```

## 로컬 PC의 공개 포트 연결

컨테이너 재시작 후 로컬 PC에서 실행했습니다.

```bash
nc -vz -w 3 127.0.0.1 15034
nc -vz -w 3 127.0.0.1 20022
```

```text
Connection to 127.0.0.1 port 15034 [tcp/*] succeeded!
Connection to 127.0.0.1 port 20022 [tcp/*] succeeded!
```
