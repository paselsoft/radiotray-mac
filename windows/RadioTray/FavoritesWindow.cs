using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace RadioTray
{
    /// <summary>Brani preferiti: ricerca istantanea, filtro per stazione, ordinamento, ricerca sul web, CSV.</summary>
    internal sealed class FavoritesWindow : Form
    {
        private readonly Func<FavoriteTracks> _tracks;
        private readonly Action<IEnumerable<FavoriteTrack>> _remove;
        private readonly TextBox _search = new TextBox { Width = 260 };
        private readonly ComboBox _station = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 };
        private readonly ListView _list = new ListView { View = View.Details, FullRowSelect = true, HideSelection = false, Dock = DockStyle.Fill, GridLines = false };
        private readonly Label _status = new Label { AutoSize = true, Anchor = AnchorStyles.Left, Padding = new Padding(0, 6, 0, 0) };
        private const string AllStations = "Tutte le stazioni";

        public FavoritesWindow(Func<FavoriteTracks> tracks, Action<IEnumerable<FavoriteTrack>> remove)
        {
            _tracks = tracks;
            _remove = remove;
            Text = "Brani preferiti - RadioTray";
            Icon = Icons.App;
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Font;
            Font = SystemFonts.MessageBoxFont;
            Size = new Size(860, 560);
            MinimumSize = new Size(520, 320);
            KeyPreview = true;

            var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 38, Padding = new Padding(8, 8, 8, 0), WrapContents = false };
            top.Controls.Add(new Label { Text = "Cerca:", AutoSize = true, Padding = new Padding(0, 4, 0, 0) });
            top.Controls.Add(_search);
            top.Controls.Add(new Label { Text = "  Stazione:", AutoSize = true, Padding = new Padding(0, 4, 0, 0) });
            top.Controls.Add(_station);

            _list.Columns.Add("Titolo", 260);
            _list.Columns.Add("Artista", 200);
            _list.Columns.Add("Stazione", 170);
            _list.Columns.Add("Aggiunto il", 130);
            var sorter = new Ui.ColumnSorter { Column = 3, Descending = true };
            sorter.Key = (item, col) => col == 3 ? (IComparable)((FavoriteTrack)item.Tag).Added : item.SubItems[col].Text;
            sorter.Attach(_list);
            _list.DoubleClick += (s, e) => SearchWeb(TrackSearchSite.YouTube);
            _list.ContextMenuStrip = BuildContextMenu();

            var bottom = new TableLayoutPanel { Dock = DockStyle.Bottom, Height = 44, ColumnCount = 2, Padding = new Padding(8, 6, 8, 6) };
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            var buttons = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Dock = DockStyle.Right };
            var youtube = new Button { Text = "Cerca su YouTube", AutoSize = true };
            youtube.Click += (s, e) => SearchWeb(TrackSearchSite.YouTube);
            var csv = new Button { Text = "Esporta CSV…", AutoSize = true };
            csv.Click += (s, e) => ExportCsv();
            var delete = new Button { Text = "Elimina", AutoSize = true };
            delete.Click += (s, e) => DeleteSelected();
            var close = new Button { Text = "Chiudi", AutoSize = true };
            close.Click += (s, e) => Close();
            buttons.Controls.AddRange(new Control[] { youtube, csv, delete, close });
            bottom.Controls.Add(_status, 0, 0);
            bottom.Controls.Add(buttons, 1, 0);
            CancelButton = close;

            Controls.Add(_list);
            Controls.Add(top);
            Controls.Add(bottom);

            _search.TextChanged += (s, e) => Fill();
            _station.SelectedIndexChanged += (s, e) => Fill();
            KeyDown += (s, e) =>
            {
                if (e.KeyCode == Keys.Delete && _list.Focused) { DeleteSelected(); e.Handled = true; }
                else if (e.Control && e.KeyCode == Keys.C && _list.Focused) { Copy(); e.Handled = true; }
                else if (e.Control && e.KeyCode == Keys.F) { _search.Focus(); e.Handled = true; }
            };
            Refill();
        }

        /// <summary>Da chiamare quando i preferiti cambiano mentre la finestra è aperta.</summary>
        public void Refill()
        {
            string selected = _station.SelectedItem as string;
            _station.BeginUpdate();
            _station.Items.Clear();
            _station.Items.Add(AllStations);
            foreach (var s in _tracks().Stations()) _station.Items.Add(s);
            _station.SelectedItem = selected != null && _station.Items.Contains(selected) ? selected : AllStations;
            _station.EndUpdate();
            Fill();
        }

        private void Fill()
        {
            string station = _station.SelectedItem as string;
            var tracks = _tracks().Matching(_search.Text, station == AllStations ? null : station);
            _list.BeginUpdate();
            _list.Items.Clear();
            foreach (var t in tracks)
            {
                var item = new ListViewItem(new[] { t.Title, t.Artist, t.Station, t.Added.Year > 1970 ? t.Added.ToLocalTime().ToString("dd/MM/yyyy HH:mm") : "" }) { Tag = t };
                _list.Items.Add(item);
            }
            _list.EndUpdate();
            int total = _tracks().Tracks.Count;
            _status.Text = tracks.Count == total ? $"{total} brani" : $"{tracks.Count} di {total} brani";
        }

        private List<FavoriteTrack> Selected() => _list.SelectedItems.Cast<ListViewItem>().Select(i => (FavoriteTrack)i.Tag).ToList();

        private ContextMenuStrip BuildContextMenu()
        {
            var m = new ContextMenuStrip();
            m.Items.Add("Cerca su YouTube", null, (s, e) => SearchWeb(TrackSearchSite.YouTube));
            m.Items.Add("Cerca su YouTube Music", null, (s, e) => SearchWeb(TrackSearchSite.YouTubeMusic));
            m.Items.Add("Cerca su Spotify", null, (s, e) => SearchWeb(TrackSearchSite.Spotify));
            m.Items.Add("Cerca su Apple Music", null, (s, e) => SearchWeb(TrackSearchSite.AppleMusic));
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add("Copia", null, (s, e) => Copy());
            m.Items.Add("Elimina", null, (s, e) => DeleteSelected());
            m.Opening += (s, e) => e.Cancel = _list.SelectedItems.Count == 0;
            return m;
        }

        private void SearchWeb(TrackSearchSite site)
        {
            var t = Selected().FirstOrDefault();
            if (t != null) Ui.OpenInBrowser(FavoriteTracks.SearchUrl(t, site), this);
        }

        private void Copy()
        {
            var sel = Selected();
            if (sel.Count == 0) return;
            try { Clipboard.SetText(string.Join(Environment.NewLine, sel.Select(t => t.DisplayText))); } catch (Exception) { }
        }

        private void DeleteSelected()
        {
            var sel = Selected();
            if (sel.Count == 0) return;
            if (sel.Count > 1 && MessageBox.Show(this, $"Eliminare {sel.Count} brani dai preferiti?", Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;
            _remove(sel);
            Refill();
        }

        private void ExportCsv()
        {
            using (var dialog = new SaveFileDialog
            {
                Title = "Esporta i brani preferiti",
                Filter = "CSV per Excel (*.csv)|*.csv",
                FileName = "Brani preferiti.csv",
                InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            })
            {
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                try
                {
                    var tracks = _list.Items.Cast<ListViewItem>().Select(i => (FavoriteTrack)i.Tag);
                    System.IO.File.WriteAllText(dialog.FileName, FavoriteTracks.Csv(tracks), new System.Text.UTF8Encoding(false));
                    _status.Text = "Esportato: " + dialog.FileName;
                }
                catch (Exception e)
                {
                    MessageBox.Show(this, "Impossibile salvare il file:\n" + e.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
        }
    }
}
