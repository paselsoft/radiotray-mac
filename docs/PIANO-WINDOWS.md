# Piano: RadioTray per Windows 10 (PC d'ufficio dietro proxy)

Stato: **tutte e quattro le fasi fatte**, pubblicate nella versione stabile 1.17.0 (Windows 0.4.1). Fasi 1 e 2 provate sul PC d'ufficio; della fase 4 provate le copertine (RDS e Radio 105).

## Si può fare?

Sì. L'app per Mac è scritta in Objective-C con le librerie di macOS (Cocoa, AVFoundation): il codice
non si può riusare così com'è, ma **la logica sì** (formati delle playlist, titoli ICY e Mediaset,
"Titolo * Artista", jingle, copertine, loghi, sveglia, backup) e soprattutto **i file restano gli
stessi**: `bookmarks.json`, `brani-preferiti.json`, il file di backup. Si potranno passare dal Mac
al PC e viceversa.

## Il punto delicato: il proxy del Ministero

In un ufficio pubblico il proxy di solito:
- è configurato da Windows (spesso con uno script PAC) e chiede **l'autenticazione con l'utente di
  dominio** (NTLM/Kerberos), senza che l'utente scriva la password;
- può **filtrare le categorie** di siti (lo streaming audio è spesso bloccato o limitato);
- talvolta **ispeziona le connessioni HTTPS** con un certificato aziendale.

Scelte per gestirlo **in modo corretto**, usando il proxy come previsto e senza aggirarlo:
- tutto il traffico (playlist, stream, titoli, copertine, ricerca) passa da **un solo componente di
  rete dell'app** che usa le impostazioni proxy di Windows e le credenziali di dominio
  dell'utente (come fanno Edge e Chrome);
- il lettore audio non va su Internet da solo: legge lo stream da un **piccolo ripetitore interno**
  (`127.0.0.1`, solo sul PC) che l'app alimenta tramite quel componente. Così un solo punto
  conosce il proxy, e lo stesso collegamento serve anche per leggere i titoli (una connessione
  invece di due, meglio per proxy e server);
- se il proxy **blocca** le radio, l'app lo dice chiaramente ("Accesso bloccato dal proxy
  dell'ufficio") e **non prova a eluderlo**: in quel caso si chiede l'abilitazione all'assistenza
  informatica, oppure si rinuncia.

> Prima di installarla conviene verificare che le regole d'uso della postazione permettano
> l'ascolto di radio via Internet e l'uso di programmi non installati dall'assistenza.

## Tecnologia proposta

| Esigenza | Scelta | Perché |
|---|---|---|
| Linguaggio e finestre | **C# con WinForms su .NET Framework 4.8** | già presente in Windows 10: nessun runtime da installare, niente permessi di amministratore |
| Icona nell'area di notifica | `NotifyIcon` + menu | equivalente dell'icona nella barra dei menu del Mac |
| Rete e proxy | `HttpClient` con proxy di sistema e credenziali predefinite | proxy PAC, NTLM/Kerberos come il browser |
| Audio MP3/AAC | **NAudio** (decodifica tramite Media Foundation di Windows) | libreria piccola, nessun codec da installare |
| HLS (Deejay, RDS, Radio Italia…) | il ripetitore interno scarica playlist e segmenti e li passa al decodificatore | stessa strada del proxy |
| Notifiche | notifiche di Windows 10 (toast) | con il pulsante "★ Preferito" |
| Distribuzione | **cartella portatile** (`RadioTray.exe` + DLL) in un `.zip`; impostazioni in `%APPDATA%\RadioTray` | si avvia senza installazione e senza permessi di amministratore |
| Compilazione | GitHub Actions su runner Windows, `.zip` come release | come per il Mac |

Alternativa scartata: VLC (libVLC) riproduce tutto, ma pesa circa 80 MB e non gestisce
l'autenticazione NTLM dei proxy.

## Fasi

1. **Base e proxy**: icona nell'area di notifica, gruppi di stazioni da `bookmarks.json`, playlist
   PLS/M3U/ASX/XSPF, MP3/AAC, titolo e artista, volume, accendi/spegni, notifiche, ripetitore
   interno attraverso il proxy, messaggi chiari se il proxy blocca. → **prova sul PC d'ufficio.**
