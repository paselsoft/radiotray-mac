using System;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace RadioTray
{
    /// <summary>
    /// Legge ogni 20 secondi il servizio "in onda" delle radio che non mandano i titoli nello stream
    /// (Deejay, Capital, m2o), attraverso il proxy come il resto. Gli eventi arrivano sul thread dell'interfaccia.
    /// </summary>
    internal sealed class OnAirPoller : IDisposable
    {
        private static readonly TimeSpan Interval = TimeSpan.FromSeconds(20);
        private readonly SynchronizationContext _ui;
        private CancellationTokenSource _cts;

        /// <summary>(titolo, artista); artista vuoto = nome del programma.</summary>
        public event Action<string, string> Song;

        public OnAirPoller(SynchronizationContext ui) { _ui = ui; }

        public void Start(string serviceUrl)
        {
            Stop();
            var cts = new CancellationTokenSource();
            _cts = cts;
            Log.Write("Titoli dal servizio " + new Uri(serviceUrl).Host);
            Task.Run(() => Loop(serviceUrl, cts.Token));
        }

        public void Stop()
        {
            _cts?.Cancel();
            _cts = null;
        }

        private async Task Loop(string url, CancellationToken ct)
        {
            string last = null;
            int errors = 0;
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    using (var r = await Net.GetHeadersAsync(new Uri(url), false, TimeSpan.FromSeconds(15), ct).ConfigureAwait(false))
                    {
                        if (r.IsSuccessStatusCode)
                        {
                            string json = await r.Content.ReadAsStringAsync().ConfigureAwait(false);
                            var song = OnAir.SongFromGediJson(json);
                            string key = song == null ? null : song.Value.title + "\n" + song.Value.artist;
                            if (song != null && key != last && !ct.IsCancellationRequested)
                            {
                                last = key;
                                var s = song.Value;
                                _ui.Post(_ => { if (!ct.IsCancellationRequested) Song?.Invoke(s.title, s.artist); }, null);
                            }
                            errors = 0;
                        }
                        else if (++errors == 3) Log.Write($"Servizio dei titoli: HTTP {(int)r.StatusCode}");
                    }
                }
                catch (OperationCanceledException) { return; }
                catch (Exception e)
                {
                    if (++errors == 3) Log.Write("Servizio dei titoli non raggiungibile: " + e.Message);
                }
                try { await Task.Delay(Interval, ct).ConfigureAwait(false); }
                catch (OperationCanceledException) { return; }
            }
        }

        public void Dispose() => Stop();
    }
}
