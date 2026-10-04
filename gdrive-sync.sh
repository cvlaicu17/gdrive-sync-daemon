#!/usr/bin/env bash
# Two-way rclone bisync between LOCAL_DIR and REMOTE. Designed to be run by a systemd timer.
# Exit 0 on success or "nothing to do" (offline); non-zero only on real failures.
set -uo pipefail

CONF="${GDRIVE_SYNC_CONFIG:-$HOME/.config/gdrive-sync/config.env}"
FILTER="${GDRIVE_SYNC_FILTER:-$HOME/.config/gdrive-sync/filter.txt}"
STATE="$HOME/.local/state/gdrive-sync"
mkdir -p "$STATE"
# shellcheck disable=SC1090
source "$CONF"
: "${LOCAL_DIR:?}" "${REMOTE:?}"
MAX_DELETE="${MAX_DELETE:-25}"
NOTIFY_AFTER_FAILURES="${NOTIFY_AFTER_FAILURES:-5}"

log() { echo "[$(date '+%F %T')] $*"; }

# Only one instance at a time.
exec 9>"$STATE/lock"
flock -n 9 || { log "previous run still active, skipping"; exit 0; }

# Skip quietly when offline; this is not a failure.
if ! curl -fsS -o /dev/null --max-time 10 https://www.googleapis.com/generate_204 2>/dev/null; then
  log "offline, skipping"
  exit 0
fi

# Refuse to run if the local dir vanished (e.g. unmounted disk); bisync would see "everything deleted".
if [ ! -d "$LOCAL_DIR" ]; then
  log "ERROR: $LOCAL_DIR does not exist, refusing to sync"
  exit 1
fi

COMMON=(--filters-file "$FILTER" --create-empty-src-dirs --drive-skip-gdocs
        --resilient --recover --conflict-resolve newer --conflict-loser num
        --max-delete "$MAX_DELETE" --retries 3 --low-level-retries 10 --log-level NOTICE)

run_bisync() { rclone bisync "$LOCAL_DIR" "$REMOTE" "${COMMON[@]}" "$@" 2>&1 | tee "$STATE/last.log"; return "${PIPESTATUS[0]}"; }

run_bisync; rc=$?

if [ $rc -ne 0 ]; then
  if grep -qiE "must run --resync|prior (path1|path2) listing.*not found|Bisync critical error" "$STATE/last.log"; then
    # Listings are missing/corrupt. --resync only copies (never deletes) so it is safe to self-heal.
    log "bisync needs --resync, recovering"
    run_bisync --resync --resync-mode newer; rc=$?
  elif grep -qiE "too many deletes|max-delete" "$STATE/last.log"; then
    log "SAFETY ABORT: sync would delete more than $MAX_DELETE files. Inspect, then run: systemctl --user start gdrive-sync.service"
  fi
fi

fails_file="$STATE/consecutive_failures"
if [ $rc -eq 0 ]; then
  log "sync ok"
  echo 0 > "$fails_file"
  exit 0
fi

n=$(( $(cat "$fails_file" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$fails_file"
log "sync FAILED (rc=$rc, consecutive failures: $n)"
if [ "$n" -eq "$NOTIFY_AFTER_FAILURES" ] && command -v notify-send >/dev/null; then
  notify-send -u critical "gdrive-sync" "Sync has failed $n times in a row. See: journalctl --user -u gdrive-sync" || true
fi
exit "$rc"
