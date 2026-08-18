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

docker run --privileged --rm \
  --volume "${REPO_ROOT}:/workspace" \
  --workdir /workspace \
  ubuntu:22.04 \
  bash -lc './bin/setup-system.sh --apply --reset-firewall --start-app && ./bin/setup-system.sh --apply --reset-firewall --start-app && ./bin/verify-system.sh --wait-cron'
