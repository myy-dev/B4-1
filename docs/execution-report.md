# 요구사항 수행 내역서

| 항목 | 수행 환경 |
| --- | --- |
| 서버 | Docker Compose의 Ubuntu 24.04 LTS 컨테이너 |
| 아키텍처 | AMD64 (`linux/amd64`, `x86_64`) |
| 제공 앱 | `app/agent-app-linux-x86` |
| 앱 설치 위치 | `/home/agent-admin/agent-app/agent-app` |
| 앱 실행 계정 | `agent-admin` |
| SSH / 앱 포트 | TCP `20022` / TCP `15034` |

## 0. 시연용 SSH 키 준비

**실행 위치: 맥북 터미널**

```bash
mkdir -p "$HOME/.ssh"
test -f "$HOME/.ssh/b4-1-demo" || \
  ssh-keygen -t ed25519 -f "$HOME/.ssh/b4-1-demo" -N "" -C b4-1-demo
```

로컬의 개인 키가 없으면 SSH 키 한 쌍을 생성하도록 구성했습니다. 개인 키 `b4-1-demo`는 맥북에 보관하고, 공개 키 `b4-1-demo.pub`만 컨테이너에 전달합니다.

`setup.sh`는 전달받은 공개 키를 `/home/agent-admin/.ssh/authorized_keys`에 등록합니다. 기존 기록에서 `.ssh` 권한 `700`, `authorized_keys` 권한 `600`과 해당 키를 이용한 SSH 접속 성공을 확인했습니다.

## 1. 서버 실행

**실행 위치: 맥북 터미널의 프로젝트 폴더**

```bash
docker compose up --build --wait
docker compose ps
```

기존 검증에서 컨테이너의 `Healthy` 상태를 확인했습니다. Docker는 `start.sh`를 실행하고, 이 스크립트는 다음 순서로 서버를 준비합니다.

1. `setup.sh`로 계정·권한·SSH·방화벽·cron 설정
2. `/usr/sbin/sshd`로 SSH 서버 시작
3. `/usr/sbin/cron`으로 예약 작업 실행 서비스 시작
4. `agent-admin` 계정으로 제공 앱 실행

## 2. 앱 부팅과 환경 변수 확인

**실행 위치: 맥북 터미널**

```bash
docker compose logs server
docker compose exec server printenv AGENT_HOME AGENT_PORT AGENT_UPLOAD_DIR AGENT_KEY_PATH AGENT_LOG_DIR
```

기존 앱 부팅 출력에서 다음 내용을 확인했습니다. 아래는 부팅 로그의 주요 부분입니다.

```text
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
```

앱이 일반 계정으로 실행됐고, 환경 변수·키 파일·포트·로그 쓰기 권한 점검을 통과했습니다. 설정과 조회 결과에서 확인한 환경 변수는 다음과 같습니다.

| 변수 | 값 |
| --- | --- |
| `AGENT_HOME` | `/home/agent-admin/agent-app` |
| `AGENT_PORT` | `15034` |
| `AGENT_UPLOAD_DIR` | `/home/agent-admin/agent-app/upload_files` |
| `AGENT_KEY_PATH` | `/home/agent-admin/agent-app/api_keys` |
| `AGENT_LOG_DIR` | `/var/log/agent-app` |

맥북에서 TCP 연결도 확인합니다.

```bash
nc -vz 127.0.0.1 20022
nc -vz 127.0.0.1 15034
```

기존 기록에서는 재시작 후 `-w 3` 옵션을 추가해 같은 두 포트를 확인했고, 모두 연결에 성공했습니다. 다음은 당시 결과를 포트별로 발췌한 것입니다.

```text
Connection to 127.0.0.1 port 20022 [tcp/*] succeeded!
Connection to 127.0.0.1 port 15034 [tcp/*] succeeded!
```

이 결과는 TCP 연결 성공을 뜻합니다. 앱의 준비 상태는 앞의 `Agent READY`로 확인했습니다.

## 3. SSH 접속과 SSH·포트·방화벽 확인

**실행 위치: 맥북 터미널에서 SSH 접속**

```bash
ssh -i "$HOME/.ssh/b4-1-demo" -p 20022 agent-admin@127.0.0.1
```

기존 검증에서 공개 키 인증으로 접속했습니다. 다음 명령부터 8번까지는 컨테이너의 `agent-admin` SSH 셸에서 실행합니다.

