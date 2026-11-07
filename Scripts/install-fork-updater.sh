#!/bin/bash
# Install or remove the per-user LaunchAgent that maintains this fork.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

LABEL="com.tinycast.fork-updater"
DOMAIN="gui/$(id -u)"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
TEMPLATE="Scripts/$LABEL.plist"

if [ "${1:-}" = "--uninstall" ]; then
    launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    rm -f "$AGENT"
    echo "✓ Removed the Tinycast fork updater."
    exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
temporary="$(mktemp "${TMPDIR:-/tmp}/tinycast-fork-updater.XXXXXX.plist")"
trap 'rm -f "$temporary"' EXIT
cp "$TEMPLATE" "$temporary"
plutil -replace ProgramArguments.0 -string "$PWD/Scripts/run-fork-updater.sh" "$temporary"
plutil -replace WorkingDirectory -string "$PWD" "$temporary"
plutil -replace StandardOutPath -string \
    "$HOME/Library/Logs/Tinycast Fork Updater.log" "$temporary"
plutil -replace StandardErrorPath -string \
    "$HOME/Library/Logs/Tinycast Fork Updater.error.log" "$temporary"
plutil -lint "$temporary" >/dev/null

launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
install -m 0644 "$temporary" "$AGENT"
launchctl bootstrap "$DOMAIN" "$AGENT"
launchctl enable "$DOMAIN/$LABEL"
launchctl kickstart "$DOMAIN/$LABEL"
echo "✓ Installed the Tinycast fork updater; it runs now and every six hours."
