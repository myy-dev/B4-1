#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="${MONITOR_LOG_FILE:-${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log}"
FROM_TIME=""
TO_TIME=""

usage() {
  cat <<'EOF'
Usage: report.sh [--log FILE] [--from 'YYYY-MM-DD HH:MM:SS'] [--to 'YYYY-MM-DD HH:MM:SS']

Summarizes CPU, memory, and disk values recorded by monitor.sh.
EOF
}

valid_timestamp() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

while (($# > 0)); do
  case "$1" in
    --log)
      (($# >= 2)) || { printf '[ERROR] --log requires a value.\n' >&2; exit 2; }
      LOG_FILE="$2"
      shift 2
      ;;
    --from)
      (($# >= 2)) || { printf '[ERROR] --from requires a value.\n' >&2; exit 2; }
      FROM_TIME="$2"
      shift 2
      ;;
    --to)
      (($# >= 2)) || { printf '[ERROR] --to requires a value.\n' >&2; exit 2; }
      TO_TIME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[ERROR] Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -z "$FROM_TIME" ]] || valid_timestamp "$FROM_TIME" || { printf '[ERROR] Invalid --from timestamp.\n' >&2; exit 2; }
[[ -z "$TO_TIME" ]] || valid_timestamp "$TO_TIME" || { printf '[ERROR] Invalid --to timestamp.\n' >&2; exit 2; }
[[ -z "$FROM_TIME" || -z "$TO_TIME" || "$FROM_TIME" < "$TO_TIME" || "$FROM_TIME" == "$TO_TIME" ]] \
  || { printf '[ERROR] --from must not be later than --to.\n' >&2; exit 2; }

if [[ ! -r "$LOG_FILE" ]]; then
  printf '[WARNING] Log file is missing or unreadable: %s\n' "$LOG_FILE"
  exit 0
fi

awk -v from="$FROM_TIME" -v to="$TO_TIME" '
  function value(field, prefix, result) {
    result = field
    sub("^" prefix ":", "", result)
    sub(/%$/, "", result)
    return result + 0
  }

  /^\[[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\] PID:/ {
    timestamp = substr($0, 2, 19)
    if (from != "" && timestamp < from) next
    if (to != "" && timestamp > to) next

    cpu = value($4, "CPU")
    mem = value($5, "MEM")
    disk = value($6, "DISK_USED")

    count++
    cpu_sum += cpu
    mem_sum += mem
    disk_sum += disk

    if (count == 1 || cpu > cpu_max) { cpu_max = cpu; cpu_max_at = timestamp }
    if (count == 1 || cpu < cpu_min) { cpu_min = cpu; cpu_min_at = timestamp }
    if (count == 1 || mem > mem_max) { mem_max = mem; mem_max_at = timestamp }
    if (count == 1 || mem < mem_min) { mem_min = mem; mem_min_at = timestamp }
    if (count == 1 || disk > disk_max) { disk_max = disk; disk_max_at = timestamp }
    if (count == 1 || disk < disk_min) { disk_min = disk; disk_min_at = timestamp }
  }

  END {
    print "====== STATISTICS REPORT ======"
    if (count == 0) {
      print "[WARNING] No matching samples found."
      exit 0
    }

    print "[CPU]"
    printf "Average : %.1f%%\n", cpu_sum / count
    printf "Maximum : %.1f%% at %s\n", cpu_max, cpu_max_at
    printf "Minimum : %.1f%% at %s\n", cpu_min, cpu_min_at

    print "[Memory]"
    printf "Average : %.1f%%\n", mem_sum / count
    printf "Maximum : %.1f%% at %s\n", mem_max, mem_max_at
    printf "Minimum : %.1f%% at %s\n", mem_min, mem_min_at

    print "[Disk]"
    printf "Average : %.1f%%\n", disk_sum / count
    printf "Maximum : %.1f%% at %s\n", disk_max, disk_max_at
    printf "Minimum : %.1f%% at %s\n", disk_min, disk_min_at

    print "[Samples]"
    printf "Data Points: %d samples\n", count
  }
' "$LOG_FILE"
