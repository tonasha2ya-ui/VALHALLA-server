#!/bin/bash

set -euo pipefail

cd /workspaces/VALHALLA-server/server || exit

BACKUP_DIR="$PWD/backups/auto"
mkdir -p "$BACKUP_DIR"
MAX_BACKUPS=10

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')

    # If the Minecraft server is running in tmux or screen, request a save to flush world to disk
    if command -v tmux >/dev/null 2>&1; then
        TMUX_SESSIONS=$(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)
        TARGET_SESSION=$(echo "$TMUX_SESSIONS" | grep -E 'minecraft|mc|server' | head -n1 || true)
        if [ -n "$TARGET_SESSION" ]; then
            tmux send-keys -t "$TARGET_SESSION" "save-all" C-m
            sleep 3
        fi
    fi
    if command -v screen >/dev/null 2>&1; then
        SCREEN_SESSION=$(screen -ls 2>/dev/null | grep -E 'minecraft|mc|server' | awk '{print $1}' | head -n1 || true)
        if [ -n "$SCREEN_SESSION" ]; then
            screen -S "$SCREEN_SESSION" -p 0 -X stuff $'save-all\n'
            sleep 3
        fi
    fi

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
