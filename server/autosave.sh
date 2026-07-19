#!/bin/bash

cd /workspaces/VALHALLA-server/server || exit

while true
do
    git add .

    if ! git diff --cached --quiet; then
        git commit -m "Auto Save $(date '+%Y-%m-%d %H:%M:%S')"
        git push origin main
        echo "Saved: $(date)"
    else
        echo "No changes: $(date)"
    fi

    sleep 1800
done
