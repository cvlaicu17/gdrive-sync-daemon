#!/usr/bin/env bash
set -euo pipefail
systemctl --user disable --now gdrive-sync.timer 2>/dev/null || true
rm -f ~/.config/systemd/user/gdrive-sync.{service,timer} ~/.local/bin/gdrive-sync.sh
systemctl --user daemon-reload
echo "Removed. Config kept in ~/.config/gdrive-sync (delete manually if wanted)."
