# Piano: RadioTray per Windows 10 (PC d'ufficio dietro proxy)

Stato: **solo piano**, nessun codice ancora.

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

## Limiti noti

- Il codice Windows non si può provare qui né sul Mac: la prova vera è sul PC d'ufficio, come per
  l'iMac.
- Ogg/Opus: decodifica da valutare (NAudio non la ha di serie).
- Senza un certificato di firma (costa), Windows SmartScreen mostrerà un avviso al primo avvio
  ("Ulteriori informazioni" → "Esegui comunque"), se la politica dell'ufficio lo permette.
