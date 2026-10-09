#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

command -v docker >/dev/null 2>&1 || {
  printf '[ERROR] Docker is required for the Ubuntu integration test.\n' >&2
  exit 1
}

docker info >/dev/null 2>&1 || {
  printf '[ERROR] Docker daemon is not running.\n' >&2
  exit 1
}

base_command='./bin/setup-system.sh --apply --reset-firewall --start-app && ./bin/setup-system.sh --apply --reset-firewall --start-app'
if [[ "${COLLECT_EVIDENCE:-0}" == "1" ]]; then
  evidence_output_root="${EVIDENCE_OUTPUT_ROOT:-/workspace/evidence/ubuntu-24.04}"
  evidence_run_id="${EVIDENCE_RUN_ID:-integration}"
  docker run --privileged --rm \
    --volume "${REPO_ROOT}:/workspace" \
    --workdir /workspace \
    --env EVIDENCE_OUTPUT_ROOT="$evidence_output_root" \
    --env EVIDENCE_RUN_ID="$evidence_run_id" \
    ubuntu:24.04 \
    bash -lc "${base_command} && ./bin/collect-evidence.sh \"\$EVIDENCE_OUTPUT_ROOT\""
else
  docker run --privileged --rm \
    --volume "${REPO_ROOT}:/workspace" \
    --workdir /workspace \
    ubuntu:24.04 \
    bash -lc "${base_command} && ./bin/verify-system.sh --wait-cron"
fi
