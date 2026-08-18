#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}"
ARCHIVE_AFTER_DAYS="${ARCHIVE_AFTER_DAYS:-7}"
DELETE_AFTER_DAYS="${DELETE_AFTER_DAYS:-30}"
ARCHIVE_ALL="${ARCHIVE_ALL:-0}"
DELETE_ALL="${DELETE_ALL:-0}"

warn() {
  printf '[WARNING] %s\n' "$*"
}

if [[ ! "$ARCHIVE_AFTER_DAYS" =~ ^[0-9]+$ || ! "$DELETE_AFTER_DAYS" =~ ^[0-9]+$ ]]; then
  printf '[ERROR] Retention days must be non-negative integers.\n' >&2
  exit 2
fi

if [[ ! -d "$LOG_DIR" ]]; then
  warn "Log directory does not exist: ${LOG_DIR}"
  exit 0
fi

if ! mkdir -p "$ARCHIVE_DIR" 2>/dev/null; then
  warn "Cannot create archive directory: ${ARCHIVE_DIR}"
  exit 0
fi

if [[ ! -w "$ARCHIVE_DIR" ]]; then
  warn "Archive directory is not writable: ${ARCHIVE_DIR}"
  exit 0
fi

archived=0
deleted=0

archive_file() {
  local source="$1" base destination temporary suffix
  base=$(basename "$source")
  destination="${ARCHIVE_DIR}/${base}.gz"
  if [[ -e "$destination" ]]; then
    suffix=$(date '+%Y%m%d%H%M%S')
    destination="${ARCHIVE_DIR}/${base}.${suffix}.gz"
  fi
  temporary="${destination}.tmp.$$"

  if gzip -c "$source" >"$temporary" && mv "$temporary" "$destination" && rm -f "$source"; then
    printf '[INFO] Archived: %s -> %s\n' "$source" "$destination"
    archived=$((archived + 1))
  else
    rm -f "$temporary"
    warn "Failed to archive: ${source}"
  fi
}

delete_archive() {
  local target="$1"
  if rm -f "$target"; then
    printf '[INFO] Deleted expired archive: %s\n' "$target"
    deleted=$((deleted + 1))
  else
    warn "Failed to delete expired archive: ${target}"
  fi
}

if [[ "$ARCHIVE_ALL" == "1" ]]; then
  while IFS= read -r -d '' file; do
    archive_file "$file"
  done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -print0 2>/dev/null)
else
  archive_mtime=$((ARCHIVE_AFTER_DAYS - 1))
  ((archive_mtime >= 0)) || archive_mtime=0
  while IFS= read -r -d '' file; do
    archive_file "$file"
  done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime "+${archive_mtime}" -print0 2>/dev/null)
fi

if [[ "$DELETE_ALL" == "1" ]]; then
  while IFS= read -r -d '' file; do
    delete_archive "$file"
  done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.gz' -print0 2>/dev/null)
else
  delete_mtime=$((DELETE_AFTER_DAYS - 1))
  ((delete_mtime >= 0)) || delete_mtime=0
  while IFS= read -r -d '' file; do
    delete_archive "$file"
  done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.gz' -mtime "+${delete_mtime}" -print0 2>/dev/null)
fi

if ((archived == 0)); then
  printf '[INFO] No log files were old enough to archive.\n'
fi
if ((deleted == 0)); then
  printf '[INFO] No archive files were old enough to delete.\n'
fi
printf '[INFO] Retention complete: archived=%d deleted=%d\n' "$archived" "$deleted"
