Lettore di radio via Internet nella barra dei menu per **macOS 10.13 High Sierra** e successivi
(Intel 64 bit; provato su iMac 27" Late 2009), ispirato a Radiotray-NG per Linux.

**Installazione:** apri `RadioTray-….dmg`, trascina RadioTray in Applicazioni, poi la prima volta
clic destro sull'app → Apri → Apri. Istruzioni complete nel file LEGGIMI.txt dentro il .dmg.

### Novità della 1.6
- **Ricerca nell'editor delle stazioni**: scrivi una parte del nome, del gruppo o dell'indirizzo
  e restano solo le stazioni che corrispondono (maiuscole e accenti non contano)
- **Importa playlist…**: aggiunge le stazioni dei file .pls e .m3u scaricati dai siti delle radio,
  anche trascinandoli nell'elenco; nome preso dalla playlist, scelta del gruppo, niente doppioni
  (i server di riserva della stessa radio diventano una stazione sola)

### Novità della 1.5
- **Copertine ufficiali di RDS**: titolo, artista e copertina arrivano direttamente dalla radio
  (prima del catalogo Apple), anche per i brani italiani che il catalogo non trova
- **Verifica le stazioni** (Preferenze ▸ Verifica le stazioni…): prova tutte le stazioni, mostra
  quelle che non rispondono e propone un indirizzo nuovo dall'archivio Radio Browser;
  "Ascolta la proposta" per provarlo, "Usa l'indirizzo proposto" per sostituirlo con un clic
- **Loghi nel menu** accanto al nome di ogni stazione, e anche nell'editor delle stazioni
  (si possono togliere: Preferenze ▸ Loghi delle stazioni nel menu)
- **Logo da indirizzo web**: nell'editor, "Logo…" accetta l'indirizzo di un'immagine
  (in Safari: clic destro sul logo ▸ Copia indirizzo immagine) oltre a un file sul Mac

### Novità della 1.4.2
- **Logo della stazione** al posto della copertina durante jingle, parlato e con le radio che non
  mandano i titoli: dall'archivio Radio Browser, oppure scelto da te nell'editor (pulsante "Logo…")
- "Ignora i titoli di questa stazione" (nel menu, sotto il volume) per le radio che mandano titoli
  sbagliati o vecchi, come a volte RMC 80 e 105 Hits: al loro posto si vede il logo
- Jingle e slogan delle radio ("Radio 105", "RadioFreccia"…) non vengono più presi per brani
- Le radio con indirizzo http:// (per esempio Radio Siena) ora funzionano
- Percentuale del volume nella finestra "In riproduzione"
- La copertina non resta quella della stazione precedente

### Novità della 1.4.1
- Copertine e titoli corretti per le radio che scrivono "Titolo - Artista" al contrario
  (per esempio Radio 105 Classics): rilevate da sole, o a mano dal sottomenu del brano
- Riconosciuto il formato "Titolo * Artista * codice" (per esempio RDS Next)

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
