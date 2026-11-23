using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace RadioTray
{
    /// <summary>
    /// Una sorgente audio: la connessione Shoutcast/Icecast (StreamConnection) oppure lo streaming HLS (HlsSource).
    /// Scrive l'audio nel tubo e segnala i titoli.
    /// </summary>
    internal interface IStreamSource : IDisposable
    {
        string Url { get; }
        string ContentType { get; }
        string StationName { get; }
        string Bitrate { get; }
        bool ViaProxy { get; }
        string LastError { get; }
        TimeSpan SinceLastData { get; }
        event Action<string> TitleReceived;
        void Pump(AudioPipe pipe);
    }

    /// <summary>
    /// Streaming HLS (.m3u8) attraverso il proxy: scarica la playlist e i segmenti man mano che escono e mette nel tubo
    /// l'audio AAC (dai segmenti .aac o dai .ts, separato con TsDemuxer). I titoli arrivano dai tag ID3 (RDS).
    /// </summary>
    internal sealed class HlsSource : IStreamSource
    {
        private const int StartSegmentsBehind = 3;
        private const int MaxPlaylistErrors = 5;

        private readonly string _mediaUrl;
        private HlsPlaylist _first;
        private readonly TsDemuxer _demuxer = new TsDemuxer();
        private long _lastDataTicks = DateTime.UtcNow.Ticks;
        private volatile bool _disposed;
        private readonly CancellationTokenSource _cts = new CancellationTokenSource();
        private string _lastTitle;
        private AudioPipe _pipe;

        public string Url { get; }
        public string ContentType { get; private set; } = "audio/aac";
        public string StationName => null;
        public string Bitrate { get; }
        public bool ViaProxy { get; }
        public string LastError { get; private set; }
        public TimeSpan SinceLastData => TimeSpan.FromTicks(DateTime.UtcNow.Ticks - Interlocked.Read(ref _lastDataTicks));
        public event Action<string> TitleReceived;

        private HlsSource(string url, string mediaUrl, HlsPlaylist media, int bandwidth, bool viaProxy)
        {
            Url = url;
            _mediaUrl = mediaUrl;
            _first = media;
            Bitrate = bandwidth > 0 ? ((bandwidth + 500) / 1000).ToString() : null;
            ViaProxy = viaProxy;
            _demuxer.AudioData += WriteAudio;
            _demuxer.Title += OnTitle;
        }

        public static bool LooksLikeHls(string url) =>
            Uri.TryCreate(url, UriKind.Absolute, out var u) && u.AbsolutePath.EndsWith(".m3u8", StringComparison.OrdinalIgnoreCase);

        public static async Task<HlsSource> OpenAsync(string url, CancellationToken ct)
        {
            var uri = new Uri(url);
            bool viaProxy = Net.ProxyFor(uri) != null;
            Log.Write($"  HLS {url} ({(viaProxy ? "proxy " + Net.ProxyFor(uri) : "diretta")})");
            var (text, effective) = await GetTextAsync(uri, ct).ConfigureAwait(false);
            var playlist = HlsPlaylist.Parse(text, effective);
            int bandwidth = 0;
            string mediaUrl = effective.AbsoluteUri;
            if (playlist.IsMaster)
            {
                var v = playlist.ChooseVariant();
                bandwidth = v.Bandwidth;
                mediaUrl = v.Url;
                Log.Write($"  variante {v.Bandwidth / 1000} kbit/s {v.Codecs}: {v.Url}");
                (text, effective) = await GetTextAsync(new Uri(mediaUrl), ct).ConfigureAwait(false);
                mediaUrl = effective.AbsoluteUri;
                playlist = HlsPlaylist.Parse(text, effective);
                if (playlist.IsMaster) throw new NetException("Playlist HLS annidata non supportata");
            }
            if (playlist.Encrypted) throw new NetException("Lo streaming HLS di questa radio è cifrato: non si può riprodurre");
            if (playlist.HasInitSegment) throw new NetException("Questa radio usa HLS con segmenti fMP4: non ancora supportato su Windows");
            if (playlist.Segments.Count == 0 && playlist.EndList) throw new NetException("La playlist HLS è vuota");
            Log.Write($"  HLS: {playlist.Segments.Count} segmenti da {playlist.TargetDuration:0.#} s, sequenza {playlist.MediaSequence}");
            return new HlsSource(url, mediaUrl, playlist, bandwidth, viaProxy);
        }

        private static async Task<(string text, Uri effective)> GetTextAsync(Uri uri, CancellationToken ct)
        {
            using (var r = await Net.GetHeadersAsync(uri, false, TimeSpan.FromSeconds(15), ct).ConfigureAwait(false))
            {
                int status = (int)r.StatusCode;
                if (status >= 400)
                    throw new NetException(NetMessages.ForHttpStatus(status, Net.ProxyFor(uri) != null, Net.IsHtml(r)) ?? $"La radio risponde con un errore (HTTP {status})");
                if (Net.IsHtml(r)) throw new NetException(NetMessages.ForHtmlInsteadOfAudio(Net.ProxyFor(uri) != null));
                var bytes = await r.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
                return (PlaylistParser.TextFromData(bytes) ?? "", r.RequestMessage?.RequestUri ?? uri);
            }
        }

        private void Touch() => Interlocked.Exchange(ref _lastDataTicks, DateTime.UtcNow.Ticks);

        private void WriteAudio(byte[] data, int offset, int count)
        {
            _pipe.Write(data, offset, count);
            Touch();
        }

        private void OnTitle(string title)
        {
            if (title == _lastTitle) return;
            _lastTitle = title;
            TitleReceived?.Invoke(title);
        }

        /// <summary>Scarica i segmenti finché la radio trasmette (su un thread dedicato).</summary>
        public void Pump(AudioPipe pipe)
        {
            _pipe = pipe;
            string error = null;
            try
            {
                long next = -1;
                int playlistErrors = 0;
                var playlist = _first;
                _first = null;
                while (!_disposed)
                {
                    int downloaded = 0;
                    if (playlist != null && playlist.Segments.Count > 0)
                    {
                        var segments = playlist.Segments;
                        if (next < 0) next = segments[Math.Max(0, segments.Count - StartSegmentsBehind)].Sequence;
                        if (next < segments[0].Sequence)
                        {
                            Log.Write($"  HLS: segmenti persi ({segments[0].Sequence - next}), si riprende dal più vecchio disponibile");
                            next = segments[0].Sequence;
                        }
                        foreach (var seg in segments.Where(s => s.Sequence >= next))
                        {
                            if (_disposed) return;
                            ProcessSegment(Download(seg.Url));
                            next = seg.Sequence + 1;
                            downloaded++;
                        }
                        if (playlist.EndList && downloaded == 0)
                        {
                            error = "fine della trasmissione";
                            break;
                        }
                    }
                    // nuova lettura della playlist: dopo una durata di segmento se ne sono arrivati, a metà se no
                    double target = playlist?.TargetDuration > 0 ? playlist.TargetDuration : 6;
                    Wait(TimeSpan.FromSeconds(Math.Max(1, downloaded > 0 ? target / 2 : target / 2)));
                    if (_disposed) return;
                    try
                    {
                        var (text, effective) = GetTextAsync(new Uri(_mediaUrl), _cts.Token).GetAwaiter().GetResult();
                        playlist = HlsPlaylist.Parse(text, effective);
                        playlistErrors = 0;
                        Touch();
                    }
                    catch (NetException e) when (++playlistErrors < MaxPlaylistErrors)
                    {
                        Log.Write($"  HLS: playlist non letta ({e.Message}), riprovo");
                        playlist = null;
                    }
                }
            }
            catch (Exception e)
            {
                if (!_disposed && !(e is ObjectDisposedException) && !(e is OperationCanceledException))
                    error = e is NetException ? e.Message : Net.Describe(e, ViaProxy);
            }
            if (error != null) Log.Write($"  HLS {Url} terminato: {error}");
            LastError = error;
            pipe.CompleteWriting();
        }

        private void Wait(TimeSpan time)
        {
            var until = DateTime.UtcNow + time;
            while (!_disposed && DateTime.UtcNow < until) Thread.Sleep(100);
        }

        private byte[] Download(string url)
        {
            var uri = new Uri(url);
            using (var r = Net.GetHeadersAsync(uri, false, TimeSpan.FromSeconds(20), _cts.Token).GetAwaiter().GetResult())
            {
                int status = (int)r.StatusCode;
                if (status >= 400)
                    throw new NetException(NetMessages.ForHttpStatus(status, ViaProxy, Net.IsHtml(r)) ?? $"Segmento HLS non scaricato (HTTP {status})");
                using (var s = r.Content.ReadAsStreamAsync().GetAwaiter().GetResult())
                using (_cts.Token.Register(() => r.Dispose()))
                using (var ms = new MemoryStream())
                {
                    var buffer = new byte[16384];
                    int n;
                    while ((n = s.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        ms.Write(buffer, 0, n);
                        Touch();
                        if (ms.Length > 16 * 1024 * 1024) throw new NetException("Segmento HLS troppo grande");
                    }
                    return ms.ToArray();
                }
            }
        }

        private void ProcessSegment(byte[] d)
        {
            if (d.Length == 0) return;
            if (d[0] == 0x47 && (d.Length < 189 || d[188] == 0x47))
            {
                _demuxer.Feed(d, 0, d.Length);
                _demuxer.Flush();
                if (_demuxer.Audio == AudioKind.Mp3) ContentType = "audio/mpeg";
                return;
            }
            if (d.Length > 8 && Encoding.ASCII.GetString(d, 4, 4) is string box && (box == "ftyp" || box == "moof" || box == "styp"))
                throw new NetException("Questa radio usa HLS con segmenti fMP4: non ancora supportato su Windows");
            // audio "impacchettato" (.aac/.mp3): uno o più tag ID3 all'inizio, poi i frame
            int pos = 0;
            while (pos < d.Length)
            {
                int len = Id3.TagLength(d, pos, d.Length - pos);
                if (len == 0) break;
                string t = Id3.StreamTitle(d, pos, Math.Min(len, d.Length - pos));
                if (t != null) OnTitle(t);
                pos = Math.Min(d.Length, pos + len);
            }
            if (pos < d.Length)
            {
                if (AudioFormat.Sniff(d.Skip(pos).Take(8192).ToArray(), Math.Min(8192, d.Length - pos)) == AudioKind.Mp3) ContentType = "audio/mpeg";
                WriteAudio(d, pos, d.Length - pos);
            }
        }

        public void Dispose()
        {
            _disposed = true;
            try { _cts.Cancel(); } catch (ObjectDisposedException) { }
        }
    }
}
