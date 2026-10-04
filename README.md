# gdrive-sync-daemon

Unattended two-way sync between a local folder and a Google Drive folder using
[`rclone bisync`](https://rclone.org/bisync/), run by a systemd **user** timer.

## Reliability features
- Starts at boot (`enable-linger`) and every 2 min after the previous run finishes (no overlap).
- Single instance via `flock`; 30 min run timeout; low CPU/IO priority.
- Offline = quiet skip, not a failure. Refuses to run if the local dir is missing (unmounted disk).
- Self-heals the "bisync needs --resync" state (copy-only, never deletes).
- Safety abort if a run would delete more than `MAX_DELETE` files.
- Conflicts: newer file wins, the loser is kept with a numeric suffix.
- Desktop notification after N consecutive failures.

## Setup
1. Create an rclone remote for Drive: `rclone config` (use your own OAuth client ID and **publish the
   consent screen to "In production"**, otherwise refresh tokens expire after 7 days).
   Credentials live only in `~/.config/rclone/rclone.conf`, which is **not** part of this repo.
2. `./install.sh`, then edit `~/.config/gdrive-sync/config.env` if needed (`LOCAL_DIR`, `REMOTE`).

## Operate
- Status: `systemctl --user list-timers gdrive-sync.timer`
- Logs: `journalctl --user -u gdrive-sync.service -e`
- Sync now: `systemctl --user start gdrive-sync.service`
- Pause: `systemctl --user disable --now gdrive-sync.timer`
- Remove: `./uninstall.sh`
