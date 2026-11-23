using System;
using System.Drawing;
using System.Windows.Forms;

namespace RadioTray
{
    /// <summary>Finestra "In riproduzione": copertina (o logo), brano, stazione, ★, comandi e volume.</summary>
    internal sealed class NowPlayingWindow : Form
    {
        private readonly PictureBox _picture = new PictureBox { Size = new Size(180, 180), SizeMode = PictureBoxSizeMode.Zoom, BackColor = SystemColors.ControlLight };
        private readonly Label _title = new Label { AutoSize = false, Height = 44, AutoEllipsis = true };
        private readonly Label _artist = new Label { AutoSize = false, Height = 24, AutoEllipsis = true };
        private readonly Label _station = new Label { AutoSize = false, Height = 22, AutoEllipsis = true, ForeColor = SystemColors.GrayText };
        private readonly Label _quality = new Label { AutoSize = false, Height = 20, AutoEllipsis = true, ForeColor = SystemColors.GrayText };
        private readonly Label _volumeText = new Label { AutoSize = false, Width = 44, TextAlign = ContentAlignment.MiddleLeft };
        private readonly Button _star = new Button { Width = 44, Height = 32 };
        private readonly Button _toggle = new Button { Width = 44, Height = 32 };
        private readonly Button _prev = new Button { Width = 44, Height = 32 };
        private readonly Button _next = new Button { Width = 44, Height = 32 };
        private readonly TrackBar _volume = new TrackBar { Minimum = 0, Maximum = 100, TickStyle = TickStyle.None, AutoSize = false, Height = 28, Width = 140 };

        // icone di Windows 10 (Segoe MDL2 Assets); se il font manca, simboli di Segoe UI Symbol
        private static readonly bool Mdl2 = Array.Exists(FontFamily.Families, f => f.Name == "Segoe MDL2 Assets");
        private static string Glyph(string mdl2, string symbol) => Mdl2 ? mdl2 : symbol;
        private static readonly string StarEmpty = Glyph("\uE734", "☆"), StarFull = Glyph("\uE735", "★");
        private static readonly string PlayGlyph = Glyph("\uE768", "▶"), StopGlyph = Glyph("\uE71A", "■");
        private static readonly string PrevGlyph = Glyph("\uE892", "⏮"), NextGlyph = Glyph("\uE893", "⏭");
        private readonly CheckBox _onTop = new CheckBox { Text = "Sempre in primo piano", AutoSize = true };
        private readonly ToolTip _tips = new ToolTip();
        private bool _updating;

        public event Action Favorite, Toggle, Previous, Next;
        public event Action<int> VolumeChanged;
        public event Action<bool> OnTopChanged;

        public NowPlayingWindow(bool onTop)
        {
            Text = "In riproduzione - RadioTray";
            Icon = Icons.App;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.Font;
            Font = SystemFonts.MessageBoxFont;
            ClientSize = new Size(470, 236);
            TopMost = onTop;
            _onTop.Checked = onTop;
            var area = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(area.Right - Width - 16, area.Bottom - Height - 16);

            _picture.Location = new Point(16, 16);
            int x = 212, w = ClientSize.Width - x - 16;
            _title.SetBounds(x, 16, w, 44);
            _title.Font = new Font(Font.FontFamily, Font.Size + 3, FontStyle.Bold);
            _artist.SetBounds(x, 62, w, 24);
            _artist.Font = new Font(Font.FontFamily, Font.Size + 1);
            _station.SetBounds(x, 88, w, 20);
            _quality.SetBounds(x, 108, w, 20);
            _star.Text = StarEmpty;
            _prev.Text = PrevGlyph;
            _toggle.Text = PlayGlyph;
            _next.Text = NextGlyph;
            int bx = x;
            foreach (var b in new[] { _star, _prev, _toggle, _next })
            {
                b.Location = new Point(bx, 134);
                b.Font = Mdl2 ? new Font("Segoe MDL2 Assets", 12f) : new Font("Segoe UI Symbol", 12f);
                bx += 50;
                Controls.Add(b);
            }
            var volLabel = new Label { Text = "Volume", AutoSize = true, Location = new Point(x, 180) };
            _volume.Location = new Point(x + 56, 174);
            _volumeText.SetBounds(x + 200, 176, 44, 22);
            _onTop.Location = new Point(x, 206);
            _tips.SetToolTip(_star, "Aggiungi ai brani preferiti (Ctrl+Alt+F)");
            _tips.SetToolTip(_toggle, "Accendi / spegni (Ctrl+Alt+P)");
            _tips.SetToolTip(_prev, "Stazione precedente (Ctrl+Alt+←)");
            _tips.SetToolTip(_next, "Stazione successiva (Ctrl+Alt+→)");

            Controls.AddRange(new Control[] { _picture, _title, _artist, _station, _quality, volLabel, _volume, _volumeText, _onTop });
            _star.Click += (s, e) => Favorite?.Invoke();
            _toggle.Click += (s, e) => Toggle?.Invoke();
            _prev.Click += (s, e) => Previous?.Invoke();
            _next.Click += (s, e) => Next?.Invoke();
            _volume.ValueChanged += (s, e) =>
            {
                _volumeText.Text = _volume.Value + "%";   // anche mentre si trascina
                if (!_updating) VolumeChanged?.Invoke(_volume.Value);
            };
            _onTop.CheckedChanged += (s, e) => { TopMost = _onTop.Checked; OnTopChanged?.Invoke(_onTop.Checked); };
        }

        /// <param name="active">accesa (anche mentre si collega)</param>
        /// <param name="format">qualità dello stream, per esempio "AAC (HLS) 129 kbps"</param>
        public void Show(string title, string artist, string station, string format, string state, bool playing, bool active, bool favorite, int volume)
        {
            _updating = true;
            _title.Text = string.IsNullOrEmpty(title) ? (playing ? "In riproduzione" : state) : title;
            _artist.Text = artist ?? "";
            _station.Text = station == null ? "" : station + (playing ? "" : " — " + state);
            _quality.Text = playing && !string.IsNullOrEmpty(format) ? format : "";
            _star.Enabled = playing && !string.IsNullOrEmpty(title);
            _star.Text = favorite ? StarFull : StarEmpty;
            _star.ForeColor = favorite ? Color.DarkOrange : SystemColors.ControlText;
            _toggle.Text = active ? StopGlyph : PlayGlyph;
            _toggle.ForeColor = active ? Color.Firebrick : Color.ForestGreen;
            _tips.SetToolTip(_toggle, (active ? "Spegni" : "Accendi") + " (Ctrl+Alt+P)");
            _tips.SetToolTip(_star, favorite ? "Già nei brani preferiti" : "Aggiungi ai brani preferiti (Ctrl+Alt+F)");
            int v = Math.Max(0, Math.Min(100, volume));
            if (_volume.Value != v) _volume.Value = v;
            _volumeText.Text = v + "%";
            _updating = false;
        }

        public void SetImage(Image image)
        {
            var old = _picture.Image;
            _picture.Image = image;
            if (old != null && !ReferenceEquals(old, image)) old.Dispose();
        }
    }
}
