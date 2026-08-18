# 증빙 자료

재현 가능한 Ubuntu 22.04 컨테이너 증빙은 [`ubuntu-22.04/integration-20260818/`](ubuntu-22.04/integration-20260818/)에 포함되어 있습니다. Docker Desktop에서 새 증빙을 생성하려면 다음 명령을 실행합니다.

```bash
EVIDENCE_RUN_ID=integration make evidence-ubuntu
```

Ubuntu 시스템에 적용한 뒤 다음 명령으로 증빙을 생성합니다.

```bash
sudo ./bin/collect-evidence.sh "$(pwd)/evidence/runs"
```

생성 결과는 `evidence/runs/<timestamp>/` 아래에 저장되며 Git에서는 기본적으로 제외됩니다. 파일 내용을 검토하고 호스트명, 사용자 정보 등 제출에 불필요한 정보를 제거한 뒤 필요한 자료만 별도로 제출하십시오.

비밀 키 파일의 내용은 수집 대상이 아닙니다.
