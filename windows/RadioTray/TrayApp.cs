using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace RadioTray
{
    /// <summary>L'icona nell'area di notifica con il suo menu: l'equivalente dell'icona nella barra dei menu del Mac.</summary>
    internal sealed class TrayApp : ApplicationContext
    {
        private const int MenuLineLength = 60;

        private readonly SynchronizationContext _ui;
        private readonly NotifyIcon _icon;
        private readonly ContextMenuStrip _menu;
        private readonly Player _player;
        private readonly Settings _settings;
        private Bookmarks _bookmarks = new Bookmarks();
        private FileSystemWatcher _watcher;
        private readonly System.Windows.Forms.Timer _reloadTimer = new System.Windows.Forms.Timer { Interval = 700 };
        private bool _diagnosing;

        // la stazione attuale (anche quando è spenta: è quella che si riaccende)
        private string _group, _station, _url;
        private bool _direct, _notifications = true;
        private List<string> _mirrors = new List<string>();
        private bool _openedUrl;   // aperta con "Apri indirizzo…", non è nell'elenco
        private TrackInfo _track = TrackInfo.Create(null, null);

        public TrayApp()
        {
            if (!(SynchronizationContext.Current is WindowsFormsSynchronizationContext))
                SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());
            _ui = SynchronizationContext.Current;

            AppPaths.Ensure();
            _settings = Settings.Load();
            _player = new Player(_ui) { Volume = _settings.Volume };
            _player.StateChanged += OnStateChanged;
            _player.TitleReceived += OnTitle;
            _player.StationNameReceived += OnStationName;
            _player.Failed += message => Notify("Errore", (_station != null ? _station + ": " : "") + message, ToolTipIcon.Warning, force: true);
            _player.Notice += message => Notify(_station ?? "RadioTray", message, ToolTipIcon.Info);

            _menu = new ContextMenuStrip { ShowImageMargin = false, ShowCheckMargin = true };
            _menu.Opening += (s, e) => { BuildMenu(); e.Cancel = false; };
            _menu.Closed += (s, e) => _settings.Save();
            _icon = new NotifyIcon { Icon = Icons.Off, Text = "RadioTray", ContextMenuStrip = _menu, Visible = true };
            _icon.MouseUp += OnIconClick;
            _icon.BalloonTipClicked += (s, e) => ShowMenu();

            _reloadTimer.Tick += (s, e) => { _reloadTimer.Stop(); LoadBookmarks(true); };
            LoadBookmarks(false);
            WatchBookmarks();
            RestoreLastStation();
            BuildMenu();
            UpdateTooltip();

            if (_settings.PlayOnStart && _url != null) Play();
            Task.Run(() => Log.Write($"Proxy per Internet: {Net.ProxyFor(new Uri("https://ice1.somafm.com/")) ?? "nessuno (connessione diretta)"}"));
        }

        #region Stazioni

        private void EnsureBookmarksFile()
        {
            if (File.Exists(AppPaths.Bookmarks)) return;
            using (var s = typeof(TrayApp).Assembly.GetManifestResourceStream("bookmarks.json"))
            using (var f = File.Create(AppPaths.Bookmarks))
                s.CopyTo(f);
            Log.Write("Creato " + AppPaths.Bookmarks + " con le stazioni predefinite");
        }

        private void LoadBookmarks(bool announce)
        {
            try
            {
                EnsureBookmarksFile();
            }
            catch (Exception e)
            {
                Log.Write("Impossibile creare il file delle stazioni: " + e.Message);
            }
            var b = Bookmarks.FromFile(AppPaths.Bookmarks, out string error);
            if (b == null)
            {
                Log.Write("Stazioni non caricate: " + error);
                Notify("Errore nel file delle stazioni", error, ToolTipIcon.Warning, force: true);
                return;
            }
            _bookmarks = b;
            Log.Write($"Caricate {b.StationCount} stazioni in {b.Groups.Count} gruppi");
            if (announce) Notify("Stazioni ricaricate", $"{b.StationCount} stazioni", ToolTipIcon.Info);
            // se la stazione attuale è cambiata nel file (per esempio l'indirizzo), la si aggiorna
            if (!_openedUrl && _station != null)
            {
                var st = _bookmarks.StationNamed(_station, _group);
                if (st != null) SetStation(_group, st);
            }
        }

        private void WatchBookmarks()
        {
            try
            {
                _watcher = new FileSystemWatcher(AppPaths.Folder, "bookmarks.json")
                {
                    NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size,
                };
                FileSystemEventHandler changed = (s, e) => _ui.Post(_ => { _reloadTimer.Stop(); _reloadTimer.Start(); }, null);
                _watcher.Changed += changed;
                _watcher.Created += changed;
                _watcher.Renamed += (s, e) => changed(s, e);
                _watcher.EnableRaisingEvents = true;
            }
            catch (Exception e)
            {
                Log.Write("Impossibile sorvegliare il file delle stazioni: " + e.Message);
            }
        }

        private void RestoreLastStation()
        {
            var st = _settings.LastGroup != null && _settings.LastStation != null
                ? _bookmarks.StationNamed(_settings.LastStation, _settings.LastGroup) : null;
            if (st != null)
            {
                SetStation(_settings.LastGroup, st);
            }
            else
            {
                var first = _bookmarks.Groups.SelectMany(g => g.Stations.Select(s => (g, s))).FirstOrDefault();
                if (first.s != null) SetStation(first.g.Name, first.s);
            }
        }

        private void SetStation(string group, Station st)
        {
            _group = group;
            _station = st.Name;
            _url = st.Url;
            _direct = st.Direct;
            _notifications = st.Notifications;
            _mirrors = st.Mirrors.ToList();
            _openedUrl = false;
        }

        private IEnumerable<(Group group, Station station)> AllStations() =>
            _bookmarks.Groups.Where(g => !g.IsRoot).Concat(_bookmarks.Groups.Where(g => g.IsRoot))
                .SelectMany(g => g.Stations.Select(s => (g, s)));

        private void PlayStation(string group, Station st)
        {
            SetStation(group, st);
            _settings.LastGroup = group;
            _settings.LastStation = st.Name;
            _settings.Save();
            Play();
        }

        private void Play()
        {
            if (_url == null) return;
            _track = TrackInfo.Create(null, null);
            Log.Write($"Accendo «{_station}» ({_url})");
            _player.Play(_url, _direct, _mirrors);
            UpdateTooltip();
        }

        private void Stop()
        {
            Log.Write("Spengo");
            _player.Stop();
            _track = TrackInfo.Create(null, null);
            UpdateTooltip();
        }

        private void TogglePlay()
        {
            if (_player.State == PlayerState.Stopped) Play();
            else Stop();
        }

        private void Step(int delta)
        {
            var all = AllStations().ToList();
            if (all.Count == 0) return;
            int index = all.FindIndex(x => x.group.Name == _group && x.station.Name == _station);
            index = index < 0 ? 0 : (index + delta + all.Count) % all.Count;
            PlayStation(all[index].group.Name, all[index].station);
        }

        private void OpenUrl()
        {
            string url = InputDialog.Ask("Apri indirizzo", "Indirizzo di una radio o di una playlist (.pls, .m3u…):", _settings.LastOpenedUrl);
            if (string.IsNullOrEmpty(url)) return;
            if (!url.Contains("://")) url = "http://" + url;
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
            {
                Notify("Errore", "Indirizzo non valido", ToolTipIcon.Warning, force: true);
                return;
            }
            _settings.LastOpenedUrl = url;
            _group = null;
            _station = uri.Host;
            _url = url;
            _direct = false;
            _notifications = true;
            _mirrors = new List<string>();
            _openedUrl = true;
            Play();
        }

        #endregion

        #region Lettore

        private void OnStateChanged(PlayerState state)
        {
            _icon.Icon = state == PlayerState.Stopped ? Icons.Off : Icons.On;
            if (state == PlayerState.Stopped) _track = TrackInfo.Create(null, null);
            UpdateTooltip();
        }

        private void OnStationName(string name)
        {
            // solo per gli indirizzi aperti a mano: le stazioni dell'elenco tengono il loro nome
            if (_openedUrl && !string.IsNullOrEmpty(name)) { _station = name; UpdateTooltip(); }
        }

        private void OnTitle(string raw)
        {
            var info = TrackInfo.FromStreamTitle(raw);
            if (info.IsFillerForStation(_station))
            {
                // jingle o pubblicità: la radio manda solo il proprio nome
                if (!_track.IsEmpty) { _track = TrackInfo.Create(null, null); UpdateTooltip(); }
                return;
            }
            if (info.IsEmpty || info.SameAs(_track)) return;
            _track = info;
            Log.Write($"Brano: {raw}");
            UpdateTooltip();
            if (_notifications) Notify(_station ?? "RadioTray", info.Text, ToolTipIcon.None);
        }

        #endregion

        #region Icona, notifiche e menu

        private void Notify(string title, string text, ToolTipIcon icon, bool force = false)
        {
            if (!force && !_settings.Notifications) return;
            _icon.ShowBalloonTip(5000, TrackInfo.Truncate(title, 63), TrackInfo.Truncate(string.IsNullOrEmpty(text) ? " " : text, 250), icon);
        }

        private void UpdateTooltip()
        {
            string text;
            switch (_player.State)
            {
                case PlayerState.Connecting:
                    text = $"Connessione a {_station}…";
                    break;
                case PlayerState.Playing:
                    text = _track.IsEmpty ? _station : _station + "\n" + _track.Title + (_track.Artist.Length > 0 ? " - " + _track.Artist : "");
                    break;
                default:
                    text = "RadioTray (spenta)";
                    break;
            }
            // NotifyIcon accetta al massimo 63 caratteri
            _icon.Text = TrackInfo.Truncate(text ?? "RadioTray", 63);
        }

        private void OnIconClick(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left) ShowMenu();
            else if (e.Button == MouseButtons.Middle) TogglePlay();
        }

        /// <summary>Apre il menu anche con il tasto sinistro (NotifyIcon lo fa da sé solo con il destro).</summary>
        private void ShowMenu()
        {
            var show = typeof(NotifyIcon).GetMethod("ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic);
            show?.Invoke(_icon, null);
        }

        private ToolStripMenuItem Item(string text, Action action, bool enabled = true)
        {
            var item = new ToolStripMenuItem(text) { Enabled = enabled };
            if (action != null) item.Click += (s, e) => action();
            return item;
        }

        private static string Truncate(string s) => TrackInfo.Truncate(s, MenuLineLength);

        /// <summary>Nei menu "&amp;" introduce una scorciatoia: si raddoppia per mostrarlo.</summary>
        private static string Escape(string s) => (s ?? "").Replace("&", "&&");

        private void BuildMenu()
        {
            _menu.SuspendLayout();
            foreach (ToolStripItem old in _menu.Items.Cast<ToolStripItem>().ToList()) old.Dispose();
            _menu.Items.Clear();
            var bold = new Font(_menu.Font, FontStyle.Bold);
            var state = _player.State;

            // brano in onda: clic per copiarlo
            if (state == PlayerState.Playing && !_track.IsEmpty)
            {
                var title = Item("♪ " + Escape(Truncate(_track.Title.Length > 0 ? _track.Title : _track.Artist)), CopyTrack);
                title.ToolTipText = "Clic per copiare titolo e artista";
                _menu.Items.Add(title);
                if (_track.Title.Length > 0 && _track.Artist.Length > 0)
                    _menu.Items.Add(Item("    " + Escape(Truncate(_track.Artist)), CopyTrack));
                _menu.Items.Add(new ToolStripSeparator());
            }

            string name = Escape(TrackInfo.Truncate(_station ?? "", 40));
            ToolStripMenuItem toggle;
            if (state == PlayerState.Stopped)
                toggle = Item(_station != null ? $"Accendi «{name}»" : "Accendi", Play, _url != null);
            else
                toggle = Item($"Spegni «{name}»", Stop);
            toggle.Font = bold;
            _menu.Items.Add(toggle);
            if (state == PlayerState.Connecting)
                _menu.Items.Add(Item("    Connessione…", null, false));
            else if (state == PlayerState.Playing && _player.Format != null)
                _menu.Items.Add(Item("    " + _player.Format, null, false));

            AddVolume();
            _menu.Items.Add(new ToolStripSeparator());

            // stazioni: i gruppi come sottomenu, poi le stazioni del gruppo "root"
            foreach (var g in _bookmarks.Groups.Where(g => !g.IsRoot))
            {
                var sub = new ToolStripMenuItem(Escape(g.Name));
                foreach (var st in g.Stations) sub.DropDownItems.Add(StationItem(g, st));
                if (g.Stations.Count == 0) sub.DropDownItems.Add(Item("(nessuna stazione)", null, false));
                if (!_openedUrl && g.Name == _group && state != PlayerState.Stopped) sub.Font = bold;
                _menu.Items.Add(sub);
            }
            foreach (var g in _bookmarks.Groups.Where(g => g.IsRoot))
                foreach (var st in g.Stations) _menu.Items.Add(StationItem(g, st));
            if (_bookmarks.StationCount == 0)
                _menu.Items.Add(Item("Nessuna stazione: Preferenze → Modifica stazioni…", null, false));

            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(Item("Stazione precedente", () => Step(-1), _bookmarks.StationCount > 0));
            _menu.Items.Add(Item("Stazione successiva", () => Step(+1), _bookmarks.StationCount > 0));
            _menu.Items.Add(Item("Apri indirizzo…", OpenUrl));
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(PreferencesMenu());
            _menu.Items.Add(Item("Informazioni su RadioTray", About));
            _menu.Items.Add(Item("Esci", Quit));
            _menu.ResumeLayout();
        }

        private ToolStripMenuItem StationItem(Group g, Station st)
        {
            var item = Item(Escape(Truncate(st.Name)), () => PlayStation(g.Name, st));
            item.Checked = !_openedUrl && g.Name == _group && st.Name == _station && _player.State != PlayerState.Stopped;
            return item;
        }

        private void AddVolume()
        {
            var label = new ToolStripLabel($"Volume {_player.Volume}%") { Margin = new Padding(20, 2, 0, 0) };
            var bar = new TrackBar
            {
                Minimum = 0,
                Maximum = 100,
                TickFrequency = 10,
                SmallChange = 5,
                LargeChange = 10,
                Value = _player.Volume,
                AutoSize = false,
                Width = 180,
                Height = 28,
                TickStyle = TickStyle.None,
                BackColor = SystemColors.Menu,
            };
            bar.ValueChanged += (s, e) =>
            {
                _player.Volume = bar.Value;
                _settings.Volume = bar.Value;
                label.Text = $"Volume {bar.Value}%";
            };
            _menu.Items.Add(label);
            _menu.Items.Add(new ToolStripControlHost(bar) { Margin = new Padding(14, 0, 4, 2), AutoSize = false, Width = 190, Height = 30 });
        }

        private ToolStripMenuItem PreferencesMenu()
        {
            var prefs = new ToolStripMenuItem("Preferenze");
            prefs.DropDownItems.Add(Item("Modifica stazioni…", () => Open("notepad.exe", AppPaths.Bookmarks)));
            prefs.DropDownItems.Add(Item("Ricarica stazioni", () => LoadBookmarks(true)));
            prefs.DropDownItems.Add(Item("Apri la cartella di RadioTray", () => Open("explorer.exe", AppPaths.Folder)));
            prefs.DropDownItems.Add(new ToolStripSeparator());
            var notifications = Item("Notifiche dei brani", () => { _settings.Notifications = !_settings.Notifications; _settings.Save(); });
            notifications.Checked = _settings.Notifications;
            prefs.DropDownItems.Add(notifications);
            var playOnStart = Item("Accendi l'ultima stazione all'avvio", () => { _settings.PlayOnStart = !_settings.PlayOnStart; _settings.Save(); });
            playOnStart.Checked = _settings.PlayOnStart;
            prefs.DropDownItems.Add(playOnStart);
            prefs.DropDownItems.Add(new ToolStripSeparator());
            prefs.DropDownItems.Add(Item(_diagnosing ? "Diagnostica di rete (in corso…)" : "Diagnostica di rete…", Diagnose, !_diagnosing));
            prefs.DropDownItems.Add(Item("Apri il registro", () => Open("notepad.exe", AppPaths.LogFile)));
            return prefs;
        }

        private void CopyTrack()
        {
            try
            {
                Clipboard.SetText(_track.Text);
                Notify("Copiato negli appunti", _track.Text, ToolTipIcon.Info, force: true);
            }
            catch (Exception e)
            {
                Log.Write("Appunti non disponibili: " + e.Message);
            }
        }

        private static void Open(string program, string path)
        {
            try
            {
                if (path == AppPaths.LogFile && !File.Exists(path)) Log.Write("Registro creato");
                Process.Start(program, "\"" + path + "\"");
            }
            catch (Exception e)
            {
                MessageBox.Show("Impossibile aprire " + path + ":\n" + e.Message, "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private void About()
        {
            string version = Application.ProductVersion;
            int plus = version.IndexOf('+');
            if (plus >= 0) version = version.Substring(0, plus);
            MessageBox.Show($"RadioTray {version} per Windows\n" +
                            "Radio via Internet nell'area di notifica, ispirato a Radiotray-NG.\n\n" +
                            $"Stazioni: {AppPaths.Bookmarks}\n" +
                            $"Registro: {AppPaths.LogFile}\n\n" +
                            "Il file delle stazioni è lo stesso della versione per Mac.\n" +
                            "Licenza GPL-3.0.",
                            "Informazioni su RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        #endregion

        #region Diagnostica

        /// <summary>Prova la rete attraverso il proxy e mostra (e copia negli appunti) un rapporto da girare a chi aiuta.</summary>
        private void Diagnose()
        {
            _diagnosing = true;
            string current = _url;
            Notify("Diagnostica di rete", "Prova in corso, ci vogliono pochi secondi…", ToolTipIcon.Info, force: true);
            Task.Run(async () =>
            {
                var sb = new StringBuilder();
                sb.AppendLine($"RadioTray {Application.ProductVersion} - {Environment.OSVersion} - .NET {Environment.Version} - {DateTime.Now:yyyy-MM-dd HH:mm}");
                var urls = new List<string>();
                if (current != null) urls.Add(current);
                urls.Add("https://ice1.somafm.com/groovesalad-128-mp3");
                urls.Add("http://icecast.unitedradio.it/Radio105.mp3");
                foreach (var u in urls.Distinct()) sb.AppendLine().Append(await Probe(u).ConfigureAwait(false));
                return sb.ToString();
            }).ContinueWith(t =>
            {
                _diagnosing = false;
                string report = t.IsFaulted ? "Diagnostica non riuscita: " + t.Exception?.GetBaseException().Message : t.Result;
                Log.Write("Diagnostica di rete:\n" + report);
                try { Clipboard.SetText(report); } catch (Exception) { }
                MessageBox.Show(report + "\n(Il rapporto è stato copiato negli appunti.)", "Diagnostica di rete",
                                MessageBoxButtons.OK, MessageBoxIcon.Information);
            }, TaskScheduler.FromCurrentSynchronizationContext());
        }

        private static async Task<string> Probe(string url)
        {
            var sb = new StringBuilder();
            sb.AppendLine(url);
            try
            {
                var uri = new Uri(url);
                sb.AppendLine("  proxy: " + (Net.ProxyFor(uri) ?? "nessuno (diretta)"));
                var watch = Stopwatch.StartNew();
                using (var cts = new CancellationTokenSource(TimeSpan.FromSeconds(20)))
                using (var r = await Net.GetHeadersAsync(uri, true, TimeSpan.FromSeconds(15), cts.Token).ConfigureAwait(false))
                {
                    sb.AppendLine($"  risposta: HTTP {(int)r.StatusCode} in {watch.ElapsedMilliseconds} ms, {Net.ContentType(r)}");
                    if (Net.Header(r, "icy-metaint") != null) sb.AppendLine("  titoli ICY: sì");
                    if (Net.Header(r, "Via") != null) sb.AppendLine("  Via: " + Net.Header(r, "Via"));
                    if ((int)r.StatusCode >= 400) return sb.ToString();
                    using (var s = await r.Content.ReadAsStreamAsync().ConfigureAwait(false))
                    using (cts.Token.Register(() => r.Dispose()))
                    {
                        var buf = new byte[16384];
                        long total = 0;
                        watch.Restart();
                        try
                        {
                            while (total < 128 * 1024 && watch.Elapsed < TimeSpan.FromSeconds(8))
                            {
                                int n = await s.ReadAsync(buf, 0, buf.Length, cts.Token).ConfigureAwait(false);
                                if (n <= 0) break;
                                total += n;
                            }
                        }
                        catch (Exception) when (total > 0) { }
                        double secs = Math.Max(0.001, watch.Elapsed.TotalSeconds);
                        sb.AppendLine($"  ricevuti {total / 1024} KB in {secs:0.0} s ({total * 8 / 1000 / secs:0} kbit/s)");
                    }
                }
            }
            catch (NetException e) { sb.AppendLine("  errore: " + e.Message); }
            catch (Exception e) { sb.AppendLine("  errore: " + e.Message); }
            return sb.ToString();
        }

        #endregion

        private void Quit()
        {
            _settings.Save();
            _player.Stop();
            _icon.Visible = false;
            ExitThread();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _watcher?.Dispose();
                _reloadTimer.Dispose();
                _player.Dispose();
                _icon.Dispose();
                _menu.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
