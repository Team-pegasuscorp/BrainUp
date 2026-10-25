#!/bin/sh
## Nightly Postgres dump of the production base (installed by deploy/README.md, run by
## /etc/cron.d/brainup-backup). Custom format (-Fc): compressed, restored with pg_restore.
## The off-server copy is pulled by Yannick's PC (deploy/pull-backups.sh).
set -eu

## Overridable to try it on the local stack (see deploy/README.md).
ROOT="${BRAINUP_ROOT:-/opt/brainup}"
DIR="${BRAINUP_BACKUP_DIR:-$ROOT/backups}"
KEEP_DAYS=14
COMPOSE="${BRAINUP_COMPOSE:-docker compose -f $ROOT/docker-compose.prod.yml}"

mkdir -p "$DIR"
chmod 700 "$DIR"
STAMP=$(date -u +%Y-%m-%d_%H%M)
PART="$DIR/.brainup-$STAMP.dump.part"

cd "$ROOT"
$COMPOSE exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$PART"
## A dump that pg_restore cannot list is worthless: fail loudly instead of keeping it.
$COMPOSE exec -T postgres pg_restore --list < "$PART" > /dev/null
mv "$PART" "$DIR/brainup-$STAMP.dump"

find "$DIR" -name 'brainup-*.dump' -mtime +"$KEEP_DAYS" -delete
find "$DIR" -name '.brainup-*.part' -mmin +120 -delete
echo "$(date -u +%FT%TZ) ok brainup-$STAMP.dump $(du -h "$DIR/brainup-$STAMP.dump" | cut -f1)"
