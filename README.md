# RadioTray per Mac

Lettore di radio via Internet nella barra dei menu di macOS, ispirato a
[Radiotray-NG](https://github.com/ebruck/radiotray-ng) per Linux, pensato per un iMac 27" Late 2009
con **macOS High Sierra 10.13** (funziona anche sulle versioni successive).

![icona](docs/icona.png)

- [Analisi di Radiotray-NG](docs/ANALISI.md)
- [Piano di sviluppo](docs/PIANO.md)
- [Piano per Windows 10](docs/PIANO-WINDOWS.md): fase 1 nella cartella `windows/` (prova: `RadioTray-Windows.zip` nell'anteprima)

## Stato

| Fase | Contenuto | Stato |
|---|---|---|
| 1 | icona e menu, stazioni a gruppi (stesso `bookmarks.json` di Radiotray-NG), playlist PLS/M3U/ASX/XSPF, AVPlayer, titolo e artista, volume, ultima stazione, notifiche, `.dmg` dalla CI | fatta (provata sull'iMac) |
| 2 | titolo letto dallo stream (ICY), timer di spegnimento, stazione successiva/precedente, tasti multimediali, Apri URL…, ricarica automatica, riconnessione | fatta (provata sull'iMac) |
| 2.5 | nome vero della stazione, Aggiungi alle stazioni…, Cerca stazioni (Radio Browser), radio italiane consigliate | fatta (ricerca provata sull'iMac) |
| 3 | editor delle stazioni, avvio al login, versione 1.0 | fatta |
| 1.1 | brani preferiti: aggiunta dal menu, finestra con ricerca, filtro, ordinamento, ricerca sul web, esportazione CSV | fatta (provata sull'iMac) |
| 1.2 | ★ nelle notifiche, ascoltati di recente, scorciatoie ⌃⌥, rotella per il volume, avviso di nuova versione | fatta (provata sull'iMac) |
| 1.3 | copertine, radiosveglia, stazioni più ascoltate, titolo nella barra dei menu | fatta (provata sull'iMac) |
| 1.4 | finestra In riproduzione, backup e iCloud Drive, pausa automatica, qualità dello stream | fatta (provata sull'iMac) |
| 1.4.1 | titolo e artista al contrario (105 Classics), formato "Titolo * Artista" (RDS) | fatta |
| 1.4.2 | loghi delle stazioni, jingle ignorati, "Ignora i titoli" per stazione, radio http, volume in percentuale | fatta (provata sull'iMac) |
| 1.5.0 | copertine ufficiali RDS, verifica delle stazioni con proposta di indirizzi nuovi, loghi nel menu e nell'editor, logo da indirizzo web | fatta (provata sull'iMac) |
| 1.6.0 | ricerca nell'editor delle stazioni, importazione di playlist .pls e .m3u | fatta (provata sull'iMac) |
| 1.7.0 | "Cerca stazioni" riprova con sigle e nomi corti (RMC, RDS, Deejay…) | fatta (provata sull'iMac) |
| 1.8.0 | finestra "In riproduzione" aperta all'avvio (facoltativo) | fatta (provata sull'iMac) |
| 1.9.0 | server di riserva, riconnessione al cambio di rete, spegnimento graduale, ascolti segnalati a Radio Browser | fatta (provata sull'iMac) |
| 1.10.0 | https quando la radio lo offre, volume ricordato per ogni stazione, uscita audio dal menu | fatta (provata sull'iMac) |
| 1.11.0 | ListenBrainz, Cerca stazioni per genere e più ascoltate | fatta (provata sull'iMac) |
| 1.12.0 | titoli per Deejay, Capital, m2o e programma Rai, testi delle canzoni, programmi | fatta (provata sull'iMac) |
| 1.13.0 | icona nel Dock, finestre del testo e In riproduzione attaccate | fatta (provata sull'iMac) |
| 1.14.0 | Avvisami quando passa…, statistiche, condividi il brano | fatta (provata sull'iMac) |
| 1.14.1 | titoli di Radio Monte Carlo (https senza titoli) | fatta (provata sull'iMac) |
| 1.15.0 | link al palinsesto della radio, palinsesto personale con foto | fatta (provata sull'iMac) |
| 1.16.0 | Ogg Vorbis, Opus e FLAC con ffmpeg, titoli di Radio Paradise | fatta (provata sull'iMac) |

## Scaricare

La versione stabile è nella pagina [**Release**](../../releases/latest): scarica `RadioTray-x.y.z.dmg`.
Le istruzioni sono nel file `LEGGIMI.txt` dentro il `.dmg`. Al primo avvio: clic destro sull'app → Apri.

## Come si pubblica una versione

- `main` è il ramo principale: ogni push viene compilato e provato su GitHub Actions.
- I rami di sviluppo pubblicano il `.dmg` di prova nella release **anteprima**.
- Per una versione stabile: aggiornare `VERSION` nel `Makefile` e `docs/NOTE-VERSIONE.md`, poi
  in GitHub → Actions → build → **Run workflow** sul ramo `main` scrivere la versione (per esempio
  `1.0.1`), oppure creare l'etichetta `v1.0.1`. La CI crea l'etichetta, pubblica "RadioTray 1.0.1"
  e toglie l'anteprima.

## Compilare su un Mac

Servono gli strumenti a riga di comando di Xcode (`xcode-select --install`). Non servono altre dipendenze.

```sh
make test               # test della logica
make app                # build/RadioTray.app (x86_64, macOS 10.13)
make check-mac          # verifica architettura, versione minima, firma
make dmg                # build/RadioTray.dmg
make stations           # controlla che le stazioni predefinite rispondano
```

## Struttura

- `src/` Objective-C + Cocoa, nessuna libreria esterna:
  - `RTBookmarks`, `RTPlaylistParser`, `RTTrackInfo`: logica, solo Foundation (testata in `tests/`)
  - `RTStreamResolver`: scarica i primi 4 KB dell'URL e decide se è una playlist o uno stream
  - `RTPlayer`: AVPlayer, stato, titolo ICY, prova degli URL alternativi
  - `RTAppDelegate`: icona nella barra dei menu, menu, azioni, notifiche
- `resources/` Info.plist, icona, stazioni predefinite
- `mac/` script per bundle, verifica e `.dmg`
- `tools/make_icon.py` rigenera l'icona (Pillow)

Piano dei miglioramenti, fatti e da fare: [docs/PIANO-MIGLIORAMENTI.md](docs/PIANO-MIGLIORAMENTI.md)
