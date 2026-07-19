#!/bin/bash

set -euo pipefail

cd /workspaces/VALHALLA-server/server || exit

LOG_FILE="$PWD/autosave.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

INTERVAL=1800

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
    SENT_SAVE=false

    # Detect tmux session running the server and send save-all
    if command -v tmux >/dev/null 2>&1; then
        TMUX_SESSIONS=$(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)
        TARGET_SESSION=$(echo "$TMUX_SESSIONS" | grep -E 'minecraft|mc|server' | head -n1 || true)
        if [ -n "$TARGET_SESSION" ]; then
            tmux send-keys -t "$TARGET_SESSION" "save-all" C-m
            log "Sent save-all to tmux session: $TARGET_SESSION"
            SENT_SAVE=true
            sleep 3
        fi
    fi

    # Detect screen session running the server and send save-all
    if command -v screen >/dev/null 2>&1; then
        SCREEN_SESSION=$(screen -ls 2>/dev/null | grep -E 'minecraft|mc|server' | awk '{print $1}' | head -n1 || true)
        if [ -n "$SCREEN_SESSION" ]; then
            screen -S "$SCREEN_SESSION" -p 0 -X stuff $'save-all\n'
            log "Sent save-all to screen session: $SCREEN_SESSION"
            SENT_SAVE=true
            sleep 3
        fi
    fi

    if [ "$SENT_SAVE" = false ]; then
        # Check for a java process that looks like a Minecraft server
        JAVA_PROCS=$(pgrep -a java 2>/dev/null || true)
        if echo "$JAVA_PROCS" | grep -Ei 'minecraft|paper|spigot|bukkit|forge|server.jar|fabric' >/dev/null 2>&1; then
            log "Minecraft java process detected but not running under tmux/screen. Cannot send save-all automatically. PID(s):"
            echo "$JAVA_PROCS" | sed 's/^/    /' | tee -a "$LOG_FILE"
        else
            log "No Minecraft server process detected; skipped save-all."
        fi
    fi

    # Proceed with git snapshot: add, commit, push
    git add .
    if ! git diff --cached --quiet; then
        git commit -m "Auto Save $TIMESTAMP"
        log "Committed changes: $TIMESTAMP"
        git push origin main || log "git push failed: check remote/credentials"
    else
        log "No changes to commit: $TIMESTAMP"
    fi

    sleep "$INTERVAL"
done
