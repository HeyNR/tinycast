#!/bin/bash
# Install or remove the per-user LaunchAgent that maintains this fork.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

LABEL="com.tinycast.fork-updater"
DOMAIN="gui/$(id -u)"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
TEMPLATE="Scripts/$LABEL.plist"
FEATURE_BRANCH="${TINYCAST_FEATURE_BRANCH:-codex/window-snapping}"
STATE="$HOME/Library/Application Support/Tinycast Fork Updater"
REPOSITORY="$STATE/repository"

if [ "${1:-}" = "--uninstall" ]; then
    launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    rm -f "$AGENT"
    echo "✓ Removed the Tinycast fork updater."
    exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
mkdir -p "$STATE"
origin_url="$(git remote get-url origin)"
upstream_url="$(git remote get-url upstream)"
if [ -d "$REPOSITORY/.git" ]; then
    if [ -n "$(git -C "$REPOSITORY" status --porcelain)" ]; then
        echo "✗ The updater repository is dirty: $REPOSITORY" >&2
        exit 1
    fi
    git -C "$REPOSITORY" fetch origin main "$FEATURE_BRANCH"
    git -C "$REPOSITORY" switch "$FEATURE_BRANCH"
    git -C "$REPOSITORY" merge --ff-only "origin/$FEATURE_BRANCH"
else
    git clone --branch "$FEATURE_BRANCH" "$origin_url" "$REPOSITORY"
fi
if git -C "$REPOSITORY" remote get-url upstream >/dev/null 2>&1; then
    git -C "$REPOSITORY" remote set-url upstream "$upstream_url"
else
    git -C "$REPOSITORY" remote add upstream "$upstream_url"
fi
if ! git -C "$REPOSITORY" show-ref --verify --quiet refs/heads/main; then
    git -C "$REPOSITORY" branch --track main origin/main
fi

temporary="$(mktemp "${TMPDIR:-/tmp}/tinycast-fork-updater.XXXXXX.plist")"
trap 'rm -f "$temporary"' EXIT
cp "$TEMPLATE" "$temporary"
plutil -replace ProgramArguments.0 -string \
    "$REPOSITORY/Scripts/run-fork-updater.sh" "$temporary"
plutil -replace WorkingDirectory -string "$REPOSITORY" "$temporary"
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
