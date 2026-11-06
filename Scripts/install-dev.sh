#!/bin/bash
# Build, verify and atomically install the persistent local development channel.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

IDENTITY="Tinycast Self-Signed"
DERIVED="build/DerivedData"
APP="$DERIVED/Build/Products/Debug/Tinycast Dev.app"
DESTINATION="/Applications/Tinycast Dev.app"
STAGING="/Applications/.Tinycast Dev.app.installing"
BACKUP="/Applications/.Tinycast Dev.app.previous"
EXECUTABLE="$DESTINATION/Contents/MacOS/Tinycast Dev"

if ! security find-identity -p codesigning | grep -Fq "\"$IDENTITY\""; then
    echo "✗ '$IDENTITY' code-signing identity not found — follow docs/signing.md §1." >&2
    exit 1
fi

echo "▸ Building signed Tinycast Dev.app…"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    build

[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" \
    = "com.tinycast.app.dev" ] || {
    echo "✗ Built app has the wrong bundle identifier." >&2
    exit 1
}

SIGNATURE="$(codesign -dv --verbose=2 "$APP" 2>&1)"
grep -Fq "Authority=$IDENTITY" <<< "$SIGNATURE" || {
    echo "✗ Built app is not signed by '$IDENTITY'." >&2
    exit 1
}
codesign --verify --deep --strict "$APP"

rm -rf "$STAGING" "$BACKUP"
ditto "$APP" "$STAGING"
codesign --verify --deep --strict "$STAGING"

pkill -f "$EXECUTABLE" 2>/dev/null || true
if [ -e "$DESTINATION" ]; then
    mv "$DESTINATION" "$BACKUP"
fi
mv "$STAGING" "$DESTINATION"

rollback() {
    echo "✗ The new build did not launch; restoring the previous app." >&2
    rm -rf "$DESTINATION"
    if [ -e "$BACKUP" ]; then
        mv "$BACKUP" "$DESTINATION"
        open "$DESTINATION"
    fi
    exit 1
}

open "$DESTINATION" || rollback
LAUNCHED=false
for _ in {1..20}; do
    if pgrep -f "$EXECUTABLE" >/dev/null; then
        LAUNCHED=true
        break
    fi
    sleep 0.25
done
[ "$LAUNCHED" = true ] || rollback

rm -rf "$BACKUP"
echo "✓ Installed and launched $DESTINATION"