```bash
whoami
sudo /usr/sbin/sshd -T | sed -n '/^port /p; /^permitrootlogin /p'
ss -ltn
sudo /usr/sbin/ufw status verbose
```

계정과 SSH 설정에서 확인한 값입니다.

```text
agent-admin
port 20022
permitrootlogin no
```

기존 포트 조회 기록은 `ss -tulnp`로 수집했습니다. 그중 시연에서 확인할 TCP 리슨 주소는 다음과 같습니다.

| 리슨 주소 | 의미 |
| --- | --- |
| `0.0.0.0:15034` | 앱의 IPv4 접속 대기 |
| `0.0.0.0:20022` | SSH의 IPv4 접속 대기 |
| `[::]:20022` | SSH의 IPv6 접속 대기 |

방화벽 조회 결과입니다.

```text
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

UFW 활성화, 기본 수신 차단, SSH·앱 포트 허용을 확인했습니다. Compose는 두 포트를 맥북의 `127.0.0.1`에 연결하도록 설정했습니다.

## 4. 계정과 그룹 확인

**실행 위치: `agent-admin` SSH 셸**

```bash
id agent-admin
id agent-dev
id agent-test
```

기존 조회 결과입니다.

```text
uid=1001(agent-admin) gid=1003(agent-admin) groups=1003(agent-admin),1001(agent-common),1002(agent-core)
uid=1002(agent-dev) gid=1004(agent-dev) groups=1004(agent-dev),1001(agent-common),1002(agent-core)
uid=1003(agent-test) gid=1005(agent-test) groups=1005(agent-test),1001(agent-common)
```

`agent-common`에는 세 계정 모두, `agent-core`에는 `agent-admin`과 `agent-dev`만 포함됐습니다. 숫자 ID보다 괄호 안의 계정·그룹 이름을 기준으로 확인합니다.

## 5. 디렉토리·파일 권한 확인

**실행 위치: `agent-admin` SSH 셸**

```bash
ls -l /home/agent-admin/agent-app
ls -ld /var/log/agent-app
ls -l /home/agent-admin/agent-app/bin/monitor.sh
ls -l /home/agent-admin/agent-app/api_keys/secret.key
getfacl -p \
  /home/agent-admin \
  /home/agent-admin/agent-app \
  /home/agent-admin/agent-app/upload_files \
  /home/agent-admin/agent-app/api_keys \
  /var/log/agent-app
```

기존 기록의 `ls`·`getfacl` 결과에서 확인한 소유권과 권한입니다.

| 대상 | 소유자 | 그룹 | 권한 |
| --- | --- | --- | --- |
| `agent-app` 디렉토리 | `agent-admin` | `agent-core` | `2770`, 추가 ACL 적용 |
| `upload_files` | `agent-admin` | `agent-common` | `2770`, 기본 ACL 적용 |
| `api_keys` | `agent-admin` | `agent-core` | `2770`, 기본 ACL 적용 |
| `/var/log/agent-app` | `agent-admin` | `agent-core` | `2770`, 기본 ACL 적용 |
| `bin` | `agent-dev` | `agent-core` | `2750` |
| `bin/monitor.sh` | `agent-dev` | `agent-core` | `750` (`-rwxr-x---`) |
| `api_keys/secret.key` | `agent-admin` | `agent-core` | `660` (`-rw-rw----`) |

상위 경로 `/home/agent-admin`과 `/home/agent-admin/agent-app`에는 다음 ACL이 있었습니다.

```text
group:agent-common:--x
```

`agent-test`가 업로드 디렉토리까지 상위 경로를 통과할 수 있도록 부여한 권한입니다.

업로드·키·로그 디렉토리에는 다음 기본 ACL이 있었습니다.

```text
default:user::rwx
default:group::rwx
default:other::---
```

setgid는 새 항목의 그룹 상속을, 기본 ACL은 새 항목의 접근 권한 상속을 담당합니다. 기존 별도 접근 점검에서도 다음 결과를 확인했습니다.

| 대상 | `agent-admin` | `agent-dev` | `agent-test` |
| --- | --- | --- | --- |
| 업로드 디렉토리 읽기·쓰기 | 가능 | 가능 | 가능 |
| 키·로그 디렉토리 읽기·쓰기 | 가능 | 가능 | 불가 |
| `monitor.sh` 읽기·실행 | 가능 | 가능 | 불가 |
| `monitor.sh` 내용 수정 | 불가 | 가능 | 불가 |

새 항목 생성 점검에서는 업로드 그룹 `agent-common`, 키·로그 그룹 `agent-core`를 상속했고, 파일 `660`·하위 디렉토리 `2770`을 확인했습니다. 자세한 권한 해석은 [계정·그룹별 권한](permissions.md)을 참고합니다.

## 6. 모니터링 수동 실행과 로그 확인

**실행 위치: `agent-admin` SSH 셸**

```bash
/home/agent-admin/agent-app/bin/monitor.sh
tail -n 5 /var/log/agent-app/monitor.log
```

기존 검증에서 수동 실행 결과와 요약 로그 기록을 확인했습니다. 다음은 당시 실행 출력입니다.

```text
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process '^/home/agent-admin/agent-app/agent-app$'... [OK] (PID: 256)
Checking port 15034... [OK]
Checking firewall... [OK]

