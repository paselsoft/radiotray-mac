namespace RadioTray
{
    /// <summary>Messaggi chiari per gli errori di rete, distinguendo quelli che vengono dal proxy dell'ufficio.</summary>
    public static class NetMessages
    {
        public const string ProxyBlocked = "Accesso bloccato dal proxy dell'ufficio";

        /// <summary>
        /// Messaggio per una risposta HTTP di errore; null se il codice non è un errore da segnalare
        /// (per gli altri 4xx/5xx il chiamante prova comunque a suonare lo stream, come Radiotray-NG).
        /// </summary>
        /// <param name="viaProxy">la richiesta è passata dal proxy</param>
        /// <param name="html">la risposta è una pagina web (le pagine di blocco dei proxy lo sono)</param>
        public static string ForHttpStatus(int status, bool viaProxy, bool html)
        {
            if (status == 407) return "Il proxy dell'ufficio chiede utente e password (autenticazione non riuscita)";
            if (viaProxy && (status == 403 || status == 451 || (status >= 400 && html && status != 404 && status != 410)))
                return ProxyBlocked + $" (HTTP {status})";
            if (status == 404 || status == 410) return $"Stazione non trovata (HTTP {status})";
            if (status == 403) return "La radio rifiuta la connessione (HTTP 403)";
            if (status == 502 || status == 504)
                return viaProxy ? $"Il proxy dell'ufficio non riesce a raggiungere la radio (HTTP {status})" : $"La radio non risponde (HTTP {status})";
            return null;
        }

        /// <summary>Messaggio quando al posto dell'audio arriva una pagina web.</summary>
        public static string ForHtmlInsteadOfAudio(bool viaProxy) => viaProxy
            ? ProxyBlocked + ": è arrivata una pagina web invece dell'audio"
            : "All'indirizzo della stazione c'è una pagina web, non una radio";
    }
}
