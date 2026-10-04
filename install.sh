#!/usr/bin/env bash
# Installs the sync daemon for the current user. Safe to re-run (never overwrites your config.env).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
command -v rclone >/dev/null || { echo "rclone not found"; exit 1; }

install -d ~/.local/bin ~/.config/gdrive-sync ~/.config/systemd/user
install -m 755 "$HERE/gdrive-sync.sh" ~/.local/bin/gdrive-sync.sh
install -m 644 "$HERE/filter.txt" ~/.config/gdrive-sync/filter.txt
[ -f ~/.config/gdrive-sync/config.env ] || install -m 644 "$HERE/config.env.example" ~/.config/gdrive-sync/config.env
install -m 644 "$HERE"/systemd/gdrive-sync.{service,timer} ~/.config/systemd/user/

# shellcheck disable=SC1090
source ~/.config/gdrive-sync/config.env
remote_name="${REMOTE%%[:,]*}"   # handles "remote:path" and "remote,root_folder_id=ID:"
rclone listremotes | grep -qx "$remote_name:" || { echo "rclone remote '$remote_name' not configured. Run: rclone config"; exit 1; }

# First run only: build bisync listings (copies in both directions, never deletes).
if ! ls ~/.cache/rclone/bisync/*.lst >/dev/null 2>&1; then
  echo "First run: initial --resync (copy-only merge)"
  rclone bisync "$LOCAL_DIR" "$REMOTE" --resync --filters-file ~/.config/gdrive-sync/filter.txt \
    --create-empty-src-dirs --drive-skip-gdocs
fi

systemctl --user daemon-reload
systemctl --user enable --now gdrive-sync.timer
# Start at boot without needing a login session:
loginctl enable-linger "$USER" || echo "WARN: could not enable linger; run: sudo loginctl enable-linger $USER"
systemctl --user list-timers gdrive-sync.timer --no-pager
