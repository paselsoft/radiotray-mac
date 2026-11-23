using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace RadioTray
{
    /// <summary>"Cerca stazioni": l'archivio pubblico Radio Browser, attraverso il proxy.</summary>
    internal sealed class SearchWindow : Form
    {
        private readonly Action<string, string> _listen;     // nome, indirizzo
        private readonly Action<string, string> _add;        // nome, indirizzo
        private readonly TextBox _query = new TextBox { Width = 240 };
        private readonly ComboBox _mode = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 130 };
        private readonly ComboBox _country = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 130 };
        private readonly Button _go = new Button { Text = "Cerca", AutoSize = true };
        private readonly ListView _list = new ListView { View = View.Details, FullRowSelect = true, HideSelection = false, Dock = DockStyle.Fill, MultiSelect = false };
        private readonly Label _status = new Label { AutoSize = true, Anchor = AnchorStyles.Left, Padding = new Padding(0, 6, 0, 0) };
        private CancellationTokenSource _cts;

        public SearchWindow(Action<string, string> listen, Action<string, string> add)
        {
            _listen = listen;
            _add = add;
            Text = "Cerca stazioni - RadioTray";
            Icon = Icons.App;
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Font;
            Font = SystemFonts.MessageBoxFont;
            Size = new Size(880, 560);
            MinimumSize = new Size(600, 320);

            _mode.Items.AddRange(new object[] { "per nome", "per genere", "più ascoltate" });
            _mode.SelectedIndex = 0;
            _country.Items.AddRange(new object[] { "in Italia", "in tutto il mondo" });
            _country.SelectedIndex = 0;
            _mode.SelectedIndexChanged += (s, e) => _query.Enabled = _mode.SelectedIndex != 2;

            var top = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 40, Padding = new Padding(8, 8, 8, 0), WrapContents = false };
            top.Controls.AddRange(new Control[] { _query, _mode, _country, _go });
            _go.Click += (s, e) => Search();
            AcceptButton = _go;

            _list.Columns.Add("Nome", 300);
            _list.Columns.Add("Formato", 110);
            _list.Columns.Add("Paese", 60);
            _list.Columns.Add("Genere", 330);
            _list.DoubleClick += (s, e) => Listen();

            var bottom = new TableLayoutPanel { Dock = DockStyle.Bottom, Height = 44, ColumnCount = 2, Padding = new Padding(8, 6, 8, 6) };
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            var buttons = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Dock = DockStyle.Right };
            var listenButton = new Button { Text = "Ascolta", AutoSize = true };
            listenButton.Click += (s, e) => Listen();
            var addButton = new Button { Text = "Aggiungi alle stazioni…", AutoSize = true };
            addButton.Click += (s, e) => Add();
            var close = new Button { Text = "Chiudi", AutoSize = true };
            close.Click += (s, e) => Close();
            buttons.Controls.AddRange(new Control[] { listenButton, addButton, close });
            bottom.Controls.Add(_status, 0, 0);
            bottom.Controls.Add(buttons, 1, 0);
            CancelButton = close;

            Controls.Add(_list);
            Controls.Add(top);
            Controls.Add(bottom);
            _status.Text = "Scrivi il nome di una radio (per esempio \"Radio Italia\") o un genere (jazz, rock, news…). Doppio clic per ascoltare.";
            Shown += (s, e) => _query.Focus();
            FormClosed += (s, e) => _cts?.Cancel();
        }

        private FoundStation SelectedStation => _list.SelectedItems.Count > 0 ? (FoundStation)_list.SelectedItems[0].Tag : null;

        private void Listen()
        {
            var s = SelectedStation;
            if (s == null) return;
            if (!s.Playable && MessageBox.Show(this, $"Il formato {s.Codec} non si può ancora ascoltare su Windows. Provare lo stesso?", Text,
                                               MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            _listen(s.Name, s.Url);
        }

        private void Add()
        {
            var s = SelectedStation;
            if (s != null) _add(s.Name, s.Url);
        }

        private async void Search()
        {
            var mode = (RadioBrowser.Mode)_mode.SelectedIndex;
            string text = _query.Text.Trim();
            if (mode != RadioBrowser.Mode.Top && text.Length == 0) { _query.Focus(); return; }
            string country = _country.SelectedIndex == 0 ? "IT" : null;
            _cts?.Cancel();
            var cts = new CancellationTokenSource();
            _cts = cts;
            _go.Enabled = false;
            _status.Text = "Ricerca in corso…";
            _list.Items.Clear();
            try
            {
                var found = await Task.Run(() => Query(mode, text, country, cts.Token));
                string note = "";
                if (found != null && found.Count == 0 && mode == RadioBrowser.Mode.Name)
                {
                    // niente col nome scritto: sigle e nomi corti (RMC, RDS, Subasio…)
                    foreach (var alt in RadioBrowser.AlternativeNames(text))
                    {
                        if (cts.IsCancellationRequested) return;
                        _status.Text = $"Nessun risultato per \"{text}\", provo \"{alt}\"…";
                        found = await Task.Run(() => Query(mode, alt, country, cts.Token));
                        if (found == null || found.Count > 0) { note = $" (cercato come \"{alt}\")"; break; }
                    }
                }
                if (cts.IsCancellationRequested) return;
                if (found == null)
                {
                    _status.Text = "L'archivio delle stazioni non risponde. Riprova tra poco.";
                    return;
                }
                _list.BeginUpdate();
                foreach (var s in found)
                {
                    var item = new ListViewItem(new[] { s.Name, s.FormatDescription, s.Country, s.Tags }) { Tag = s };
                    if (!s.Playable) { item.ForeColor = SystemColors.GrayText; item.ToolTipText = "Formato non ancora supportato su Windows"; }
                    _list.Items.Add(item);
                }
                _list.EndUpdate();
                if (_list.Items.Count > 0) _list.Items[0].Selected = true;
                int bad = found.Count(s => !s.Playable);
                _status.Text = found.Count == 0 ? "Nessuna stazione trovata." :
                    $"{found.Count} stazioni{note}" + (bad > 0 ? $", in grigio {bad} in formati non ancora supportati" : "") + ". Doppio clic per ascoltare.";
            }
            finally
            {
                if (_cts == cts) _go.Enabled = true;
            }
        }

        /// <summary>La ricerca su un server dell'archivio, poi sugli altri se non risponde. Null se nessuno risponde.</summary>
        private static List<FoundStation> Query(RadioBrowser.Mode mode, string text, string country, CancellationToken ct)
        {
            foreach (var server in RadioBrowser.Servers)
            {
                if (ct.IsCancellationRequested) return null;
                try
                {
                    var uri = new Uri(RadioBrowser.SearchUrl(server, mode, text, country));
                    using (var r = Net.GetHeadersAsync(uri, false, TimeSpan.FromSeconds(12), ct).GetAwaiter().GetResult())
                    {
                        if (!r.IsSuccessStatusCode) { Log.Write($"Radio Browser {server}: HTTP {(int)r.StatusCode}"); continue; }
                        var list = RadioBrowser.StationsFromJson(r.Content.ReadAsStringAsync().GetAwaiter().GetResult());
                        if (list != null) return list;
                    }
                }
                catch (Exception e) when (!(e is OperationCanceledException))
                {
                    Log.Write($"Radio Browser {server} non disponibile: {e.Message}");
                }
                catch (OperationCanceledException) { return null; }
            }
            return null;
        }
    }
}
