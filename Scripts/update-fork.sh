#!/bin/bash
# Rebase the private feature branch onto upstream, verify it, install it and publish it.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

FEATURE_BRANCH="${TINYCAST_FEATURE_BRANCH:-codex/window-snapping}"
OFFICIAL_REPOSITORY="abue-ammar/tinycast"
FORK_REPOSITORY="HeyNR/tinycast"

if [ "$(git branch --show-current)" != "$FEATURE_BRANCH" ]; then
    echo "✗ Run this from $FEATURE_BRANCH." >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "✗ Commit or stash every change before updating." >&2
    exit 1
fi
case "$(git remote get-url upstream)" in
    *"$OFFICIAL_REPOSITORY"*) ;;
    *) echo "✗ upstream does not point to $OFFICIAL_REPOSITORY." >&2; exit 1 ;;
esac
case "$(git remote get-url origin)" in
    *"$FORK_REPOSITORY"*) ;;
    *) echo "✗ origin does not point to $FORK_REPOSITORY." >&2; exit 1 ;;
esac

echo "▸ Updating the pristine main branch…"
git fetch upstream main
git switch main
git merge --ff-only upstream/main
git push origin main

echo "▸ Rebasing $FEATURE_BRANCH…"
git switch "$FEATURE_BRANCH"
git rebase main

echo "▸ Verifying the rebased fork…"
./Scripts/run-tests.sh
./Scripts/lint.sh
if grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/; then
    echo "✗ A pure model imports a UI framework." >&2
    exit 1
fi

./Scripts/install-dev.sh
git push --force-with-lease origin "$FEATURE_BRANCH"
echo "✓ $FEATURE_BRANCH is current, verified, installed and published."