2. **HLS e radio italiane**: Deejay, Capital, m2o, RDS, Radio Italia; correzioni Mediaset
   (formato "~", titolo/artista al contrario, jingle).
3. **Preferiti e ricerca**: brani preferiti (finestra con ricerca, filtro, CSV), cronologia,
   Cerca stazioni (Radio Browser), editor delle stazioni, importazione del backup del Mac.
4. **Rifiniture**: copertine e loghi, finestra "In riproduzione", scorciatoie da tastiera
   (Ctrl+Alt invece di ⌃⌥), timer e sveglia, avvio all'accesso.

## Cosa serve sapere prima di iniziare

1. Sul PC d'ufficio **una radio si ascolta dal browser**? Per esempio
   `https://ice1.somafm.com/groovesalad-128-mp3` in Edge o Chrome. Se no, il proxy blocca lo
   streaming e l'app non potrà fare di meglio.
2. Il browser **chiede utente e password** per il proxy, o entra da solo?
3. Si possono **avviare programmi** scaricati (un `.exe` da una cartella in Documenti), o
   compaiono blocchi di sicurezza (SmartScreen, AppLocker)?
4. Versione di Windows 10 (Impostazioni → Sistema → Informazioni).

## Risposte (verificate sul PC d'ufficio, novembre 2026)

1. **Streaming nel browser: sì.** `https://ice1.somafm.com/groovesalad-128-mp3` si ascolta senza problemi
   in Edge/Chrome: il proxy lascia passare gli stream audio.
2. **Proxy senza credenziali:** il browser entra da solo (autenticazione integrata di Windows o proxy
   trasparente). L'app deve usare il proxy di sistema con le credenziali predefinite (`UseDefaultCredentials`).
3. **Programmi scaricati: sì.** A volte compare SmartScreen ma si può proseguire (account amministratore);
   va bene un `.exe` non firmato, con l'avviso "Esegui comunque" la prima volta.
4. **Windows 10 Enterprise 22H2**, build 19045.6456 (64 bit): .NET Framework 4.8 è già presente.

Si può partire dalla fase 1.

## Fase 1: com'è fatta (novembre 2026)

```
windows/RadioTray.Core/   logica senza interfaccia (netstandard2.0): bookmarks.json, playlist PLS/M3U/ASX/XSPF,
                          titoli (ICY, Mediaset "~", RDS " * ", jingle), separazione audio/titoli ICY,
                          riconoscimento del formato dai primi byte, messaggi del proxy
windows/RadioTray.Tests/  test della logica (dotnet run, anche su Linux): gli stessi casi dei test per Mac
windows/RadioTray/        app WinForms .NET Framework 4.8 + NAudio
```

- **Rete** (`Net.cs`): un solo `HttpClient` con il proxy di sistema (PAC compreso) e
  `CredentialCache.DefaultNetworkCredentials` per il proxy; le credenziali non vengono mai mandate alle radio.
  Errori tradotti: 407 → "chiede utente e password", 403/451 o pagina web attraverso il proxy →
  "Accesso bloccato dal proxy dell'ufficio", certificato rifiutato → "forse il proxy controlla le https".
- **Una connessione per stazione** (`StreamConnection.cs`): con `Icy-MetaData: 1` l'audio va nel tubo
  (`AudioPipe.cs`, con contropressione) e i titoli si leggono dagli stessi byte.
- **Decodifica**: MP3 con il codec MP3 di Windows (ACM, frame per frame, dal tubo); AAC con Media Foundation,
  che legge dal **ripetitore interno** (`LocalRelay.cs`: `TcpListener` solo su 127.0.0.1, porta casuale,
  nessun permesso di amministratore, aperto solo quando serve). Se l'ACM non c'è, anche l'MP3 passa da lì.
  Poi buffer di qualche secondo, volume, `WaveOutEvent`.