[RESOURCE MONITORING]
CPU Usage : 4.2%
MEM Usage : 10.5%
DISK Used : 1.0%
[WARNING] MEM threshold exceeded (10.5% > 10%)

[INFO] Log appended: /var/log/agent-app/monitor.log
```

프로세스·포트·방화벽 점검을 통과했습니다. 메모리 사용률이 기준 `10%`를 넘어 경고가 발생했지만 요약 로그 기록은 완료됐습니다.

기존 최근 로그 조회에서 확인한 기록 중 한 줄입니다.

```text
[2026-10-16 07:01:47] PID:256 CPU:4.2% MEM:10.5% DISK_USED:1.0%
```

점검 시간, 앱 PID, 시스템 CPU·메모리·루트 파일시스템 사용률이 한 줄로 기록됐습니다. 로그 파일별 역할과 출력 해석은 [모니터링 로그 읽기](monitoring-logs.md)를 참고합니다.

## 7. cron 자동 실행 확인

**실행 위치: `agent-admin` SSH 셸**

```bash
crontab -l
```

기존 조회에서 다음 일정이 등록된 것을 확인했습니다.

```text
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1
```

매분 `monitor.sh`를 실행하고, 실행 메시지와 오류를 `cron.log`에 추가하는 설정입니다.

시연에서는 다음 명령으로 자동 실행 전후의 줄 수와 마지막 기록을 비교합니다.

```bash
wc -l /var/log/agent-app/monitor.log
tail -n 1 /var/log/agent-app/monitor.log
sleep 70
wc -l /var/log/agent-app/monitor.log
tail -n 1 /var/log/agent-app/monitor.log
```

기존 보고서에는 이 70초 대기 절차의 독립된 전후 출력은 없습니다. 자동 실행에 따른 로그 증가는 9번의 재시작 전후 기록에서 확인했습니다.

```bash
tail -n 20 /var/log/agent-app/cron.log
```

이 명령은 cron이 실행한 모니터링의 최근 출력·경고·오류를 확인하는 용도입니다. 기존 보고서에는 이 명령의 별도 출력이 첨부되지 않았습니다.

## 8. 프로세스·포트 장애 처리 확인

**실행 위치: `agent-admin` SSH 셸**

존재하지 않는 프로세스를 점검 대상으로 지정합니다.

```bash
AGENT_PROCESS_PATTERN='^없는프로세스$' \
  /home/agent-admin/agent-app/bin/monitor.sh
echo $?
```

기존 검증은 같은 목적의 `^missing-agent-process$` 이름을 사용했고, 다음 결과를 확인했습니다.

```text
Checking process '^missing-agent-process$'... [FAIL]
process exit=1
```

실패 메시지를 출력하고 종료 코드 `1`을 반환했습니다. 시연의 `echo $?`는 같은 종료 코드를 숫자 `1`로 표시합니다.

다음으로 실제 앱 포트와 다른 번호를 지정합니다.

```bash
AGENT_PORT=15035 \
  /home/agent-admin/agent-app/bin/monitor.sh
