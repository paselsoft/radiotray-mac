using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Threading;
using System.Threading.Tasks;

namespace RadioTray
{
    /// <summary>Un errore di rete già tradotto in un messaggio per l'utente.</summary>
    internal sealed class NetException : Exception
    {
        public NetException(string message) : base(message) { }
    }

    /// <summary>
    /// L'unico componente che va su Internet: usa il proxy di Windows (anche con script PAC) e le credenziali
    /// dell'utente di dominio, come fanno Edge e Chrome. Il proxy non viene mai aggirato.
    /// </summary>
    internal static class Net
    {
        public static readonly string UserAgent = "RadioTray-Windows/" + typeof(Net).Assembly.GetName().Version.ToString(3);
        private static readonly IWebProxy Proxy;
        public static readonly HttpClient Client;

        static Net()
        {
            // i programmi desktop hanno di serie 2 connessioni per server: troppo poche per stream + titoli + playlist
            ServicePointManager.DefaultConnectionLimit = 32;
            ServicePointManager.Expect100Continue = false;
            Proxy = WebRequest.GetSystemWebProxy();
            Proxy.Credentials = CredentialCache.DefaultNetworkCredentials;
            var handler = new HttpClientHandler
            {
                Proxy = Proxy,
                UseProxy = true,
                AllowAutoRedirect = true,
                MaxAutomaticRedirections = 10,
                UseCookies = false,
                AutomaticDecompression = DecompressionMethods.None,
            };
            Client = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
            Client.DefaultRequestHeaders.UserAgent.ParseAdd(UserAgent);
        }

        /// <summary>Il proxy usato per questo indirizzo, oppure null se la connessione è diretta.</summary>
        public static string ProxyFor(Uri uri)
        {
            try
            {
                if (Proxy.IsBypassed(uri)) return null;
                var p = Proxy.GetProxy(uri);
                return p == null || p == uri ? null : p.GetLeftPart(UriPartial.Authority);
            }
            catch (Exception e)
            {
                Log.Write($"Impossibile leggere il proxy per {uri.Host}: {e.Message}");
                return null;
            }
        }

        /// <summary>
        /// GET fino alle intestazioni (il corpo si legge dopo). Gli errori di rete diventano NetException con un messaggio chiaro.
        /// </summary>
        public static async Task<HttpResponseMessage> GetHeadersAsync(Uri uri, bool icyMetadata, TimeSpan timeout, CancellationToken ct)
        {
            var request = new HttpRequestMessage(HttpMethod.Get, uri);
            request.Headers.TryAddWithoutValidation("Accept", "*/*");
            if (icyMetadata) request.Headers.TryAddWithoutValidation("Icy-MetaData", "1");
            using (var timer = CancellationTokenSource.CreateLinkedTokenSource(ct))
            {
                timer.CancelAfter(timeout);
                try
                {
                    return await Client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timer.Token).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (!ct.IsCancellationRequested)
                {
                    throw new NetException(ProxyFor(uri) != null
                        ? "La radio non risponde (tempo scaduto, attraverso il proxy dell'ufficio)"
                        : "La radio non risponde (tempo scaduto)");
                }
                catch (HttpRequestException e)
                {
                    throw new NetException(Describe(e, ProxyFor(uri) != null));
                }
            }
        }

        public static bool IsHtml(HttpResponseMessage r) =>
            (r.Content.Headers.ContentType?.MediaType ?? "").IndexOf("html", StringComparison.OrdinalIgnoreCase) >= 0;

        public static string ContentType(HttpResponseMessage r) => r.Content.Headers.ContentType?.ToString() ?? "";

        public static string Header(HttpResponseMessage r, string name)
        {
            if (r.Headers.TryGetValues(name, out var v) || r.Content.Headers.TryGetValues(name, out v))
                foreach (var s in v) return s;
            return null;
        }

        /// <summary>Messaggio per l'utente da un'eccezione di rete.</summary>
        public static string Describe(Exception e, bool viaProxy)
        {
            for (var x = e; x != null; x = x.InnerException)
            {
                if (x is WebException we)
                {
                    switch (we.Status)
                    {
                        case WebExceptionStatus.NameResolutionFailure:
                            return "Server della radio non trovato (nome sconosciuto)";
                        case WebExceptionStatus.ProxyNameResolutionFailure:
                            return "Il proxy dell'ufficio non è raggiungibile (nome sconosciuto)";
                        case WebExceptionStatus.ConnectFailure:
                            return viaProxy ? "Impossibile collegarsi al proxy dell'ufficio" : "Impossibile collegarsi alla radio";
                        case WebExceptionStatus.TrustFailure:
                            return "Certificato https non accettato" + (viaProxy ? " (forse il proxy dell'ufficio controlla le connessioni https)" : "");
                        case WebExceptionStatus.SecureChannelFailure:
                            return "Connessione https non riuscita" + (viaProxy ? " (forse la blocca il proxy dell'ufficio)" : "");
                        case WebExceptionStatus.ServerProtocolViolation:
                            return "La radio risponde in un formato non standard (vecchio server Shoutcast?)";
                        case WebExceptionStatus.Timeout:
                            return "La radio non risponde (tempo scaduto)";
                        case WebExceptionStatus.ConnectionClosed:
                        case WebExceptionStatus.KeepAliveFailure:
                        case WebExceptionStatus.ReceiveFailure:
                        case WebExceptionStatus.SendFailure:
                            return viaProxy ? "Connessione interrotta (dal proxy dell'ufficio o dalla radio)" : "Connessione interrotta dalla radio";
                    }
                }
                if (x is AuthenticationException) return "Connessione https non riuscita (certificato o protocollo)";
                if (x is SocketException se) return "Errore di rete: " + se.Message;
                if (x is IOException && x.InnerException == null) return "Connessione interrotta: " + x.Message;
            }
            return "Errore di rete: " + e.Message;
        }
    }
}
