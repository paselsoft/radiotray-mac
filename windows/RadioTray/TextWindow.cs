using System;
using System.Drawing;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace RadioTray
{
    /// <summary>
    /// Finestra di testo interna: editor delle stazioni (con controllo prima di salvare) e visore del registro.
    /// Serve perché sui PC d'ufficio la politica di sicurezza può impedire di avviare il Blocco note.
    /// </summary>
    internal sealed class TextWindow : Form
    {
        private readonly TextBox _text;
        private readonly Label _status;
        private readonly Func<string, string> _save;   // restituisce un errore, oppure null se ha salvato
        private string _savedText;

        public TextWindow(string title, string text, Func<string, string> save, string hint)
        {
            _save = save;
            _savedText = text;
            Text = title;
            Icon = Icons.App;
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Font;
            Font = SystemFonts.MessageBoxFont;
            Size = new Size(820, 620);
            MinimumSize = new Size(480, 320);
            KeyPreview = true;

            _text = new TextBox
            {
                Multiline = true,
                ScrollBars = ScrollBars.Both,
                WordWrap = false,
                AcceptsTab = true,
                AcceptsReturn = true,
                ReadOnly = save == null,
                BackColor = SystemColors.Window,
                Font = new Font("Consolas", 10f),
                Dock = DockStyle.Fill,
                MaxLength = 0,
                Text = text.Replace("\r\n", "\n").Replace("\n", "\r\n"),
            };
            _savedText = _text.Text;

            _status = new Label { AutoSize = false, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, Text = hint ?? "" };
            var buttons = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, Dock = DockStyle.Right, AutoSize = true, WrapContents = false };
            var bottom = new TableLayoutPanel { Dock = DockStyle.Bottom, Height = 44, ColumnCount = 2, Padding = new Padding(8, 6, 8, 6) };
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            bottom.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            if (save != null)
            {
                var saveButton = new Button { Text = "Salva", AutoSize = true };
                saveButton.Click += (s, e) => Save();
                var cancel = new Button { Text = "Chiudi", AutoSize = true };
                cancel.Click += (s, e) => Close();
                buttons.Controls.Add(cancel);
                buttons.Controls.Add(saveButton);
                FormClosing += OnClosing;
            }
            else
            {
                var close = new Button { Text = "Chiudi", AutoSize = true };
                close.Click += (s, e) => Close();
                var copy = new Button { Text = "Copia tutto", AutoSize = true };
                copy.Click += (s, e) =>
                {
                    try { Clipboard.SetText(_text.Text); _status.Text = "Copiato negli appunti"; } catch (Exception) { }
                };
                buttons.Controls.Add(close);
                buttons.Controls.Add(copy);
                CancelButton = close;
                Shown += (s, e) => { _text.SelectionStart = _text.TextLength; _text.ScrollToCaret(); };
            }
            bottom.Controls.Add(_status, 0, 0);
            bottom.Controls.Add(buttons, 1, 0);
            Controls.Add(_text);
            Controls.Add(bottom);
            KeyDown += (s, e) =>
            {
                if (e.Control && e.KeyCode == Keys.S && _save != null) { Save(); e.SuppressKeyPress = true; }
                if (e.Control && e.KeyCode == Keys.A) { _text.SelectAll(); e.SuppressKeyPress = true; }
            };
        }

        public void SetText(string text)
        {
            _text.Text = text.Replace("\r\n", "\n").Replace("\n", "\r\n");
            _savedText = _text.Text;
            _text.SelectionStart = _text.TextLength;
            _text.ScrollToCaret();
        }

        private bool Save()
        {
            string error = _save(_text.Text.Replace("\r\n", "\n"));
            if (error == null)
            {
                _savedText = _text.Text;
                _status.ForeColor = SystemColors.ControlText;
                _status.Text = "Salvato: l'elenco delle stazioni è aggiornato.";
                return true;
            }
            _status.ForeColor = Color.Firebrick;
            _status.Text = error;
            // porta il cursore alla riga dell'errore
            var m = Regex.Match(error, @"riga (\d+), colonna (\d+)");
            if (m.Success)
            {
                int line = int.Parse(m.Groups[1].Value) - 1, column = int.Parse(m.Groups[2].Value) - 1;
                if (line >= 0 && line < _text.Lines.Length)
                {
                    int pos = _text.GetFirstCharIndexFromLine(line) + Math.Min(column, _text.Lines[line].Length);
                    _text.Focus();
                    _text.SelectionStart = Math.Max(0, pos);
                    _text.SelectionLength = 0;
                    _text.ScrollToCaret();
                }
            }
            return false;
        }

        private void OnClosing(object sender, FormClosingEventArgs e)
        {
            if (_text.Text == _savedText) return;
            var answer = MessageBox.Show(this, "Salvare le modifiche alle stazioni?", Text, MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (answer == DialogResult.Cancel || (answer == DialogResult.Yes && !Save())) e.Cancel = true;
        }
    }
}
