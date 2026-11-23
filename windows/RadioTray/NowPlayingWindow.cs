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
        private readonly Button _star = new Button { Text = "★", Width = 44, Height = 32 };
        private readonly Button _toggle = new Button { Text = "⏻", Width = 44, Height = 32 };
        private readonly Button _prev = new Button { Text = "⏮", Width = 44, Height = 32 };
        private readonly Button _next = new Button { Text = "⏭", Width = 44, Height = 32 };
        private readonly TrackBar _volume = new TrackBar { Minimum = 0, Maximum = 100, TickStyle = TickStyle.None, AutoSize = false, Height = 28, Width = 170 };
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
            ClientSize = new Size(470, 214);
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
            _station.SetBounds(x, 88, w, 22);
            int bx = x;
            foreach (var b in new[] { _star, _prev, _toggle, _next })
            {
                b.Location = new Point(bx, 116);
                b.Font = new Font("Segoe UI Symbol", 12f);
                bx += 50;
                Controls.Add(b);
            }
            var volLabel = new Label { Text = "Volume", AutoSize = true, Location = new Point(x, 160) };
            _volume.Location = new Point(x + 56, 154);
            _onTop.Location = new Point(x, 186);
            _tips.SetToolTip(_star, "Aggiungi ai brani preferiti (Ctrl+Alt+F)");
            _tips.SetToolTip(_toggle, "Accendi / spegni (Ctrl+Alt+P)");
            _tips.SetToolTip(_prev, "Stazione precedente (Ctrl+Alt+←)");
            _tips.SetToolTip(_next, "Stazione successiva (Ctrl+Alt+→)");

            Controls.AddRange(new Control[] { _picture, _title, _artist, _station, volLabel, _volume, _onTop });
            _star.Click += (s, e) => Favorite?.Invoke();
            _toggle.Click += (s, e) => Toggle?.Invoke();
            _prev.Click += (s, e) => Previous?.Invoke();
            _next.Click += (s, e) => Next?.Invoke();
            _volume.ValueChanged += (s, e) => { if (!_updating) VolumeChanged?.Invoke(_volume.Value); };
            _onTop.CheckedChanged += (s, e) => { TopMost = _onTop.Checked; OnTopChanged?.Invoke(_onTop.Checked); };
        }

        public void Show(string title, string artist, string station, string state, bool playing, bool favorite, int volume)
        {
            _updating = true;
            _title.Text = string.IsNullOrEmpty(title) ? (playing ? "In riproduzione" : state) : title;
            _artist.Text = artist ?? "";
            _station.Text = station == null ? "" : station + (playing ? "" : " — " + state);
            _star.Enabled = playing && !string.IsNullOrEmpty(title);
            _star.ForeColor = favorite ? Color.DarkOrange : SystemColors.ControlText;
            _toggle.ForeColor = playing ? Color.ForestGreen : SystemColors.ControlText;
            if (_volume.Value != volume) _volume.Value = Math.Max(0, Math.Min(100, volume));
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
