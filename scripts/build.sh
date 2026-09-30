#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/flodo-open-clang-cache"
swift build -c release --disable-sandbox
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o .build/AppIcon.icns
APP="dist/Flodo Open.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FlodoOpen "$APP/Contents/MacOS/FlodoOpen"
cp .build/release/flowctl "$APP/Contents/MacOS/flowctl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Keep the same designated requirement across updates so Keychain trust survives.
SIGNING_IDENTITY="${FLODO_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    IDENTITIES=$(security find-identity -v -p codesigning | sed -nE '/"Apple (Development|Distribution):/s/^[[:space:]]*[0-9]+\) ([A-F0-9]+).*/\1/p')
    if [[ $(printf '%s\n' "$IDENTITIES" | awk 'NF { n++ } END { print n+0 }') == 1 ]]; then
        SIGNING_IDENTITY="$IDENTITIES"
    else
        SIGNING_IDENTITY="-"
        printf '%s\n' 'No unambiguous signing identity. Set FLODO_SIGNING_IDENTITY for stable Keychain access across builds.' >&2
    fi
fi
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$PWD/$APP"
