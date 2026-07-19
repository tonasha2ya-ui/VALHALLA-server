#!/bin/bash

set -euo pipefail

cd /workspaces/VALHALLA-server/server || exit

LOG_FILE="$PWD/autosave.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

INTERVAL=1800

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
    SENT_SAVE=false

    # Improved detection for Minecraft server (Forge 1.20.1 and others)
    # Patterns to match in java command line
    JAVA_PATTERN='forge|neoforge|minecraft_server|run.sh|libraries/net/minecraftforge|@libraries|nogui'

    JAVA_MATCHES=$(pgrep -a java 2>/dev/null || true)
    MATCHED_PIDS=$(echo "$JAVA_MATCHES" | grep -Ei "$JAVA_PATTERN" | awk '{print $1}' || true)

    # helper: walk parent chain and return first ancestor pid matching name
    find_ancestor_by_name() {
        pid=$1
        name=$2
        while [ "$pid" -ne 1 ] 2>/dev/null; do
            pcmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null || true)
            if echo "$pcmd" | grep -qi "$name"; then
                echo "$pid"
                return 0
            fi
            pid=$(awk '{print $4}' /proc/$pid/stat 2>/dev/null || echo 1)
        done
        return 1
    }

    # attempt to map java process to tmux pane by matching tty
    if [ -n "$MATCHED_PIDS" ]; then
        for pid in $MATCHED_PIDS; do
            # get TTY of the java process (e.g., pts/2)
            TTY=$(ps -p "$pid" -o tty= 2>/dev/null | tr -d ' ' || true)
            if [ -n "$TTY" ] && [ "$TTY" != "?" ]; then
                TTY_PATH="/dev/$TTY"
            else
                TTY_PATH=""
            fi

            # Try tmux: match pane TTY to process TTY
            if command -v tmux >/dev/null 2>&1; then
                tmux list-panes -a -F "#{session_name}:#{pane_tty}" 2>/dev/null | while IFS=: read -r session pane_tty; do
                    if [ -n "$pane_tty" ] && [ -n "$TTY_PATH" ] && [ "$pane_tty" = "$TTY_PATH" ]; then
                        tmux send-keys -t "$session" "save-all" C-m
                        log "Sent save-all to tmux session: $session (matched pid $pid tty $TTY_PATH)"
                        SENT_SAVE=true
                    fi
                done
            fi

            # Try screen: check ancestor chain for screen and map via screen -ls
            if [ "$SENT_SAVE" = false ] && command -v screen >/dev/null 2>&1; then
                # if an ancestor is 'screen' get list of screen sessions and try to pick one
                SCR_ANCESTOR=$(find_ancestor_by_name "$pid" screen || true)
                if [ -n "$SCR_ANCESTOR" ]; then
                    # pick the first screen session (best-effort) and send save-all
                    SCREEN_SESSION_LINE=$(screen -ls 2>/dev/null | grep -E '\.[^\t ]+' | head -n1 || true)
                    SCREEN_NAME=$(echo "$SCREEN_SESSION_LINE" | awk -F. '{print $2}' | awk '{print $1}' || true)
                    if [ -n "$SCREEN_NAME" ]; then
                        screen -S "$SCREEN_NAME" -p 0 -X stuff $'save-all\n' 2>/dev/null || true
                        log "Sent save-all to screen session: $SCREEN_NAME (matched pid $pid)"
                        SENT_SAVE=true
                    fi
                fi
            fi
        done
    fi

    if [ "$SENT_SAVE" = false ]; then
        if [ -n "$MATCHED_PIDS" ]; then
            log "Minecraft java process(es) detected but no tmux/screen session mapped; PID(s):"
            echo "$JAVA_MATCHES" | grep -Ei "$JAVA_PATTERN" | sed 's/^/    /' | tee -a "$LOG_FILE"
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
