using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace RadioTray
{
    /// <summary>
    /// Editor delle stazioni: gruppi e stazioni in un albero, nome/indirizzo/notifiche a destra, Salva controlla tutto.
    /// I campi che l'editor non conosce (mirrors, image…) restano com'erano.
    /// </summary>
    internal sealed class StationEditor : Form
    {
        private readonly Func<string, string> _save;       // testo JSON → errore oppure null
        private readonly Action<string, string> _listen;   // nome, indirizzo
        private readonly Action _editAsText;
        private BookmarksDocument _doc;
        private bool _dirty, _filling;

        private readonly TreeView _tree = new TreeView { Dock = DockStyle.Fill, HideSelection = false, ShowLines = true, FullRowSelect = true };
        private readonly TextBox _filter = new TextBox { Dock = DockStyle.Top };
        private readonly Label _nameLabel = new Label { Text = "Nome", AutoSize = true };
        private readonly TextBox _name = new TextBox { Width = 380 };
        private readonly Label _urlLabel = new Label { Text = "Indirizzo (stream o playlist .pls/.m3u/.m3u8)", AutoSize = true };
        private readonly TextBox _url = new TextBox { Width = 380 };
        private readonly CheckBox _notify = new CheckBox { Text = "Notifiche dei brani per questa stazione", AutoSize = true };
        private readonly Button _test = new Button { Text = "Prova", AutoSize = true };
        private readonly Label _status = new Label { AutoSize = true, Anchor = AnchorStyles.Left, Padding = new Padding(0, 6, 0, 0) };

        public StationEditor(string json, Func<string, string> save, Action<string, string> listen, Action editAsText)
        {
            _save = save;
            _listen = listen;
            _editAsText = editAsText;
            _doc = BookmarksDocument.Parse(json, out string error) ?? BookmarksDocument.Empty();
            Text = "Stazioni - RadioTray";
            Icon = Icons.App;
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Font;
            Font = SystemFonts.MessageBoxFont;
            Size = new Size(900, 600);
            MinimumSize = new Size(700, 420);

            var left = new Panel { Dock = DockStyle.Left, Width = 330, Padding = new Padding(8, 8, 4, 0) };
            var filterLabel = new Label { Text = "Cerca:", Dock = DockStyle.Top, Height = 18 };
            left.Controls.Add(_tree);
            left.Controls.Add(_filter);
            left.Controls.Add(filterLabel);

            var right = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, Padding = new Padding(12, 26, 8, 0), WrapContents = false, AutoScroll = true };
            right.Controls.AddRange(new Control[] { _nameLabel, _name, Spacer(), _urlLabel, _url, Spacer(), _notify, Spacer(), _test });

            var toolbar = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 40, Padding = new Padding(8, 6, 8, 0), WrapContents = false };
            Button B(string text, Action a)
            {
                var b = new Button { Text = text, AutoSize = true };
                b.Click += (s, e) => a();
                toolbar.Controls.Add(b);
                return b;
            }
            B("Nuovo gruppo…", NewGroup);
            B("Nuova stazione…", NewStation);
            B("Elimina", Delete);
            B("▲ Su", () => MoveSelected(-1));
            B("▼ Giù", () => MoveSelected(+1));
            B("Sposta nel gruppo…", MoveToGroup);

            var bottom = new TableLayoutPanel { Dock = DockStyle.Bottom, Height = 44, ColumnCount = 2, Padding = new Padding(8, 6, 8, 6) };
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            var buttons = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Dock = DockStyle.Right };
            var asText = new Button { Text = "Modifica come testo…", AutoSize = true };
            asText.Click += (s, e) => { if (ConfirmDiscard()) { _dirty = false; Close(); _editAsText(); } };
            var saveButton = new Button { Text = "Salva", AutoSize = true };
            saveButton.Click += (s, e) => Save();
            var close = new Button { Text = "Chiudi", AutoSize = true };
            close.Click += (s, e) => Close();
            buttons.Controls.AddRange(new Control[] { asText, saveButton, close });
            bottom.Controls.Add(_status, 0, 0);
            bottom.Controls.Add(buttons, 1, 0);

            Controls.Add(right);
            Controls.Add(left);
            Controls.Add(toolbar);
            Controls.Add(bottom);

            _tree.AfterSelect += (s, e) => ShowSelection();
            _filter.TextChanged += (s, e) => Fill(Selected);
            _name.Leave += (s, e) => ApplyName();
            _name.KeyDown += (s, e) => { if (e.KeyCode == Keys.Enter) { ApplyName(); e.SuppressKeyPress = true; } };
            _url.Leave += (s, e) => ApplyUrl();
            _url.KeyDown += (s, e) => { if (e.KeyCode == Keys.Enter) { ApplyUrl(); e.SuppressKeyPress = true; } };
            _notify.CheckedChanged += (s, e) =>
            {
                if (_filling || !(Selected is BookmarksDocument.DocStation st)) return;
                _doc.SetNotifications(st, _notify.Checked);
                Changed();
            };
            _test.Click += (s, e) =>
            {
                ApplyUrl();
                if (Selected is BookmarksDocument.DocStation st) _listen(st.Name, st.Url);
            };
            KeyPreview = true;
            KeyDown += (s, e) => { if (e.Control && e.KeyCode == Keys.S) { Save(); e.SuppressKeyPress = true; } };
            FormClosing += (s, e) => { if (!ConfirmDiscard()) e.Cancel = true; };

            Fill(null);
            _status.Text = error != null ? "Il file attuale ha un errore: " + error : $"{_doc.Groups.Sum(g => g.Stations.Count)} stazioni. Le modifiche valgono dopo \"Salva\" (Ctrl+S).";
        }

        private static Control Spacer() => new Panel { Height = 10, Width = 1 };

        private object Selected => _tree.SelectedNode?.Tag;

        private void Changed()
        {
            _dirty = true;
            if (!Text.StartsWith("*")) Text = "* " + Text;
        }

        private void Fill(object select)
        {
            string f = FavoriteTracks.Fold(_filter.Text.Trim());
            _tree.BeginUpdate();
            _tree.Nodes.Clear();
            TreeNode toSelect = null;
            foreach (var g in _doc.Groups)
            {
                var stations = g.Stations.Where(s => f.Length == 0 || FavoriteTracks.Fold(s.Name + " " + s.Url).Contains(f)).ToList();
                if (f.Length > 0 && stations.Count == 0 && !FavoriteTracks.Fold(g.Name).Contains(f)) continue;
                var gn = new TreeNode(g.DisplayName) { Tag = g, NodeFont = new Font(_tree.Font, FontStyle.Bold) };
                gn.Text = g.DisplayName;   // ricalcola la larghezza con il grassetto
                foreach (var s in stations)
                {
                    var sn = new TreeNode(s.Name) { Tag = s };
                    gn.Nodes.Add(sn);
                    if (select is BookmarksDocument.DocStation ss && ss.Equals(s)) toSelect = sn;
                }
                _tree.Nodes.Add(gn);
                if (select is BookmarksDocument.DocGroup sg && sg.Name == g.Name) toSelect = gn;
            }
            _tree.ExpandAll();
            _tree.EndUpdate();
            _tree.SelectedNode = toSelect ?? (_tree.Nodes.Count > 0 ? _tree.Nodes[0] : null);
            ShowSelection();
        }

        private void ShowSelection()
        {
            _filling = true;
            var sel = Selected;
            bool station = sel is BookmarksDocument.DocStation;
            _nameLabel.Text = station ? "Nome della stazione" : "Nome del gruppo";
            _name.Enabled = sel != null && !(sel is BookmarksDocument.DocGroup g0 && g0.IsRoot);
            _name.Text = sel is BookmarksDocument.DocStation s ? s.Name : sel is BookmarksDocument.DocGroup g ? g.DisplayName : "";
            _urlLabel.Visible = _url.Visible = _notify.Visible = _test.Visible = station;
            if (sel is BookmarksDocument.DocStation st)
            {
                _url.Text = st.Url;
                _notify.Checked = st.Notifications;
            }
            _filling = false;
        }

        private void Error(string message)
        {
            _status.ForeColor = Color.Firebrick;
            _status.Text = message;
        }

        private void Info(string message)
        {
            _status.ForeColor = SystemColors.ControlText;
            _status.Text = message;
        }

        private void ApplyName()
        {
            if (_filling) return;
            var sel = Selected;
            string error = null;
            if (sel is BookmarksDocument.DocStation s && _name.Text.Trim() != s.Name) { error = _doc.RenameStation(s, _name.Text); if (error == null) { Changed(); _tree.SelectedNode.Text = s.Name; } }
            else if (sel is BookmarksDocument.DocGroup g && !g.IsRoot && _name.Text.Trim() != g.Name) { error = _doc.RenameGroup(g, _name.Text); if (error == null) { Changed(); _tree.SelectedNode.Text = g.DisplayName; } }
            if (error != null) { Error(error); ShowSelection(); }
        }

        private void ApplyUrl()
        {
            if (_filling || !(Selected is BookmarksDocument.DocStation s) || _url.Text.Trim() == s.Url) return;
            string error = _doc.SetUrl(s, _url.Text);
            if (error != null) { Error(error); ShowSelection(); }
            else Changed();
        }

        private BookmarksDocument.DocGroup SelectedGroup =>
            Selected is BookmarksDocument.DocStation s ? s.Group : Selected as BookmarksDocument.DocGroup;

        private void NewGroup()
        {
            var r = Ui.AskFields("Nuovo gruppo", "Crea", new[] { ("Nome del gruppo:", "", (string[])null) });
            if (r == null) return;
            string error = _doc.AddGroup(r[0], out var g);
            if (error != null) { Error(error); return; }
            Changed();
            Fill(g);
            Info($"Creato il gruppo \"{g.Name}\".");
        }

        private void NewStation()
        {
            var groups = _doc.Groups.Where(g => !g.IsRoot).Select(g => g.Name).ToList();
            groups.Add("(senza gruppo)");
            string current = SelectedGroup?.DisplayName ?? groups.FirstOrDefault() ?? "";
            var r = Ui.AskFields("Nuova stazione", "Aggiungi", new[]
            {
                ("Nome della stazione:", "", (string[])null),
                ("Indirizzo (stream o playlist):", "", (string[])null),
                ("Gruppo (scegli o scrivi un nome nuovo):", current, groups.ToArray()),
            });
            if (r == null) return;
            var group = r[2].Length == 0 || r[2] == "(senza gruppo)" ? _doc.RootGroup() : _doc.GroupNamed(r[2]);
            if (group == null && _doc.AddGroup(r[2], out group) is string ge) { Error(ge); return; }
            string error = _doc.AddStation(group, r[0], r[1], out var st);
            if (error != null) { Error(error); return; }
            Changed();
            _filter.Text = "";
            Fill(st);
            Info($"Aggiunta \"{st.Name}\" in \"{group.DisplayName}\".");
        }

        private void Delete()
        {
            var sel = Selected;
            if (sel is BookmarksDocument.DocStation s)
            {
                _doc.RemoveStation(s);
                Changed();
                Fill(s.Group);
                Info($"Eliminata \"{s.Name}\".");
            }
            else if (sel is BookmarksDocument.DocGroup g)
            {
                int n = g.Stations.Count;
                if (n > 0 && MessageBox.Show(this, $"Eliminare il gruppo \"{g.DisplayName}\" con le sue {n} stazioni?", "Stazioni",
                                             MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                _doc.RemoveGroup(g);
                Changed();
                Fill(null);
                Info($"Eliminato il gruppo \"{g.DisplayName}\".");
            }
        }

        private void MoveSelected(int delta)
        {
            var sel = Selected;
            if (sel is BookmarksDocument.DocStation s) _doc.MoveStation(s, delta);
            else if (sel is BookmarksDocument.DocGroup g) _doc.MoveGroup(g, delta);
            else return;
            Changed();
            Fill(sel);
        }

        private void MoveToGroup()
        {
            if (!(Selected is BookmarksDocument.DocStation s)) { Info("Scegli prima una stazione."); return; }
            var groups = _doc.Groups.Where(g => !g.IsRoot && g.Name != s.Group.Name).Select(g => g.Name).ToList();
            if (!s.Group.IsRoot) groups.Add("(senza gruppo)");
            var r = Ui.AskFields("Sposta nel gruppo", "Sposta", new[] { ($"Sposta \"{s.Name}\" nel gruppo:", groups.FirstOrDefault() ?? "", groups.ToArray()) });
            if (r == null || r[0].Length == 0) return;
            var target = r[0] == "(senza gruppo)" ? _doc.RootGroup() : _doc.GroupNamed(r[0]);
            if (target == null && _doc.AddGroup(r[0], out target) is string ge) { Error(ge); return; }
            string error = _doc.MoveStationToGroup(s, target, out var moved);
            if (error != null) { Error(error); return; }
            Changed();
            Fill(moved);
        }

        private bool Save()
        {
            ApplyName();
            ApplyUrl();
            string error = _save(_doc.ToJson());
            if (error != null) { Error(error); return false; }
            _dirty = false;
            Text = Text.TrimStart('*', ' ');
            Info("Salvato: l'elenco delle stazioni è aggiornato.");
            return true;
        }

        private bool ConfirmDiscard()
        {
            if (!_dirty) return true;
            var answer = MessageBox.Show(this, "Salvare le modifiche alle stazioni?", "Stazioni", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (answer == DialogResult.Cancel) return false;
            if (answer == DialogResult.Yes) return Save();
            _dirty = false;
            return true;
        }
    }
}
