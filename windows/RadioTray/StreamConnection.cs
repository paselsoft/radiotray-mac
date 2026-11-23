using System;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace RadioTray
{
    /// <summary>
    /// La connessione allo stream, attraverso il proxy: l'audio va nel tubo (e da lì al decodificatore),
    /// i titoli ICY vengono letti dalla stessa connessione.
    /// </summary>
    internal sealed class StreamConnection : IStreamSource
    {
        private HttpResponseMessage _response;
        private Stream _stream;
        private readonly IcyParser _parser;
        private long _lastDataTicks = DateTime.UtcNow.Ticks;
        private volatile bool _disposed;

        public string Url { get; }
        public string ContentType { get; }
        public string StationName { get; }
        public string Bitrate { get; }
        public bool ViaProxy { get; }
        public event Action<string> TitleReceived;

        public TimeSpan SinceLastData => TimeSpan.FromTicks(DateTime.UtcNow.Ticks - Interlocked.Read(ref _lastDataTicks));

        private StreamConnection(string url, HttpResponseMessage response, Stream stream, bool viaProxy)
        {
            Url = url;
            _response = response;
            _stream = stream;
            ViaProxy = viaProxy;
            ContentType = Net.ContentType(response);
            StationName = IcyParser.StationNameFromHeader(Net.Header(response, "icy-name"));
            Bitrate = Net.Header(response, "icy-br");
            int.TryParse(Net.Header(response, "icy-metaint"), out int metaint);
            _parser = new IcyParser(Math.Max(0, metaint));
        }

        public static async Task<StreamConnection> OpenAsync(string url, CancellationToken ct)
        {
            var uri = new Uri(url);
            string proxy = Net.ProxyFor(uri);
            Log.Write($"  connessione a {url} ({(proxy != null ? "proxy " + proxy : "diretta")})");
            var response = await Net.GetHeadersAsync(uri, true, TimeSpan.FromSeconds(20), ct).ConfigureAwait(false);
            int status = (int)response.StatusCode;
            if (status >= 400)
            {
                string msg = NetMessages.ForHttpStatus(status, proxy != null, Net.IsHtml(response)) ?? $"La radio risponde con un errore (HTTP {status})";
                response.Dispose();
                throw new NetException(msg);
            }
            var stream = await response.Content.ReadAsStreamAsync().ConfigureAwait(false);
            var conn = new StreamConnection(url, response, stream, proxy != null);
            Log.Write($"  risposta: {conn.ContentType}, icy-metaint {Net.Header(response, "icy-metaint") ?? "-"}, icy-br {conn.Bitrate ?? "-"}, icy-name {conn.StationName ?? "-"}");
            return conn;
        }

        /// <summary>Legge lo stream finché non finisce o si chiude la connessione (su un thread dedicato).</summary>
        public void Pump(AudioPipe pipe)
        {
            var buffer = new byte[16384];
            string error = null;
            try
            {
                int n;
                while (!_disposed && (n = _stream.Read(buffer, 0, buffer.Length)) > 0)
                {
                    Interlocked.Exchange(ref _lastDataTicks, DateTime.UtcNow.Ticks);
                    foreach (var title in _parser.Feed(buffer, 0, n, pipe.Write)) TitleReceived?.Invoke(title);
                }
                if (!_disposed) error = "fine dello stream";
            }
            catch (Exception e)
            {
                // dopo la chiusura (cambio di stazione) gli errori sono attesi; questo thread non deve mai lanciare
                if (!_disposed && !(e is ObjectDisposedException)) error = Net.Describe(e, ViaProxy);
            }
            if (error != null) Log.Write($"  lettura di {Url} terminata: {error}");
            LastError = error;
            pipe.CompleteWriting();
        }

        public string LastError { get; private set; }

        public void Dispose()
        {
            _disposed = true;
            try { _stream?.Dispose(); } catch (Exception) { }
            try { _response?.Dispose(); } catch (Exception) { }
            _stream = null;
            _response = null;
        }
    }
}