echo $?
```

기존 실행 결과의 주요 부분입니다.

```text
Checking process '^/home/agent-admin/agent-app/agent-app$'... [OK] (PID: 256)
Checking port 15035... [FAIL]
port exit=1
```

앱 프로세스는 정상이지만 지정한 포트가 리슨 상태가 아니어서 종료 코드 `1`을 반환했습니다. 두 명령의 환경 변수는 해당 실행에만 적용됩니다.

## 9. 재시작과 로그 보존 확인

**실행 위치: 재시작 전 `agent-admin` SSH 셸**

```bash
wc -l /var/log/agent-app/monitor.log
tail -n 5 /var/log/agent-app/monitor.log
exit
```

기존 기록은 마지막 1줄을 조회했으며, 재시작 전 상태는 다음과 같았습니다.

```text
20 /var/log/agent-app/monitor.log
[2026-10-16 10:59:25] PID:264 CPU:4.3% MEM:13.3% DISK_USED:1.0%
```

**실행 위치: 맥북 터미널**

```bash
docker compose restart server
docker compose up --wait
docker compose ps
docker compose logs server
ssh -i "$HOME/.ssh/b4-1-demo" -p 20022 agent-admin@127.0.0.1
```

기존 검증에서 컨테이너의 `Healthy` 상태와 같은 키를 이용한 SSH 재접속을 확인했습니다.

**실행 위치: 재접속한 `agent-admin` SSH 셸**

```bash
wc -l /var/log/agent-app/monitor.log
tail -n 5 /var/log/agent-app/monitor.log
ls -lh /var/log/agent-app
exit
```

기존 기록은 마지막 2줄을 조회했으며, 결과는 다음과 같았습니다.

```text
21 /var/log/agent-app/monitor.log
[2026-10-16 10:59:25] PID:264 CPU:4.3% MEM:13.3% DISK_USED:1.0%
[2026-10-16 11:00:02] PID:384 CPU:0.7% MEM:10.1% DISK_USED:1.0%
```

재시작 전의 기록이 남아 있고 새 기록이 추가되어 `20줄 → 21줄`로 증가했습니다. 당시 수동 모니터링을 멈춘 상태였고, 재시작 후에도 매분 cron 일정이 등록돼 있음을 확인했습니다.

로그 디렉토리는 Compose의 `agent-logs` 볼륨에 연결되어 있어 컨테이너 재시작 후에도 기록이 유지됩니다.

## 10. 시연 종료

**실행 위치: 맥북 터미널**

```bash
docker compose down --volumes
ssh-keygen -R '[127.0.0.1]:20022'
```

시연 종료 절차입니다. 기존 보고서에는 종료 명령의 실행 출력이 없어 완료된 검증 결과로 표시하지 않았습니다.

`down --volumes`는 컨테이너와 함께 로그 볼륨도 삭제합니다. `ssh-keygen -R`은 맥북에 저장된 해당 주소의 SSH 서버 키 기록을 제거합니다.

## 추가 검증 기록

다음은 기존 보고서에서 별도로 수행한 점검입니다. 시연 가이드 0~10번 외에 진행했던 결과를 요약했습니다.

| 점검 | 기존 확인 결과 |
| --- | --- |
| root SSH 로그인 | `Permission denied (publickey)`, 종료 코드 `255` |
| 비밀번호·대화형 SSH 인증 | `passwordauthentication no`, `kbdinteractiveauthentication no` |
| SSH 허용 계정 | `allowusers agent-admin` |
| sudo 권한 제한 | 지정된 두 조회 명령만 비밀번호 없이 허용, `sudo -n /bin/true` 거부 |
| 앱 아키텍처·설치본 | 컨테이너 `x86_64`, x86 앱과 설치본의 SHA-256 일치 |
| 모니터링 소스·설치본 | 당시 SHA-256 일치. 이후 소스 수정분의 설치본 반영 여부는 재확인 필요 |
| 메모리 측정 | 당시 `free`에서 `used / total`과 `(total - available) / total`이 모두 `10.0%` |
| 메모리 수집 실패 | 명령 실패·메모리 행 누락·전체량 0에서 각각 오류 및 종료 코드 `1` |
| 자원 경고 | 한 번의 실행에만 세 임계값을 `0`으로 지정해 CPU·메모리·디스크 경고 확인 |
| 방화벽 비활성 | 비활성 상태에서 경고 후 로그 기록·정상 종료 확인, 종료 후 UFW 재활성화 |
| 로그 회전 | 임시 경로에서 크기 한도를 `200`바이트로 낮춰 12회 회전 후 현재 로그와 `.1`~`.9` 총 10개 확인 |

모니터링 전체 소스와 계산·잠금·로그 회전 설명은 [monitor.sh](../scripts/monitor.sh)의 주석을 참고합니다.
