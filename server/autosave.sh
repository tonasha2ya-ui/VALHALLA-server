#!/bin/bash

set -euo pipefail

cd /workspaces/VALHALLA-server/server || exit

BACKUP_DIR="$PWD/backups/auto"
mkdir -p "$BACKUP_DIR"
MAX_BACKUPS=10

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')

    # Create a compressed snapshot (exclude backups and .git)
    tar --exclude='./backups' --exclude='./.git' -czf "$BACKUP_DIR/server_backup_$TIMESTAMP.tar.gz" .

    # Rotate old backups, keep the most recent $MAX_BACKUPS
    (cd "$BACKUP_DIR" && ls -1t | sed -e "1,${MAX_BACKUPS}d" | xargs -r rm --)

    # Commit changes locally only (no push)
    git add .
    if ! git diff --cached --quiet; then
        git commit -m "Auto Save $TIMESTAMP"
        echo "Committed locally: $TIMESTAMP"
        # Push commits to remote so backups and changes are stored off-host
        git push origin main || echo "git push failed: see CI/credentials"
    else
        echo "No changes to commit: $TIMESTAMP"
    fi

    echo "Backup created: $BACKUP_DIR/server_backup_$TIMESTAMP.tar.gz"
    sleep 1800
done
