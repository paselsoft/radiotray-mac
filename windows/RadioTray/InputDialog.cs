using System.Drawing;
using System.Windows.Forms;

namespace RadioTray
{
    /// <summary>Una piccola finestra con un campo di testo (per "Apri indirizzo…").</summary>
    internal static class InputDialog
    {
        public static string Ask(string title, string prompt, string initial)
        {
            using (var form = new Form())
            {
                form.Text = title;
                form.FormBorderStyle = FormBorderStyle.FixedDialog;
                form.StartPosition = FormStartPosition.CenterScreen;
                form.MinimizeBox = form.MaximizeBox = false;
                form.ShowInTaskbar = true;
                form.TopMost = true;
                form.AutoScaleMode = AutoScaleMode.Font;
                form.Font = SystemFonts.MessageBoxFont;
                form.ClientSize = new Size(480, 120);
                form.Icon = Icons.App;

                var label = new Label { Text = prompt, AutoSize = false, Left = 12, Top = 12, Width = 456, Height = 34 };
                var box = new TextBox { Left = 12, Top = 48, Width = 456, Text = initial ?? "" };
                var ok = new Button { Text = "Ascolta", DialogResult = DialogResult.OK, Left = 300, Top = 82, Width = 80 };
                var cancel = new Button { Text = "Annulla", DialogResult = DialogResult.Cancel, Left = 388, Top = 82, Width = 80 };
                form.Controls.AddRange(new Control[] { label, box, ok, cancel });
                form.AcceptButton = ok;
                form.CancelButton = cancel;
                form.Shown += (s, e) => { form.Activate(); box.Focus(); box.SelectAll(); };
                return form.ShowDialog() == DialogResult.OK ? box.Text.Trim() : null;
            }
        }
    }
}
