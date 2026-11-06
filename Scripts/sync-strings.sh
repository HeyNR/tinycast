#!/bin/bash
# Merge the strings the compiler extracted into Localizable.xcstrings, as an Xcode build in the IDE
# does; `xcodebuild` alone never writes them back. Run after changing any UI text.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

DERIVED=build/strings
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
remove_build_products() {
    local app="$DERIVED/Build/Products/Debug/Tinycast Dev.app"
    local helper="$DERIVED/Build/Products/Debug/Tinycast Dev Dictation.app"
    "$LSREGISTER" -u "$app/Contents/Helpers/Tinycast Dev Dictation.app" \
        >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$helper" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
    rm -rf "$app" "$helper"
}
trap remove_build_products EXIT

xcodebuild build -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
    CODE_SIGNING_ALLOWED=NO -derivedDataPath "$DERIVED" -quiet

# A read loop rather than `mapfile`, which is bash 4 — macOS ships bash 3.2.
args=()
while IFS= read -r f; do args+=(--stringsdata "$f"); done < <(
    find "$DERIVED/Build/Intermediates.noindex/Tinycast.build/Debug/Tinycast.build" \
        -name '*.stringsdata'
)
# The catalog's file name is its table, so only `Localizable` strings land in it.
xcrun xcstringstool sync Tinycast/Resources/Localizable.xcstrings "${args[@]}"

node Scripts/check-localizations.js
