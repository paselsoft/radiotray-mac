using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace RadioTray
{
    /// <summary>Dall'indirizzo della stazione agli indirizzi degli stream (playlist PLS/M3U/ASX/XSPF), attraverso il proxy.</summary>
    internal static class StreamResolver
    {
        private const int MaxPlaylistBytes = 4096;

        /// <summary>Indirizzi riconosciuti come HLS dal contenuto (senza l'estensione .m3u8).</summary>
        private static readonly System.Collections.Concurrent.ConcurrentDictionary<string, bool> HlsUrls =
            new System.Collections.Concurrent.ConcurrentDictionary<string, bool>();

        public static bool IsHls(string url) => HlsSource.LooksLikeHls(url) || HlsUrls.ContainsKey(url);

        public static async Task<List<string>> ResolveAsync(string url, bool direct, CancellationToken ct)
        {
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) throw new NetException("Indirizzo della stazione non valido");
            if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)
                throw new NetException($"Protocollo \"{uri.Scheme}\" non supportato");
            if (direct || PlaylistParser.UrlLooksDirect(url))
            {
                Log.Write($"  {url}: stream diretto ({(direct ? "direct=true" : "estensione")})");
                return new List<string> { url };
            }

            bool viaProxy = Net.ProxyFor(uri) != null;
            using (var response = await Net.GetHeadersAsync(uri, false, TimeSpan.FromSeconds(15), ct).ConfigureAwait(false))
            {
                string effective = response.RequestMessage?.RequestUri?.AbsoluteUri ?? url;
                string contentType = Net.ContentType(response);
                int status = (int)response.StatusCode;
                if (status >= 400)
                {
                    string msg = NetMessages.ForHttpStatus(status, viaProxy, Net.IsHtml(response));
                    if (msg != null) throw new NetException(msg);
                    // come Radiotray-NG: con altri errori si prova comunque a suonarlo direttamente
                    Log.Write($"  {url}: HTTP {status}, tentativo come stream diretto");
                    return new List<string> { effective };
                }
                if (PlaylistParser.ContentTypeIsAudio(contentType))
                {
                    Log.Write($"  {url}: stream diretto ({contentType})");
                    return new List<string> { effective };
                }

                var buffer = new byte[MaxPlaylistBytes];
                int length = 0;
                using (var stream = await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
                using (ct.Register(() => response.Dispose()))
                {
                    try
                    {
                        int n;
                        while (length < buffer.Length && (n = await stream.ReadAsync(buffer, length, buffer.Length - length, ct).ConfigureAwait(false)) > 0)
                            length += n;
                    }
                    catch (IOException) when (length > 0) { }
                }
                ct.ThrowIfCancellationRequested();

                if (PlaylistParser.IsHls(contentType, buffer, length))
                {
                    Log.Write($"  {url}: stream HLS");
                    HlsUrls[effective] = true;
                    return new List<string> { effective };
                }
                var urls = PlaylistParser.UrlsFromData(buffer, contentType, new Uri(effective), out string format, length);
                if (urls == null)
                {
                    if (AudioFormat.FromContentType(contentType) == AudioKind.Html || AudioFormat.Sniff(buffer, length) == AudioKind.Html)
                        throw new NetException(NetMessages.ForHtmlInsteadOfAudio(viaProxy));
                    Log.Write($"  {url}: nessuna playlist riconosciuta ({(contentType.Length > 0 ? contentType : "tipo sconosciuto")}): stream diretto");
                    return new List<string> { effective };
                }
                if (urls.Count == 0) throw new NetException("La playlist della stazione è vuota");
                urls.RemoveAll(u => !u.StartsWith("http://", StringComparison.OrdinalIgnoreCase) && !u.StartsWith("https://", StringComparison.OrdinalIgnoreCase));
                if (urls.Count == 0) throw new NetException("La playlist contiene solo indirizzi mms:// o rtsp://, non supportati");
                Log.Write($"  {url}: playlist {format} con {urls.Count} voci");
                return urls;
            }
        }
    }
}
