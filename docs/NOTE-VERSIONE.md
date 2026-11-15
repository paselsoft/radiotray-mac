Lettore di radio via Internet nella barra dei menu per **macOS 10.13 High Sierra** e successivi
(Intel 64 bit; provato su iMac 27" Late 2009), ispirato a Radiotray-NG per Linux.

**Installazione:** apri `RadioTray-….dmg`, trascina RadioTray in Applicazioni, poi la prima volta
clic destro sull'app → Apri → Apri. Istruzioni complete nel file LEGGIMI.txt dentro il .dmg.

### Novità della 1.4
- **Finestra "In riproduzione"**: copertina grande, ◀︎ ⏯ ▶︎ ★, volume, sempre in primo piano
- **Backup**: esporta/importa tutto in un file (unisci o sostituisci) e copia giornaliera su iCloud Drive
- **Pausa automatica** quando blocchi lo schermo o stacchi le cuffie, con ripresa al ritorno
- **Qualità dello stream** nel menu: formato e bitrate

### Novità della 1.3
- **Copertine degli album** nella notifica, nel menu e nei brani preferiti (catalogo pubblico di Apple)
- **Radiosveglia**: ora, giorni della settimana, stazione, volume crescente
- **Più ascoltate**: le 5 stazioni che ascolti di più in cima al menu
- **Titolo nella barra dei menu** accanto all'icona (facoltativo, da Preferenze)

### Novità della 1.2
- **★ Preferito nelle notifiche** del cambio di brano (sempre visibile con lo stile "Avvisi")
- **Ascoltati di recente**: gli ultimi brani nel menu, un clic per aggiungerli ai preferiti
- **Scorciatoie da tastiera** in qualsiasi app: ⌃⌥P accendi/spegni, ⌃⌥F preferito,
  ⌃⌥→ / ⌃⌥← stazione, ⌃⌥↑ / ⌃⌥↓ volume
- **Rotella sull'icona** per il volume
- **Avviso di nuova versione** (controllo su GitHub al massimo una volta al giorno)

### Novità della 1.1
- **Brani preferiti**: clic sul brano in ascolto ▸ ★ Aggiungi ai brani preferiti. Nella finestra
  "Brani preferiti…": ricerca istantanea, filtro per stazione, ordinamento per colonna, elimina,
  copia, cerca su YouTube / YouTube Music / Apple Music / Spotify, esporta in CSV.
- Righe selezionate leggibili (testo bianco sul blu) in tutte le finestre.

### Cosa fa
- Stazioni a gruppi nel menu, con lo stesso `bookmarks.json` di Radiotray-NG
- Playlist PLS, M3U, ASX, XSPF; stream MP3, AAC e HLS
- Titolo e artista del brano nel menu e nelle notifiche (anche con le radio Mediaset)
- Volume, accendi/spegni l'ultima stazione, stazione precedente/successiva, tasti multimediali
- Timer di spegnimento, riconnessione automatica (anche dopo lo stop del Mac)
- **Cerca stazioni**: archivio pubblico Radio Browser, ascolto di prova e aggiunta ai preferiti
- **Editor delle stazioni**: rinomina, sposta (anche trascinando) ed elimina stazioni e gruppi
- Apri URL… con il nome vero della stazione e "Aggiungi alle stazioni…"
- Radio italiane consigliate (RTL 102.5, RDS, Deejay, 105, Virgin, R101, RMC, Kiss Kiss,
  Capital, m2o, Radio 24, Radiofreccia, Subasio, Rai)
- Avvio automatico al login

### Limiti noti
- Ogg Vorbis/Opus, FLAC e WMA non sono riproducibili su macOS (la ricerca li mostra in grigio).
- Alcune radio non inviano il titolo del brano (Rai, Radio 24, quelle in HLS come Deejay e Capital).
