using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace RadioTray
{
    internal enum PlayerState { Stopped, Connecting, Playing }

    /// <summary>
    /// Il lettore: risolve la playlist, si collega allo stream attraverso il proxy, decodifica e suona.
    /// Se lo stream cade si riconnette; se un server non va prova i successivi (playlist e server di riserva).
    /// Gli eventi arrivano sul thread dell'interfaccia.
    /// </summary>
    internal sealed class Player : IDisposable
    {
        private static readonly int[] ReconnectDelays = { 2, 5, 10, 15, 20, 30, 30, 30, 60, 60 };
        private static readonly TimeSpan StallTimeout = TimeSpan.FromSeconds(20);
        private static readonly TimeSpan PrebufferTime = TimeSpan.FromSeconds(1.5);
        private static readonly TimeSpan MaxBufferTime = TimeSpan.FromSeconds(6);

        private readonly SynchronizationContext _ui;
        private readonly Lazy<LocalRelay> _relay = new Lazy<LocalRelay>(() => new LocalRelay());   // aperto solo quando serve
        private CancellationTokenSource _session;
        private VolumeSampleProvider _volumeProvider;
        private int _volume = 80;
        private int _generation;

        public PlayerState State { get; private set; } = PlayerState.Stopped;
        public string Format { get; private set; }

        public event Action<PlayerState> StateChanged;
        public event Action<string> TitleReceived;
        /// <summary>Copertina ufficiale del prossimo titolo (RDS).</summary>
        public event Action<string> CoverReceived;
        public event Action<string> StationNameReceived;
        /// <summary>Errore definitivo: il lettore si è fermato.</summary>
        public event Action<string> Failed;
        /// <summary>Messaggio informativo (per esempio "Connessione persa, riprovo…").</summary>
        public event Action<string> Notice;

        public Player(SynchronizationContext ui) { _ui = ui; }

        public int Volume
        {
            get => _volume;
            set
            {
                _volume = Math.Max(0, Math.Min(100, value));
                var vp = _volumeProvider;
                if (vp != null) vp.Volume = _volume / 100f;
            }
        }

        private void Post(int generation, Action action)
        {
            _ui.Post(_ =>
            {
                if (generation == _generation) action();
            }, null);
        }

        private void SetState(int generation, PlayerState state)
        {
            Post(generation, () =>
            {
                if (State == state) return;
                State = state;
                StateChanged?.Invoke(state);
            });
        }

        public void Play(string url, bool direct, IEnumerable<string> mirrors)
        {
            Stop();
            int generation = ++_generation;
            var cts = new CancellationTokenSource();
            _session = cts;
            State = PlayerState.Connecting;
            StateChanged?.Invoke(State);
            var sources = new List<string> { url };
            sources.AddRange((mirrors ?? Enumerable.Empty<string>()).Where(m => m != url));
            Task.Run(() => RunAsync(generation, sources, direct, cts.Token));
        }

        public void Stop()
        {
            _generation++;
            _session?.Cancel();
            _session = null;
            _volumeProvider = null;
            Format = null;
            if (State != PlayerState.Stopped)
            {
                State = PlayerState.Stopped;
                StateChanged?.Invoke(State);
            }
        }

        private sealed class Outcome
        {
            public bool Played;
            public string Error;
        }

        private async Task RunAsync(int generation, List<string> sources, bool direct, CancellationToken ct)
        {
            // gli stream di ogni sorgente, risolti la prima volta che servono
            var resolved = new Dictionary<string, List<string>>();
            string good = null, lastError = null;
            bool everPlayed = false;
            int attempt = 0;
            try
            {
                while (!ct.IsCancellationRequested)
                {
                    bool played = false;
                    var candidates = new List<string>();
                    foreach (var source in sources)
                    {
                        if (!resolved.TryGetValue(source, out var streams))
                        {
                            try
                            {
                                Log.Write($"Risoluzione di {source}");
                                streams = await StreamResolver.ResolveAsync(source, direct && source == sources[0], ct).ConfigureAwait(false);
                                resolved[source] = streams;
                            }
                            catch (NetException e)
                            {
                                Log.Write($"  {source}: {e.Message}");
                                lastError = e.Message;
                                continue;
                            }
                        }
                        candidates.AddRange(streams);
                    }
                    if (good != null) { candidates.Remove(good); candidates.Insert(0, good); }
                    foreach (var url in candidates.Distinct().ToList())
                    {
                        if (ct.IsCancellationRequested) return;
                        var outcome = await PlayOneAsync(generation, url, StreamResolver.IsHls(url), ct).ConfigureAwait(false);
                        if (ct.IsCancellationRequested) return;
                        if (outcome.Error != null) lastError = outcome.Error;
                        if (outcome.Played)
                        {
                            played = everPlayed = true;
                            good = url;
                            break;
                        }
                    }
                    if (!everPlayed)
                    {
                        Fail(generation, lastError ?? "Impossibile riprodurre la stazione");
                        return;
                    }
                    if (played) attempt = 0;   // ha suonato e poi è caduta: si ricomincia a contare
                    if (attempt >= ReconnectDelays.Length)
                    {
                        Fail(generation, "Connessione persa" + (lastError != null ? ": " + lastError : ""));
                        return;
                    }
                    int delay = ReconnectDelays[attempt++];
                    Log.Write($"Connessione persa ({lastError}), nuovo tentativo tra {delay} s");
                    if (attempt == 1) Post(generation, () => Notice?.Invoke($"Connessione persa ({lastError}), riprovo…"));
                    SetState(generation, PlayerState.Connecting);
                    resolved.Clear();   // la playlist potrebbe essere cambiata
                    await Task.Delay(TimeSpan.FromSeconds(delay), ct).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException) { }
            catch (Exception e)
            {
                Log.Write("Errore inatteso nel lettore: " + e);
                Fail(generation, "Errore inatteso: " + e.Message);
            }
        }

        private void Fail(int generation, string message)
        {
            Log.Write("Lettore fermo: " + message);
            Post(generation, () =>
            {
                _session?.Cancel();
                _session = null;
                _volumeProvider = null;
                State = PlayerState.Stopped;
                StateChanged?.Invoke(State);
                Failed?.Invoke(message);
            });
        }

        /// <summary>Suona un indirizzo; se si scopre che è una playlist HLS si riparte in HLS.</summary>
        private async Task<Outcome> PlayOneAsync(int generation, string url, bool hls, CancellationToken ct)
        {
            bool switchToHls = false;
            var outcome = await PlayOnceAsync(generation, url, hls, ct, () => switchToHls = true).ConfigureAwait(false);
            if (!switchToHls || ct.IsCancellationRequested) return outcome;
            Log.Write("  è una playlist HLS: riparto in HLS");
            return await PlayOnceAsync(generation, url, true, ct, () => { }).ConfigureAwait(false);
        }

        /// <summary>Suona un indirizzo finché lo stream non finisce, cade o si cambia stazione.</summary>
        private async Task<Outcome> PlayOnceAsync(int generation, string url, bool hls, CancellationToken ct, Action needsHls)
        {
            var outcome = new Outcome();
            IStreamSource conn = null;
            AudioPipe pipe = null;
            IStreamDecoder decoder = null;
            WaveOutEvent output = null;
            string relayUrl = null;
            var decodeDone = new ManualResetEventSlim(false);
            try
            {
                SetState(generation, PlayerState.Connecting);
                try
                {
                    if (hls) conn = await HlsSource.OpenAsync(url, ct).ConfigureAwait(false);
                    else conn = await StreamConnection.OpenAsync(url, ct).ConfigureAwait(false);
                }
                catch (NetException e)
                {
                    Log.Write($"  {url}: {e.Message}");
                    outcome.Error = e.Message;
                    return outcome;
                }
                if (!hls && AudioFormat.FromContentType(conn.ContentType) == AudioKind.Hls)
                {
                    needsHls();   // playlist HLS senza estensione .m3u8
                    return outcome;
                }
                if (conn.StationName != null) { string name = conn.StationName; Post(generation, () => StationNameReceived?.Invoke(name)); }
                conn.CoverReceived += cover => Post(generation, () => CoverReceived?.Invoke(cover));
                conn.TitleReceived += title => Post(generation, () => TitleReceived?.Invoke(title));

                pipe = new AudioPipe();
                var connection = conn;
                var thePipe = pipe;
                new Thread(() => connection.Pump(thePipe)) { IsBackground = true, Name = "RadioTray rete" }.Start();

                // il formato: dal Content-Type, controllato sui primi byte
                var head = pipe.Peek(16384, TimeSpan.FromSeconds(15), ct);
                ct.ThrowIfCancellationRequested();
                if (head.Length == 0)
                {
                    outcome.Error = conn.LastError != null ? conn.LastError : "La radio non manda audio";
                    return outcome;
                }
                var declared = AudioFormat.FromContentType(conn.ContentType);
                var sniffed = AudioFormat.Sniff(head, head.Length);
                var kind = sniffed != AudioKind.Unknown ? sniffed : declared;
                Log.Write($"  formato: dichiarato {declared}, riconosciuto {sniffed}");
                switch (kind)
                {
                    case AudioKind.Html:
                        outcome.Error = NetMessages.ForHtmlInsteadOfAudio(conn.ViaProxy);
                        return outcome;
                    case AudioKind.Hls:
                        if (!hls) { needsHls(); return outcome; }
                        outcome.Error = "Playlist HLS non riconosciuta";
                        return outcome;
                    case AudioKind.Ogg:
                    case AudioKind.Flac:
                        outcome.Error = $"Formato {(kind == AudioKind.Ogg ? "Ogg Vorbis/Opus" : "FLAC")} non ancora supportato su Windows: serve l'indirizzo MP3 o AAC della radio";
                        return outcome;
                }

                // decodificatore: MP3 con il codec di Windows, il resto (AAC) con Media Foundation dal ripetitore interno
                string decoderError = null;
                var opened = new ManualResetEventSlim(false);
                var decoderThread = new Thread(() =>
                {
                    try
                    {
                        if (kind == AudioKind.Mp3)
                        {
                            try
                            {
                                decoder = new Mp3StreamDecoder(thePipe.AsStream());
                            }
                            catch (Exception e) when (!ct.IsCancellationRequested)
                            {
                                Log.Write("  codec MP3 di Windows non disponibile (" + e.Message + "), provo Media Foundation");
                            }
                        }
                        if (decoder == null)
                        {
                            string ext = kind == AudioKind.Mp3 ? "mp3" : "aac";
                            string mime = kind == AudioKind.Mp3 ? "audio/mpeg" : "audio/aac";
                            relayUrl = _relay.Value.Register(thePipe, ext, mime);
                            decoder = new MediaFoundationDecoder(relayUrl);
                        }
                    }
                    catch (Exception e)
                    {
                        decoderError = e.Message;
                    }
                    finally
                    {
                        opened.Set();
                    }
                }) { IsBackground = true, Name = "RadioTray apertura" };
                decoderThread.Start();
                if (!WaitHandle(opened.WaitHandle, TimeSpan.FromSeconds(25), ct))
                {
                    ct.ThrowIfCancellationRequested();
                    outcome.Error = "Il decodificatore audio non parte (tempo scaduto)";
                    return outcome;
                }
                if (decoder == null)
                {
                    outcome.Error = "Impossibile decodificare l'audio: " + (decoderError ?? "errore sconosciuto");
                    Log.Write("  " + outcome.Error);
                    return outcome;
                }
                Format = $"{(kind == AudioKind.Mp3 ? "MP3" : "AAC")}{(hls ? " (HLS)" : "")}{(conn.Bitrate != null ? " " + conn.Bitrate + " kbps" : "")}";
                Log.Write($"  decodifica con {decoder.Name}: {decoder.WaveFormat}");

                // decodifica → buffer di qualche secondo → uscita audio
                var buffered = new BufferedWaveProvider(decoder.WaveFormat)
                {
                    BufferDuration = TimeSpan.FromSeconds(10),
                    DiscardOnBufferOverflow = true,
                    ReadFully = true,
                };
                var dec = decoder;
                new Thread(() =>
                {
                    var chunk = new byte[dec.WaveFormat.AverageBytesPerSecond / 4 + 4096];
                    try
                    {
                        while (!ct.IsCancellationRequested)
                        {
                            while (buffered.BufferedDuration > MaxBufferTime && !ct.IsCancellationRequested) Thread.Sleep(50);
                            int n = dec.Read(chunk, 0, chunk.Length);
                            if (n <= 0) break;
                            buffered.AddSamples(chunk, 0, n);
                        }
                    }
                    catch (Exception e) when (!ct.IsCancellationRequested)
                    {
                        Log.Write("  errore di decodifica: " + e.Message);
                    }
                    catch (Exception) { }
                    decodeDone.Set();
                }) { IsBackground = true, Name = "RadioTray decodifica" }.Start();

                var until = DateTime.UtcNow + TimeSpan.FromSeconds(20);
                while (buffered.BufferedDuration < PrebufferTime && !decodeDone.IsSet && DateTime.UtcNow < until)
                    await Task.Delay(100, ct).ConfigureAwait(false);
                if (buffered.BufferedDuration == TimeSpan.Zero)
                {
                    outcome.Error = conn.LastError ?? "La radio non manda audio";
                    return outcome;
                }

                var volume = new VolumeSampleProvider(buffered.ToSampleProvider()) { Volume = _volume / 100f };
                output = new WaveOutEvent { DesiredLatency = 300, NumberOfBuffers = 3 };
                output.Init(new SampleToWaveProvider16(volume));
                output.Play();
                Post(generation, () => _volumeProvider = volume);
                outcome.Played = true;
                SetState(generation, PlayerState.Playing);
                Log.Write("  in riproduzione");

                // finché suona: si controlla che arrivino dati
                while (!ct.IsCancellationRequested)
                {
                    await Task.Delay(250, ct).ConfigureAwait(false);
                    if (decodeDone.IsSet && buffered.BufferedBytes == 0)
                    {
                        outcome.Error = conn.LastError ?? "lo stream si è interrotto";
                        break;
                    }
                    if (conn.SinceLastData > StallTimeout)
                    {
                        outcome.Error = "la radio non manda più dati";
                        Log.Write("  " + outcome.Error);
                        break;
                    }
                    if (output.PlaybackState == PlaybackState.Stopped)
                    {
                        outcome.Error = "l'uscita audio si è fermata";
                        Log.Write("  " + outcome.Error);
                        break;
                    }
                }
                return outcome;
            }
            catch (OperationCanceledException)
            {
                return outcome;
            }
            finally
            {
                try { output?.Stop(); } catch (Exception) { }
                try { output?.Dispose(); } catch (Exception) { }
                pipe?.Abort();
                conn?.Dispose();
                if (relayUrl != null) _relay.Value.Unregister(relayUrl);
                // il decodificatore si chiude quando ha smesso di leggere (Media Foundation non ama le chiusure a metà)
                var d = decoder;
                if (d != null)
                {
                    ThreadPool.QueueUserWorkItem(_ =>
                    {
                        decodeDone.Wait(TimeSpan.FromSeconds(5));
                        try { d.Dispose(); } catch (Exception) { }
                    });
                }
            }
        }

        private static bool WaitHandle(WaitHandle handle, TimeSpan timeout, CancellationToken ct) =>
            System.Threading.WaitHandle.WaitAny(new[] { handle, ct.WaitHandle }, timeout) == 0;

        public void Dispose()
        {
            Stop();
            if (_relay.IsValueCreated) _relay.Value.Dispose();
        }
    }
}
