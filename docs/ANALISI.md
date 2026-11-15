# Analisi di Radiotray-NG

Fonte analizzata: `ebruck/radiotray-ng` (ramo `master`, clone superficiale, sola lettura).
Linguaggio C++14, circa 10.700 righe, licenza GPL-3.0 (icone CC BY-ND 3.0).

## Che cosa fa

Lettore di radio via Internet che vive nell'area di notifica di Linux (AppIndicator).
Un clic sull'icona apre un menu con le stazioni divise in gruppi; si sceglie una stazione e parte.
Nessuna finestra principale.

## Architettura

```
main.cpp ─ crea i componenti e li collega
  ├─ Config        ~/.config/radiotray-ng/radiotray-ng.json (opzioni, volume, ultima stazione)
  ├─ Bookmarks     bookmarks.json: gruppi → stazioni {name, url, image?, notifications?, direct?}
  ├─ EventBus      eventi: state_changed, tags_changed, volume_changed, station_error, message
  ├─ Player        GStreamer (playbin3 + souphttpsrc), buffering, riavvio se lo stream si blocca
  ├─ PlaylistDownloader  libcurl: scarica i primi 4 KB e sceglie il decoder
  │     decoder: PLS, M3U/M3U8, ASX, XSPF, RAM, ASF, "DS"; altrimenti stream diretto
  ├─ RadiotrayNG   logica: play/stop, stazione successiva/precedente, volume, notifiche,
  │                divisione "Artista - Titolo", ricarica dei preferiti
  ├─ GUI           AppIndicator (GTK3) oppure ncurses (terminale)
  ├─ Notification  libnotify (su macOS: chiama `terminal-notifier` da riga di comando)
  ├─ MediaKeys     D-Bus GNOME (su macOS: vuoto)
  └─ rtng_dbus     interfaccia D-Bus per script esterni
rtng-bookmark-editor ─ editor dei preferiti separato (wxWidgets)
```

## Il menu (da `appindicator_gui.cpp`)

1. **Stato**: "Stopped" oppure titolo e artista del brano (a capo dopo 40 caratteri).
   Un clic copia titolo e artista negli appunti.
2. **Turn On "stazione" / Turn Off "stazione"**.
3. **Volume: N%** (con `tag-info-verbose`: bitrate e codec).
4. Separatore, poi i **gruppi come sottomenu** e le stazioni del gruppo `root` direttamente nel menu.
5. **Preferences** → Bookmark Editor…, Reload Bookmarks.
6. **Sleep Timer** (spunta; chiede i minuti, predefinito 30).
7. **About**, **Quit**.

La rotella del mouse sull'icona cambia il volume. Icona diversa da acceso a spento.

## Comportamenti da replicare

- **Formato `bookmarks.json`**: array di `{ "group": "...", "image": "...", "stations": [ {"name", "url", "image", "notifications", "direct"} ] }`.
  Il gruppo `root` non diventa un sottomenu. Lo manteniamo identico, così il file di Linux si copia così com'è.
- **Risoluzione dell'URL**: se finisce con un'estensione audio o `direct: true`, si suona direttamente.
  Altrimenti si scaricano al massimo 4 KB, si guardano Content-Type e contenuto e si sceglie il decoder.
  Se nessuno lo riconosce, è uno stream diretto. Si accetta la risposta `ICY 200 OK` dei vecchi server Shoutcast.
- **Metadati**: il titolo ICY `"Artista - Titolo"` viene diviso al primo `" - "`. Il trattino solo
  viene ignorato. C'è un'estrazione extra di `text="..."` per iHeartRadio.
- **Notifiche**: all'avvio della stazione (nome stazione), a ogni cambio di brano, senza ripetere lo stesso brano due volte.
  Si possono spegnere per stazione (`notifications: false`). Gli errori vengono mostrati sempre.
- **Ultima stazione** ricordata e riproposta in "Turn On".
- **Successiva/precedente** dentro il gruppo corrente (tasti multimediali).
- **Ricarica automatica** del file dei preferiti quando cambia (controllo ogni 10 s).
- **Volume** 0–200% a passi di 1, salvato nella configurazione.

## Perché non basta compilarlo su High Sierra

Il codice ha già qualche ramo `APPLE`, ma su macOS compila solo l'interfaccia **ncurses**
(nel terminale) e richiede GStreamer, Boost, jsoncpp e libcurl, presi da Homebrew.
Homebrew non supporta più 10.13 da anni: le dipendenze andrebbero compilate a mano, e il risultato
sarebbe comunque un programma da terminale, senza icona nella barra dei menu.
Notifiche e tasti multimediali per macOS sono vuoti o rimandano a strumenti esterni.

**Conclusione**: conviene riscrivere l'app in modo nativo, rispettando il comportamento e il formato
dei preferiti, invece di fare il porting del C++.
