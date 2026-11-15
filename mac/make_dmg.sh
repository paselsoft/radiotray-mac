#!/bin/sh
# Impacchetta l'app in un .dmg (HFS+, UDZO: leggibile da macOS 10.13).
# Uso: sh mac/make_dmg.sh build/RadioTray.app build/RadioTray.dmg
set -eu
APP=$1
DMG=$2
HERE=$(cd "$(dirname "$0")" && pwd)
STAGE=$(dirname "$DMG")/dmg-stage
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applicazioni"
cp "$HERE/LEGGIMI.txt" "$STAGE/LEGGIMI.txt"
# hdiutil a volte fallisce con "Resource busy": si riprova
n=0
until hdiutil create -volname "RadioTray" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"; do
    n=$((n + 1))
    [ $n -ge 4 ] && { echo "hdiutil non riesce a creare il dmg" >&2; exit 1; }
    sleep $((n * 5))
done
rm -rf "$STAGE"
echo "Creato $DMG"
