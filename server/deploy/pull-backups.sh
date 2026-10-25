#!/bin/sh
## Off-server copy of the production dumps, run on Yannick's PC by a systemd user timer
## (deploy/systemd/). Pulls from the server, then mirrors to Google Drive. No Google
## credentials ever sit on the server.
set -eu

LOCAL="${BRAINUP_BACKUP_DIR:-/mnt/jeux/backups/brainup}"
REMOTE="brainup-hetzner:/opt/brainup/backups/"
DRIVE="gdrive:BrainUp/backups"
KEEP_DAYS=60

mkdir -p "$LOCAL"
rsync -a --include 'brainup-*.dump' --exclude '*' "$REMOTE" "$LOCAL/"
find "$LOCAL" -name 'brainup-*.dump' -mtime +"$KEEP_DAYS" -delete
rclone sync "$LOCAL" "$DRIVE" --include 'brainup-*.dump'

LATEST=$(ls -1 "$LOCAL"/brainup-*.dump 2>/dev/null | tail -n 1)
echo "$(date +%FT%T) ok latest=$(basename "${LATEST:-none}")"
