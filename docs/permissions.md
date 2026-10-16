# 계정·그룹별 권한

## 계정과 그룹

| 계정 | 역할 | 소속 공통 그룹 | 소속 핵심 그룹 |
| --- | --- | --- | --- |
| `agent-admin` | SSH 시연 접속, 제공 앱·cron 모니터링 실행 | `agent-common` | `agent-core` |
| `agent-dev` | `monitor.sh` 작성·수정, 키·로그 접근 | `agent-common` | `agent-core` |
| `agent-test` | 업로드 디렉토리 사용 | `agent-common` | 없음 |

## 디렉토리 접근 권한

| 경로 | 소유자:그룹 | 모드 | `agent-admin` | `agent-dev` | `agent-test` |
| --- | --- | --- | --- | --- | --- |
| `$AGENT_HOME` | `agent-admin:agent-core` | `2770` + ACL | 조회·생성·삭제·진입 | 조회·생성·삭제·진입 | 경로 통과만 가능 |
| `$AGENT_HOME/upload_files` | `agent-admin:agent-common` | `2770` + 기본 ACL | 조회·생성·삭제·진입 | 조회·생성·삭제·진입 | 조회·생성·삭제·진입 |
| `$AGENT_HOME/api_keys` | `agent-admin:agent-core` | `2770` + 기본 ACL | 조회·생성·삭제·진입 | 조회·생성·삭제·진입 | 접근 불가 |
| `/var/log/agent-app` | `agent-admin:agent-core` | `2770` + 기본 ACL | 조회·생성·삭제·진입 | 조회·생성·삭제·진입 | 접근 불가 |
| `$AGENT_HOME/bin` | `agent-dev:agent-core` | `2750` | 조회·진입 | 조회·생성·삭제·진입 | 접근 불가 |

- `r`: 안에 있는 파일 이름 조회
- `w`: 파일·하위 디렉토리 생성, 삭제, 이름 변경 (`x`도 필요)
- `x`: 디렉토리 진입과 그 아래의 지정된 경로 접근

## 주요 파일 권한

| 파일 | 소유자:그룹 | 모드 | `agent-admin` | `agent-dev` | `agent-test` |
| --- | --- | --- | --- | --- | --- |
| `$AGENT_HOME/bin/monitor.sh` | `agent-dev:agent-core` | `750` | 읽기·실행 | 읽기·수정·실행 | 접근 불가 |
| `$AGENT_HOME/api_keys/secret.key` | `agent-admin:agent-core` | `660` | 읽기·수정 | 읽기·수정 | 접근 불가 |
| `$AGENT_HOME/agent-app` | `agent-admin:agent-core` | `750` | 읽기·수정·실행 | 읽기·실행 | 접근 불가 |

## 디렉토리 권한 앞자리의 `2`

디렉토리 모드 `2770`, `2750`의 앞자리 `2`는 일반 접근 권한이 아니라 **setgid 특수 권한**입니다.

- `2770` = setgid `2000` + 접근 권한 `770`
- `2750` = setgid `2000` + 접근 권한 `750`

디렉토리에 setgid를 설정하면 그 안에서 새로 만든 파일과 하위 디렉토리가 부모 디렉토리의 그룹을 상속합니다. 예를 들어 `agent-common` 그룹의 `upload_files` 안에 새 파일을 만들면 새 파일도 `agent-common` 그룹을 상속합니다.

이 프로젝트의 파일 모드 `750`, `660`에는 그룹 상속이 필요하지 않으므로 앞자리 `2`를 붙이지 않았습니다. 따라서 파일에는 소유자·그룹·그 외 사용자의 일반 권한 세 자리만 표시됩니다.


