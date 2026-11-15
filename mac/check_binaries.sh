#!/bin/sh
# Verifica che l'eseguibile sia solo ARCH, con versione minima MIN, senza librerie esterne
# al sistema, e che firma e Info.plist siano validi.
# Uso: sh mac/check_binaries.sh build/RadioTray.app x86_64 10.13
set -eu
APP=$1
ARCH=$2
MIN=$3
BIN="$APP/Contents/MacOS/RadioTray"
fail=0
archs=$(lipo -info "$BIN" | sed "s/.*: //")
minv=$(otool -l "$BIN" | awk '/LC_VERSION_MIN_MACOSX/{m=1} /LC_BUILD_VERSION/{b=1} m&&$1=="version"{print $2; exit} b&&$1=="minos"{print $2; exit}')
echo "RadioTray: arch=[$archs] min=$minv"
[ "$archs" = "$ARCH" ] || { echo "ERRORE: architettura diversa da $ARCH"; fail=1; }
[ "$minv" = "$MIN" ] || { echo "ERRORE: versione minima diversa da $MIN"; fail=1; }
echo "Dipendenze:"
otool -L "$BIN" | awk 'NR>1 {print "  " $1}'
for dep in $(otool -L "$BIN" | awk 'NR>1 {print $1}'); do
    case "$dep" in
        /usr/lib/*|/System/Library/Frameworks/*) ;;
        *) echo "ERRORE: dipendenza esterna $dep"; fail=1 ;;
    esac
done
# simboli che su 10.13 non esistono: nessun riferimento a Swift o a framework più recenti
if otool -L "$BIN" | grep -q -i swift; then echo "ERRORE: dipende da Swift"; fail=1; fi
codesign --verify --deep --strict --verbose=2 "$APP" || fail=1
plutil -lint "$APP/Contents/Info.plist" || fail=1
[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")" = "$MIN" ] || { echo "ERRORE: LSMinimumSystemVersion"; fail=1; }
[ $fail -eq 0 ] && echo "Verifica superata" || { echo "Verifica FALLITA"; exit 1; }
