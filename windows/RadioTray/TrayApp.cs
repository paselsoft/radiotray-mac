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
        private readonly OnAirPoller _onAir;
        private FavoriteTracks _favorites = new FavoriteTracks();
        private FavoriteTracks _history = new FavoriteTracks();
        private FavoritesWindow _favoritesWindow;
        private SearchWindow _searchWindow;
        private StationEditor _stationEditor;
        private TrackInfo _balloonTrack;      // brano dell'ultima notifica: un clic lo aggiunge ai preferiti
        private const int HistoryLimit = 50;

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
            _onAir = new OnAirPoller(_ui);
            _onAir.Song += OnAirSong;

            _menu = new ContextMenuStrip { ShowImageMargin = false, ShowCheckMargin = true };
            _menu.Opening += (s, e) => { BuildMenu(); e.Cancel = false; };
            _menu.Closed += (s, e) => _settings.Save();
            _icon = new NotifyIcon { Icon = Icons.Off, Text = "RadioTray", ContextMenuStrip = _menu, Visible = true };
            _icon.MouseUp += OnIconClick;
            _icon.BalloonTipClicked += (s, e) => OnBalloonClicked();
            LoadTracks();

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
            string service = OnAir.ServiceUrl(_url);
            if (service != null) _onAir.Start(service);
            else _onAir.Stop();
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
            if (state == PlayerState.Stopped)
            {
                _track = TrackInfo.Create(null, null);
                _onAir.Stop();
            }
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
            if (StationIn(_settings.SwappedStations)) info = info.Swapped();   // stazione che scrive "Titolo - Artista"
            if (StationIn(_settings.IgnoredTitleStations) || info.IsFillerForStation(_station))
            {
                // jingle o pubblicità: la radio manda solo il proprio nome
                if (!_track.IsEmpty) { _track = TrackInfo.Create(null, null); UpdateTooltip(); }
                return;
            }
            if (info.IsEmpty || info.SameAs(_track)) return;
            _track = info;
            Log.Write($"Brano: {raw}");
            UpdateTooltip();
            NewTrack(info);
        }

        /// <summary>Brano dal servizio "in onda" (Deejay, Capital, m2o); senza artista è il nome del programma.</summary>
        private void OnAirSong(string title, string artist)
        {
            if (_player.State == PlayerState.Stopped || StationIn(_settings.IgnoredTitleStations)) return;
            var info = TrackInfo.Create(title, artist);
            if (StationIn(_settings.SwappedStations)) info = info.Swapped();
            if (info.IsEmpty || info.SameAs(_track)) return;
            _track = info;
            Log.Write($"Brano (servizio): {artist} - {title}");
            UpdateTooltip();
            if (artist.Length > 0) NewTrack(info);
        }

        /// <summary>Chiave della stazione attuale per le impostazioni per stazione.</summary>
        private string StationKey => _station == null ? null : _openedUrl ? "url\n" + _url : _group + "\n" + _station;

        private bool StationIn(List<string> list) => StationKey != null && list.Contains(StationKey);

        private void ToggleStation(List<string> list)
        {
            string key = StationKey;
            if (key == null) return;
            if (!list.Remove(key)) list.Add(key);
            _settings.Save();
        }

        #endregion

        #region Icona, notifiche e menu

        private void Notify(string title, string text, ToolTipIcon icon, bool force = false)
        {
            if (!force && !_settings.Notifications) return;
            _balloonTrack = null;
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
                bool favorite = _favorites.Find(_track.Title, _track.Artist) != null;
                var title = new ToolStripMenuItem((favorite ? "★ " : "♪ ") + Escape(Truncate(_track.Title.Length > 0 ? _track.Title : _track.Artist)));
                FillTrackMenu(title, favorite);
                _menu.Items.Add(title);
                if (_track.Title.Length > 0 && _track.Artist.Length > 0)
                {
                    var artistItem = new ToolStripMenuItem("    " + Escape(Truncate(_track.Artist)));
                    FillTrackMenu(artistItem, favorite);
                    _menu.Items.Add(artistItem);
                }
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
            if (state == PlayerState.Playing)
            {
                var swapped = Item("Titolo e artista al contrario per questa stazione", () =>
                {
                    ToggleStation(_settings.SwappedStations);
                    _track = _track.Swapped();
                    UpdateTooltip();
                });
                swapped.Checked = StationIn(_settings.SwappedStations);
                swapped.ToolTipText = "Per le radio che scrivono \"Titolo - Artista\" invece di \"Artista - Titolo\"";
                var ignore = Item("Ignora i titoli di questa stazione", () =>
                {
                    ToggleStation(_settings.IgnoredTitleStations);
                    if (StationIn(_settings.IgnoredTitleStations)) { _track = TrackInfo.Create(null, null); UpdateTooltip(); }
                });
                ignore.Checked = StationIn(_settings.IgnoredTitleStations);
                ignore.ToolTipText = "Per le radio che mandano titoli sbagliati o vecchi";
                var perStation = new ToolStripMenuItem("Titoli di questa stazione");
                perStation.DropDownItems.Add(swapped);
                perStation.DropDownItems.Add(ignore);
                _menu.Items.Add(perStation);
            }

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
            _menu.Items.Add(HistoryMenu());
            _menu.Items.Add(Item("Brani preferiti…", ShowFavorites));
            _menu.Items.Add(new ToolStripSeparator());
            _menu.Items.Add(Item("Cerca stazioni…", ShowSearch));
            _menu.Items.Add(Item("Apri indirizzo…", OpenUrl));
            if (_openedUrl && _url != null)
                _menu.Items.Add(Item($"Aggiungi «{Escape(TrackInfo.Truncate(_station, 30))}» alle stazioni…", () => AddToStations(_station, _url)));
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
            prefs.DropDownItems.Add(Item("Modifica stazioni…", ShowStationEditor));
            prefs.DropDownItems.Add(Item("Ricarica stazioni", () => LoadBookmarks(true)));
            prefs.DropDownItems.Add(Item("Apri la cartella di RadioTray", () => OpenFolder(AppPaths.Folder)));
            var backup = new ToolStripMenuItem("Backup");
            backup.DropDownItems.Add(Item("Esporta backup…", ExportBackup));
            backup.DropDownItems.Add(Item("Importa backup (anche dal Mac)…", ImportBackup));
            prefs.DropDownItems.Add(backup);
            prefs.DropDownItems.Add(new ToolStripSeparator());
            var notifications = Item("Notifiche dei brani", () => { _settings.Notifications = !_settings.Notifications; _settings.Save(); });
            notifications.Checked = _settings.Notifications;
            prefs.DropDownItems.Add(notifications);
            var playOnStart = Item("Accendi l'ultima stazione all'avvio", () => { _settings.PlayOnStart = !_settings.PlayOnStart; _settings.Save(); });
            playOnStart.Checked = _settings.PlayOnStart;
            prefs.DropDownItems.Add(playOnStart);
            prefs.DropDownItems.Add(new ToolStripSeparator());
            prefs.DropDownItems.Add(Item(_diagnosing ? "Diagnostica di rete (in corso…)" : "Diagnostica di rete…", Diagnose, !_diagnosing));
            prefs.DropDownItems.Add(Item("Apri il registro", ShowLog));
            return prefs;
        }

        #region Preferiti e cronologia

        private void LoadTracks()
        {
            _favorites = FavoriteTracks.FromFile(AppPaths.Favorites, out string e1) ?? new FavoriteTracks();
            if (e1 != null) Log.Write("Brani preferiti non leggibili: " + e1);
            _history = FavoriteTracks.FromFile(AppPaths.History, out string e2) ?? new FavoriteTracks();
            if (e2 != null) Log.Write("Ascoltati di recente non leggibili: " + e2);
        }

        private void SaveFavorites()
        {
            try { Ui.WriteText(AppPaths.Favorites, _favorites.ToJson()); }
            catch (Exception e) { Log.Write("Impossibile salvare i brani preferiti: " + e.Message); }
            if (_favoritesWindow != null && !_favoritesWindow.IsDisposed) _favoritesWindow.Refill();
        }

        private void SaveHistory()
        {
            try { Ui.WriteText(AppPaths.History, _history.ToJson()); }
            catch (Exception e) { Log.Write("Impossibile salvare gli ascoltati di recente: " + e.Message); }
        }

        /// <summary>Brano nuovo: cronologia e notifica (un clic sulla notifica lo aggiunge ai preferiti).</summary>
        private void NewTrack(TrackInfo info)
        {
            if (_history.Record(info.Title, info.Artist, _station ?? "", DateTime.UtcNow, HistoryLimit)) SaveHistory();
            if (!_notifications || !_settings.Notifications) return;
            bool favorite = _favorites.Find(info.Title, info.Artist) != null;
            Notify((favorite ? "★ " : "") + (_station ?? "RadioTray"), info.Text + (favorite ? "" : "\n(clic qui: ★ aggiungi ai preferiti)"), ToolTipIcon.None);
            _balloonTrack = favorite ? null : info;
        }

        private void OnBalloonClicked()
        {
            var t = _balloonTrack;
            _balloonTrack = null;
            if (t != null) AddFavorite(t.Title, t.Artist, _station);
            else ShowMenu();
        }

        private void AddFavorite(string title, string artist, string station)
        {
            var t = _favorites.Add(title, artist, station ?? "", DateTime.UtcNow, out bool present);
            if (!present) SaveFavorites();
            Notify(present ? "★ Già nei brani preferiti" : "★ Aggiunto ai brani preferiti", t.DisplayText, ToolTipIcon.Info, force: true);
        }

        private void FillTrackMenu(ToolStripMenuItem parent, bool favorite)
        {
            var track = _track;
            parent.DropDownItems.Add(favorite ? Item("★ Già nei brani preferiti", null, false)
                                              : Item("★ Aggiungi ai brani preferiti", () => AddFavorite(track.Title, track.Artist, _station)));
            parent.DropDownItems.Add(Item("Copia titolo e artista", CopyTrack));
            parent.DropDownItems.Add(Item("Cerca su YouTube", () =>
                Ui.OpenInBrowser(FavoriteTracks.SearchUrl(new FavoriteTrack { Title = track.Title, Artist = track.Artist }, TrackSearchSite.YouTube))));
            parent.DropDownItems.Add(new ToolStripSeparator());
            parent.DropDownItems.Add(Item("Brani preferiti…", ShowFavorites));
        }

        private ToolStripMenuItem HistoryMenu()
        {
            var menu = new ToolStripMenuItem("Ascoltati di recente");
            var recent = _history.Tracks.Reverse().Take(20).ToList();
            if (recent.Count == 0) menu.DropDownItems.Add(Item("(ancora nessun brano)", null, false));
            foreach (var t in recent)
            {
                bool favorite = _favorites.Find(t.Title, t.Artist) != null;
                var item = Item((favorite ? "★ " : "") + Escape(Truncate(t.DisplayText)), () => AddFavorite(t.Title, t.Artist, t.Station));
                item.ToolTipText = $"{t.Station}, {t.Added.ToLocalTime():HH:mm} — clic: aggiungi ai preferiti";
                menu.DropDownItems.Add(item);
            }
            return menu;
        }

        private void ShowFavorites()
        {
            if (_favoritesWindow == null || _favoritesWindow.IsDisposed)
                _favoritesWindow = new FavoritesWindow(() => _favorites, tracks => { _favorites.Remove(tracks); SaveFavorites(); });
            Ui.Bring(_favoritesWindow);
        }

        #endregion

        #region Ricerca ed editor delle stazioni

        /// <summary>Ascolta un indirizzo che non è nell'elenco (ricerca, prova dall'editor).</summary>
        private void PlayUrl(string name, string url)
        {
            _group = null;
            _station = string.IsNullOrEmpty(name) ? new Uri(url).Host : name;
            _url = url;
            _direct = false;
            _notifications = true;
            _mirrors = new List<string>();
            _openedUrl = true;
            Play();
        }

        private void ShowSearch()
        {
            if (_searchWindow == null || _searchWindow.IsDisposed) _searchWindow = new SearchWindow(PlayUrl, AddToStations);
            Ui.Bring(_searchWindow);
        }

        private void ShowStationEditor()
        {
            if (_stationEditor != null && !_stationEditor.IsDisposed) { Ui.Bring(_stationEditor); return; }
            string text;
            try
            {
                EnsureBookmarksFile();
                text = File.ReadAllText(AppPaths.Bookmarks, Encoding.UTF8);
            }
            catch (Exception e)
            {
                MessageBox.Show("Impossibile leggere il file delle stazioni:\n" + e.Message, "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if (BookmarksDocument.Parse(text, out string error) == null)
            {
                MessageBox.Show("Il file delle stazioni ha un errore e va corretto come testo:\n\n" + error, "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                EditBookmarks();
                return;
            }
            _stationEditor = new StationEditor(text, SaveBookmarks, PlayUrl, EditBookmarks);
            Ui.Bring(_stationEditor);
        }

        /// <summary>Aggiunge una stazione all'elenco chiedendo nome e gruppo.</summary>
        private void AddToStations(string name, string url)
        {
            BookmarksDocument doc;
            try
            {
                EnsureBookmarksFile();
                doc = BookmarksDocument.Parse(File.ReadAllText(AppPaths.Bookmarks, Encoding.UTF8), out string error);
                if (doc == null) { MessageBox.Show("Il file delle stazioni ha un errore:\n" + error, "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
            }
            catch (Exception e)
            {
                MessageBox.Show("Impossibile leggere il file delle stazioni:\n" + e.Message, "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if (doc.ContainsUrl(url) && MessageBox.Show($"Un'altra stazione ha già questo indirizzo:\n{url}\n\nAggiungerla lo stesso?", "RadioTray",
                                                         MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            var groups = doc.Groups.Where(g => !g.IsRoot).Select(g => g.Name).ToList();
            groups.Add("(senza gruppo)");
            while (true)
            {
                var r = Ui.AskFields("Aggiungi alle stazioni", "Aggiungi", new[]
                {
                    ("Nome della stazione:", name, (string[])null),
                    ("Gruppo (scegli o scrivi un nome nuovo):", _group != null && !_openedUrl ? _group : groups[0], groups.ToArray()),
                });
                if (r == null) return;
                var group = r[1].Length == 0 || r[1] == "(senza gruppo)" ? doc.RootGroup() : doc.GroupNamed(r[1]);
                string error = group == null ? doc.AddGroup(r[1], out group) : null;
                if (error == null) error = doc.AddStation(group, r[0], url, out _);
                if (error == null) error = SaveBookmarks(doc.ToJson());
                if (error == null)
                {
                    Notify("Stazione aggiunta", $"{r[0]} in \"{group.DisplayName}\"", ToolTipIcon.Info, force: true);
                    if (_openedUrl && _url == url)
                    {
                        // da ora è una stazione dell'elenco
                        _openedUrl = false;
                        _group = group.Name;
                        _station = r[0].Trim();
                        _settings.LastGroup = _group;
                        _settings.LastStation = _station;
                        _settings.Save();
                    }
                    return;
                }
                MessageBox.Show(error, "Aggiungi alle stazioni", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                name = r[0];
            }
        }

        #endregion

        #region Backup

        private Backup CurrentBackup()
        {
            var b = new Backup
            {
                AppVersion = "Windows " + Application.ProductVersion.Split('+')[0],
                Created = DateTime.UtcNow,
                Favorites = _favorites,
                History = _history,
            };
            try
            {
                if (File.Exists(AppPaths.Bookmarks) && Json.Parse(File.ReadAllText(AppPaths.Bookmarks, Encoding.UTF8)) is List<object> l) b.Bookmarks = l;
            }
            catch (Exception e) { Log.Write("Stazioni non incluse nel backup: " + e.Message); }
            // le impostazioni con i nomi della versione per Mac
            b.Settings[Backup.KeyVolume] = _settings.Volume;
            b.Settings[Backup.KeyNotifications] = _settings.Notifications;
            if (_settings.LastGroup != null) b.Settings[Backup.KeyLastGroup] = _settings.LastGroup;
            if (_settings.LastStation != null) b.Settings[Backup.KeyLastStation] = _settings.LastStation;
            if (_settings.LastOpenedUrl != null) b.Settings[Backup.KeyLastUrl] = _settings.LastOpenedUrl;
            b.Settings[Backup.KeySwapped] = _settings.SwappedStations.Cast<object>().ToList();
            b.Settings[Backup.KeyIgnored] = _settings.IgnoredTitleStations.Cast<object>().ToList();
            return b;
        }

        private void ExportBackup()
        {
            using (var dialog = new SaveFileDialog
            {
                Title = "Esporta backup di RadioTray",
                Filter = "Backup di RadioTray (*.json)|*.json",
                FileName = "RadioTray-backup.json",
                InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            })
            {
                if (dialog.ShowDialog() != DialogResult.OK) return;
                try
                {
                    var b = CurrentBackup();
                    File.WriteAllText(dialog.FileName, b.ToJson(), new UTF8Encoding(false));
                    Log.Write("Backup esportato in " + dialog.FileName);
                    MessageBox.Show($"Backup salvato:\n{dialog.FileName}\n\n{b.StationCount} stazioni, {b.Favorites.Tracks.Count} brani preferiti, " +
                                    $"{b.History.Tracks.Count} ascoltati di recente.\n\nSi può importare anche in RadioTray per Mac (Preferenze > Backup).",
                                    "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                catch (Exception e)
                {
                    MessageBox.Show("Impossibile salvare il backup:\n" + e.Message, "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
        }

        /// <summary>Importa un backup (del Mac o di Windows): aggiunge ciò che manca, non cancella niente.</summary>
        private void ImportBackup()
        {
            string path;
            using (var dialog = new OpenFileDialog
            {
                Title = "Importa backup di RadioTray",
                Filter = "Backup di RadioTray (*.json)|*.json|Tutti i file (*.*)|*.*",
                InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            })
            {
                if (dialog.ShowDialog() != DialogResult.OK) return;
                path = dialog.FileName;
            }
            Backup b;
            try { b = Backup.Parse(File.ReadAllText(path, Encoding.UTF8), out string error); if (b == null) throw new InvalidDataException(error); }
            catch (Exception e)
            {
                MessageBox.Show("Impossibile importare il backup:\n" + e.Message, "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            string from = (b.AppVersion != null ? $"RadioTray {b.AppVersion}" : "RadioTray") + (b.Created.HasValue ? $" del {b.Created.Value.ToLocalTime():dd/MM/yyyy HH:mm}" : "");
            if (MessageBox.Show($"Backup di {from}:\n{b.StationCount} stazioni, {b.Favorites.Tracks.Count} brani preferiti, {b.History.Tracks.Count} ascoltati di recente.\n\n" +
                                "Le stazioni e i brani che mancano vengono aggiunti; quelli che hai già restano come sono. Importare?",
                                "Importa backup", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;

            int stations = 0;
            if (b.Bookmarks != null)
            {
                try
                {
                    EnsureBookmarksFile();
                    var doc = BookmarksDocument.Parse(File.ReadAllText(AppPaths.Bookmarks, Encoding.UTF8), out string error) ?? BookmarksDocument.Empty();
                    var extra = Bookmarks.Parse(Json.Write(b.Bookmarks), out _);
                    stations = doc.Merge(extra);
                    if (stations > 0)
                    {
                        string saveError = SaveBookmarks(doc.ToJson());
                        if (saveError != null) throw new InvalidOperationException(saveError);
                    }
                }
                catch (Exception e)
                {
                    MessageBox.Show("Le stazioni non sono state importate:\n" + e.Message, "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    stations = 0;
                }
            }
            int favorites = _favorites.Merge(b.Favorites);
            if (favorites > 0) SaveFavorites();
            int history = _history.Merge(b.History);
            while (_history.Tracks.Count > HistoryLimit) _history.Remove(new[] { _history.Tracks[0] });
            if (history > 0) SaveHistory();
            foreach (var k in b.SettingStrings(Backup.KeySwapped)) if (!_settings.SwappedStations.Contains(k)) _settings.SwappedStations.Add(k);
            foreach (var k in b.SettingStrings(Backup.KeyIgnored)) if (!_settings.IgnoredTitleStations.Contains(k)) _settings.IgnoredTitleStations.Add(k);
            _settings.Save();
            Log.Write($"Backup importato da {path}: {stations} stazioni, {favorites} preferiti, {history} ascoltati");
            MessageBox.Show($"Importati: {stations} stazioni nuove, {favorites} brani preferiti nuovi, {history} ascoltati di recente.",
                            "Importa backup", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        #endregion

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

        private TextWindow _editor, _logWindow;

        private static void Bring(Form f)
        {
            if (f.WindowState == FormWindowState.Minimized) f.WindowState = FormWindowState.Normal;
            f.Show();
            f.Activate();
        }

        /// <summary>Editor interno di bookmarks.json: niente programmi esterni (la politica dell'ufficio può bloccarli).</summary>
        private void EditBookmarks()
        {
            if (_editor != null && !_editor.IsDisposed) { Bring(_editor); return; }
            string text;
            try
            {
                EnsureBookmarksFile();
                text = File.ReadAllText(AppPaths.Bookmarks, Encoding.UTF8);
            }
            catch (Exception e)
            {
                MessageBox.Show("Impossibile leggere il file delle stazioni:\n" + e.Message, "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            _editor = new TextWindow("Stazioni - RadioTray", text, SaveBookmarks,
                                     "Formato: [ { \"group\": \"Nome\", \"stations\": [ { \"name\": \"…\", \"url\": \"…\" } ] } ]   Ctrl+S salva");
            Bring(_editor);
        }

        /// <summary>Salva solo se il testo è un elenco di stazioni valido; tiene una copia della versione precedente.</summary>
        private string SaveBookmarks(string text)
        {
            if (Bookmarks.Parse(text, out string error) == null) return error;
            try
            {
                if (File.Exists(AppPaths.Bookmarks)) File.Copy(AppPaths.Bookmarks, AppPaths.Bookmarks + ".bak", true);
                File.WriteAllText(AppPaths.Bookmarks, text, new UTF8Encoding(false));
            }
            catch (Exception e)
            {
                return "Impossibile salvare: " + e.Message;
            }
            Log.Write("Stazioni modificate dall'editor interno");
            LoadBookmarks(false);
            return null;
        }

        private void ShowLog()
        {
            string text;
            try
            {
                using (var f = new FileStream(AppPaths.LogFile, FileMode.OpenOrCreate, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var r = new StreamReader(f, Encoding.UTF8))
                    text = r.ReadToEnd();
            }
            catch (Exception e)
            {
                text = "Impossibile leggere il registro: " + e.Message;
            }
            if (_logWindow != null && !_logWindow.IsDisposed) _logWindow.SetText(text);
            else _logWindow = new TextWindow("Registro - RadioTray", text, null, AppPaths.LogFile);
            Bring(_logWindow);
        }

        private static void OpenFolder(string path)
        {
            try
            {
                Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true });
            }
            catch (Exception e)
            {
                Log.Write("Impossibile aprire la cartella: " + e.Message);
                try { Clipboard.SetText(path); } catch (Exception) { }
                MessageBox.Show("Windows non permette di aprire la cartella da qui (" + e.Message + ").\n\n" +
                                "Il percorso è stato copiato negli appunti: incollalo nella barra degli indirizzi di Esplora file.\n\n" + path,
                                "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Information);
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
                _onAir.Dispose();
                _player.Dispose();
                _icon.Dispose();
                _menu.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
