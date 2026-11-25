#!/bin/sh
# Crea RadioTray.app: eseguibile, Info.plist, icona, stazioni predefinite, firma ad-hoc.
# Uso: VERSION=0.1.0 sh mac/make_bundle.sh build/RadioTray.app build/RadioTray
set -eu
APP=$1
BIN=$2
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${VERSION:-0.1.0}
BUILDNO=$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RadioTray"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILDNO/" "$ROOT/resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ROOT/resources/RadioTray.icns" "$ROOT/resources/bookmarks.json" "$ROOT/resources/stazioni-italiane.json" "$ROOT/resources/Credits.rtf" "$ROOT/resources/telecomando.html" "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Creato $APP"