- **Riconnessione** come sul Mac (2, 5, 10, 15, 20, 30… s) e server successivi della playlist / `mirrors`.
- **Menu**: brano (clic = copia), Accendi/Spegni, formato, volume, gruppi, stazioni, precedente/successiva,
  Apri indirizzo…, Preferenze (Modifica stazioni nel Blocco note con ricarica automatica, notifiche,
  accendi all'avvio, **Diagnostica di rete…**, registro), Informazioni, Esci.
- **CI**: job `windows` (runner Windows): test, compilazione, prova di avvio, `RadioTray-Windows.zip`;
  il job `release` pubblica `.dmg` e `.zip` insieme nell'anteprima (e nelle versioni stabili).

Provato qui (Linux, .NET 8) con radio vere: rete + titoli ICY + tubo + ripetitore su SomaFM (MP3 e AAC da
playlist PLS) e Radio 105 (titoli Mediaset); riconoscimento di HLS e delle pagine web al posto dell'audio.
**Non provato**: la parte Windows (audio NAudio/Media Foundation, menu, notifiche, proxy dell'ufficio).

### Diagnostica di rete sul PC d'ufficio (23 novembre 2026, build 113)

Windows 10 22H2 (19045), .NET Framework 4.8. Tutte e tre le radio passano dal proxy `10.139.232.11:8080`
letto dallo script PAC, senza credenziali da inserire:

| Radio | Risposta | Titoli ICY | Velocità |
|---|---|---|---|
| RTL 102.5 (https, Shoutcast) | 200 `audio/mpeg` in 2,6 s | sì | 534 kbit/s |
| SomaFM Groove Salad (https) | 200 `audio/mpeg` in 1,1 s | sì | 2118 kbit/s |
| Radio 105 (http) | 200 `audio/mpeg` in 0,5 s | sì | 1217 kbit/s |

Il proxy aggiunge `Via: … Cluster` anche alle https: le apre e le ricontrolla con il certificato
dell'ufficio, che Windows (e quindi l'app) accetta. Restano da provare l'audio e il menu.

### Prova d'ascolto sul PC d'ufficio (23 novembre 2026, build 113)

- **Si sentono** (MP3 e AAC): Radio 105, RTL 102.5, Virgin, R101, Radio Monte Carlo, Kiss Kiss, Radio 24,
  Radiofreccia, Subasio; Rai Radio 1, 2, 3, Isoradio; Radio Swiss Jazz, SomaFM Groove Salad, Secret Agent,
  Sonic Universe; Radio Swiss Classic; Radio Paradise. Menu, titolo e artista, formato, volume: a posto.
- **Non si sentono** (come previsto, sono HLS `.m3u8`, fase 2): RDS, Deejay, Capital, m2o.
- **Problema**: "Modifica stazioni…" dava "Accesso negato": la politica della postazione non lascia avviare il
  Blocco note da un altro programma. Dalla 0.1.1 stazioni e registro si aprono in una finestra interna
  (editor con controllo prima di salvare, copia in `bookmarks.json.bak`; registro con "Copia tutto").
  "Apri la cartella", se bloccato, copia il percorso negli appunti.
- **0.1.1 provata** (build 115): Modifica stazioni, Apri il registro e Apri la cartella di RadioTray funzionano.
  **Fase 1 conclusa.**

### Da provare sul PC d'ufficio
1. Scaricare `RadioTray-Windows.zip` dalla release **anteprima**, estrarlo in Documenti, avviare `RadioTray.exe`
   (SmartScreen: "Ulteriori informazioni" → "Esegui comunque").
2. Preferenze → **Diagnostica di rete…**: incollare qui il rapporto (è negli appunti).
3. Ascoltare una radio MP3 (Radio 105, SomaFM Groove Salad) e una AAC (SomaFM da playlist `.pls`):
   audio, titolo nella notifica, volume, Spegni/Accendi, cambio di stazione.
4. Se qualcosa non va: Preferenze → Apri il registro, e copiare qui le ultime righe.

## Fase 2: HLS e radio italiane (novembre 2026)

Com'è fatto lo streaming delle quattro radio che non suonavano:

| Radio | Playlist | Segmenti | Titoli |
|---|---|---|---|
| RDS | master → `chunklist.m3u8`, segmenti da 4 s | `.aac` (ADTS, AAC-LC 128k) con tag ID3 in testa | JSON nel frame ID3 `JSI3` (`traccia`, `artista`, `cover`) |
| Deejay, Capital, m2o | master → `play1.m3u8`, segmenti da 10 s | `.ts` (MPEG-TS, solo audio HE-AAC 122k, PID 513) | nessuno nello stream: servizio GEDI `…/api/pub/v2/all/gdwc-audio-player/onair?format=json` |

- **Logica comune**: `HlsPlaylist` (master/media, scelta della variante solo audio fino a 320 kbit/s, fMP4 e
  cifratura riconosciuti), `TsDemuxer` (PAT/PMT, PES audio AAC/MP3, metadati ID3), `Id3` (frame v2.3/2.4,
  JSON di RDS, TIT2/TPE1), `OnAir` (titoli GEDI: "Titolo ARTISTA MAIUSCOLO", o dal nome della copertina).
  "LINK * 1002264" di RDS (codice al posto dell'artista) non è un brano.
- **App**: `HlsSource` scarica playlist e segmenti attraverso il proxy (si parte 3 segmenti indietro, la
  playlist si rilegge a metà della durata di un segmento) e mette l'AAC nel tubo: da lì Media Foundation dal
  ripetitore interno, come per le altre radio AAC. Una playlist HLS senza estensione `.m3u8` viene riconosciuta
  dal contenuto. `OnAirPoller` legge il servizio GEDI ogni 20 s.
- **Menu**: "Titoli di questa stazione" → "Titolo e artista al contrario" e "Ignora i titoli".

Provato qui (Linux, .NET 8) con le radio vere: RDS, Deejay, Capital e m2o danno audio AAC continuo
(controllato con ffmpeg: AAC-LC per RDS, HE-AAC per le GEDI, nessun errore) e i titoli (RDS dal JSON ID3,
le altre dal servizio GEDI). **Da provare sul PC d'ufficio**: che Media Foundation suoni l'HE-AAC con la
qualità piena (48 kHz) e non solo la parte base a 24 kHz.

**0.2.0 provata sul PC d'ufficio** (23 novembre 2026, build 117): RDS, Deejay, Capital e m2o suonano
perfettamente, con i titoli; le altre radio continuano ad andare. **Fase 2 conclusa.**

## Fase 3: preferiti, cronologia, ricerca, editor, backup (novembre 2026)

Stessi file e formati della versione per Mac, così si passa da un computer all'altro:
`brani-preferiti.json` e `ascoltati-di-recente.json` (`[{"title","artist","station","added"}]`, data ISO 8601),
backup `RadioTray-backup.json` (`"format": "radiotray-mac-backup"`, impostazioni con i nomi del Mac:
`volume-level`, `swapped-title-artist-stations`…), chiavi per stazione `gruppo\nstazione` o `url\n…`.

- **Logica comune** (testata): `FavoriteTracks` (aggiunta senza doppioni, ricerca senza accenti a parole,
  cronologia con limite, CSV per Excel, indirizzi di ricerca YouTube/Spotify/Apple Music), `RadioBrowser`
  (indirizzi, lettura, Ogg/Opus/FLAC/WMA in fondo, nomi alternativi come sul Mac), `Backup`,
  `BookmarksDocument` (modifica di bookmarks.json che conserva i campi sconosciuti; unione per indirizzo).
- **Menu**: sottomenu del brano (★ Aggiungi ai preferiti, Copia, Cerca su YouTube), Ascoltati di recente,
  Brani preferiti…, Cerca stazioni…, "Aggiungi «…» alle stazioni…" per gli indirizzi aperti a mano,
  Preferenze → Backup (Esporta / Importa anche dal Mac).
- **"★ Preferito" nella notifica**: le notifiche a fumetto di `NotifyIcon` non hanno pulsanti (i "toast" con
  pulsanti richiedono un collegamento nel menu Start con un AppUserModelID, cioè un'installazione). Al loro posto:
  **clic sulla notifica** = aggiungi ai preferiti (la notifica lo scrive).
- **Finestre**: Brani preferiti (ricerca, filtro, ordinamento, Canc, Ctrl+C, doppio clic = YouTube, CSV),
  Cerca stazioni (per nome/genere/più ascoltate, Italia/mondo, Ascolta, Aggiungi), Stazioni (albero gruppi/stazioni,
  nome/indirizzo/notifiche, nuovo, elimina, su/giù, sposta, prova, salva con controllo e `.bak`).
- Il browser per le ricerche si apre con ShellExecute; se la politica del PC lo blocca, l'indirizzo va negli appunti.

Provato qui: 307 controlli sulla logica; ricerche vere su Radio Browser (Radio Italia, Radio Monte Carlo,
genere jazz, più ascoltate in Italia) lette correttamente. Le finestre vanno provate sul PC d'ufficio.

## Fase 4: rifiniture (novembre 2026)

- **Copertine**: prima quella ufficiale della radio (RDS nel JSON ID3, GEDI nel campo `image`), poi il catalogo
  pubblico di Apple (iTunes Search, accettata solo se l'artista corrisponde, come sul Mac). Se manca: **logo** della
  stazione (campo `image` di bookmarks.json, file o indirizzo; poi Radio Browser per indirizzo e per nome, niente SVG).
  Cache in `%LOCALAPPDATA%\RadioTray\immagini`; si scarica solo con la finestra In riproduzione aperta.
  Le notifiche a fumetto di Windows non mostrano immagini.
- **Finestra In riproduzione** (`NowPlayingWindow`): copertina/logo, titolo, artista, stazione, ★, ⏮ ⏻ ⏭, volume,
  "Sempre in primo piano"; si riapre all'avvio se era aperta.
- **Scorciatoie** (`HotKeys`, RegisterHotKey): Ctrl+Alt+P/F/←/→/↑/↓ come ⌃⌥ sul Mac, più i tasti multimediali.
  Se un tasto è già usato da un altro programma si salta (scritto nel registro). Ctrl+Alt è AltGr sulla tastiera
  italiana: P, F e le frecce non producono caratteri con AltGr, quindi non danno fastidio.
- **Timer di spegnimento** (15 min – 2 ore, volume che cala negli ultimi 30 s) e **radiosveglia** (`Alarm` nella
  logica comune, stessa regola del Mac: giorni a bit, 10 minuti di tolleranza, una volta al giorno; volume crescente
  in 2 minuti).
- **Avvio con Windows**: valore `RadioTray` in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (solo utente,
  senza amministratore); il percorso si aggiorna se la cartella viene spostata.
- Il backup esporta anche sveglia e scorciatoie con i nomi del Mac (`alarm-minutes`, `alarm-days`, `hot-keys`…).

Provato qui: 343 controlli sulla logica (copertine, loghi, sveglia); richieste vere al catalogo di Apple (copertine
di Stevie Wonder, Gazzelle, Miles Davis) e a Radio Browser (loghi di Radio 105, RTL 102.5, Deejay).
Finestre, scorciatoie, sveglia e avvio vanno provati sul PC d'ufficio.

### 0.4.1 (versione stabile 1.17.0)
Dalla prova della finestra In riproduzione: le copertine funzionano (ufficiale per RDS, dal catalogo di Apple
per Radio 105), ma il simbolo ⏻ non esiste nel font di Windows 10 e compariva come un quadratino. Ora i pulsanti
usano le icone di Windows 10 (Segoe MDL2 Assets): riproduci/ferma, stella vuota/piena. In più la finestra mostra
la qualità dello stream (per esempio "AAC (HLS) 129 kbps") e la percentuale del volume, anche mentre si trascina.

**0.4.1 provata sul PC d'ufficio** (23 novembre 2026): con la radio spenta il pulsante ▶ verde, la stella disattivata
e il logo della stazione (Radio Capital); in ascolto il ■ rosso, la stella, la copertina (Franco Battiato, "Impressioni
di Settembre", su Radio Capital via GEDI), la riga "AAC (HLS) 122 kbps" e il volume "70%". Tutto corretto.

## Limiti noti

- Il codice Windows non si può provare qui né sul Mac: la prova vera è sul PC d'ufficio, come per
  l'iMac.
- Ogg/Opus: decodifica da valutare (NAudio non la ha di serie).
- Senza un certificato di firma (costa), Windows SmartScreen mostrerà un avviso al primo avvio
  ("Ulteriori informazioni" → "Esegui comunque"), se la politica dell'ufficio lo permette.
