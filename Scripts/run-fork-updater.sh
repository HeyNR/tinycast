#!/bin/bash
# The LaunchAgent entry point: one update at a time, with a readable last-run status.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
export PATH="$HOME/.volta/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

STATE="$HOME/Library/Application Support/Tinycast Fork Updater"
LOCK="$STATE/running"
STATUS="$STATE/last-run.txt"
mkdir -p "$STATE"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Another Tinycast fork update is already running."
    exit 0
fi
trap 'rmdir "$LOCK"' EXIT

started="$(date '+%Y-%m-%d %H:%M:%S %Z')"
feature_branch="${TINYCAST_FEATURE_BRANCH:-codex/window-snapping}"
if git switch "$feature_branch" && /usr/bin/caffeinate -i ./Scripts/update-fork.sh; then
    result="success"
    status=0
else
    status=$?
    result="failed"
fi
finished="$(date '+%Y-%m-%d %H:%M:%S %Z')"
temporary="$STATUS.tmp"
printf 'Result: %s\nStarted: %s\nFinished: %s\nExit status: %s\n' \
    "$result" "$started" "$finished" "$status" > "$temporary"
mv "$temporary" "$STATUS"
exit "$status"
