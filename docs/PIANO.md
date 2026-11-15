# Piano: RadioTray per macOS 10.13 (iMac 27" Late 2009)

## Vincoli della macchina

- Intel Core 2 Duo / i5-i7 a 64 bit, macOS **High Sierra 10.13**, niente Metal moderno: è un'app
  per la barra dei menu, quindi la grafica non conta.
- Homebrew non supporta più 10.13, quindi **zero dipendenze esterne**: solo framework di sistema.
- Swift prima di 10.14.4 richiede di incorporare le sue librerie nell'app (fragile con gli Xcode
  recenti). Scegliamo **Objective-C + Cocoa**, la stessa strada già provata con Zuma
  (`platform_mac.m`, build in CI con target 10.13).

## Scelte tecniche

| Funzione di Radiotray-NG | Su macOS 10.13 |
|---|---|
| Icona AppIndicator + menu GTK | `NSStatusItem` + `NSMenu`, icona "template" (si adatta al tema scuro) |
| GStreamer | `AVPlayer` (AVFoundation): MP3, AAC/HE-AAC, HLS. **Non** Ogg/Opus né WMA/ASF |
| Metadati GStreamer | `AVPlayerItem.timedMetadata` (titolo ICY `StreamTitle`) |
| libcurl + decoder playlist | `NSURLSession` (primi 4 KB) + parser PLS, M3U, ASX, XSPF scritti da noi |
| libnotify | `NSUserNotificationCenter` (disponibile su 10.13) |
| Tasti multimediali | `MPRemoteCommandCenter` (10.12.2+, collegato in modo debole). Su 10.13 non è garantito che F7–F9 arrivino all'app |
| Config JSON | `NSUserDefaults` |
| `bookmarks.json` | **stesso formato**, in `~/Library/Application Support/RadioTray/` |
| Controllo modifiche ogni 10 s | `dispatch_source` sul file (ricarica immediata) |
| Rotella sull'icona | cursore del volume dentro il menu |
| Editor wxWidgets | fase 1: "Modifica stazioni…" apre il JSON in TextEdit. Fase 3: piccolo editor nativo |
| D-Bus | non serve (eventualmente AppleScript più avanti) |

Accorgimenti specifici:
- `Info.plist` con `LSUIElement` (niente icona nel Dock), `LSMinimumSystemVersion` 10.13
  e `NSAllowsArbitraryLoads` (molte radio sono ancora in `http://`).
- Firma ad-hoc. Al primo avvio: clic destro → Apri, per Gatekeeper.
- Interfaccia in italiano.

## Menu previsto

```
♪ Titolo del brano
  Artista                     (clic: copia negli appunti)
Accendi «Radio X» / Spegni «Radio X»
Volume  [━━━━━━●───] 70%
───────────────
Gruppo 1                     ▸ stazioni
Gruppo 2                     ▸ stazioni
Stazione senza gruppo (root)
───────────────
Stazione precedente / successiva
Apri URL…
Timer di spegnimento…        ✓
Preferenze                   ▸ Modifica stazioni…, Ricarica stazioni, Mostra nel Finder,
                               Notifiche ✓, Notifiche dettagliate
Informazioni su RadioTray
Esci                        ⌘Q
```

## Struttura del repository

```
src/        main.m, AppDelegate, RTPlayer (AVPlayer), RTStreamResolver (NSURLSession),
            RTPlaylistParser, RTTrackInfo, RTBookmarks   ← questi tre solo Foundation, testabili
            RTMenuController, RTNotifier, RTSettings
resources/  Info.plist, bookmarks.json predefinito, icona .icns, Credits.rtf
tests/      test della logica (parser playlist, divisione titolo, lettura preferiti)
mac/        make_bundle.sh, make_dmg.sh, check_binaries.sh (come Zuma)
.github/workflows/build.yml   runner macOS: x86_64, target 10.13, test, .dmg come artifact/release
```

## Fasi

1. **Base funzionante**: icona e menu, preferiti, risoluzione delle playlist, riproduzione AVPlayer,
   titolo e artista, volume, ultima stazione, notifiche, build in CI con `.dmg`. → prova sull'iMac.
2. **Completezza**: timer di spegnimento, stazione successiva/precedente, tasti multimediali,
   Apri URL…, ricarica automatica, riconnessione se lo stream cade, icona nello stato di
   connessione.
3. **Comodità**: editor delle stazioni nativo, importazione dei preferiti di Radiotray-NG/RadioTray
   (XML), avvio al login, titolo nella barra (opzionale).

## Limiti noti

- Le stazioni **Ogg Vorbis/Opus** o **WMA** non si possono riprodurre con AVPlayer. Quasi tutte
  hanno anche un flusso MP3/AAC: si sostituisce l'URL.
- I server Shoutcast v1 che rispondono `ICY 200 OK` potrebbero non funzionare con AVPlayer.
  Da verificare sull'iMac. Il ripiego è un piccolo proxy locale.
- I tasti multimediali della tastiera Apple su 10.13 potrebbero continuare ad aprire iTunes.
- Licenza: Radiotray-NG è GPL-3.0. Qui il codice viene riscritto da zero, senza copiarlo. Il formato dei
  preferiti è solo un formato dati. Per coerenza si può comunque pubblicare questo progetto sotto GPL-3.0.
