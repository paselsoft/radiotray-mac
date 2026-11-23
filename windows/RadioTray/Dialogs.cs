using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Forms;

namespace RadioTray
{
    /// <summary>Piccole finestre di dialogo e funzioni comuni alle finestre.</summary>
    internal static class Ui
    {
        public static Form NewDialog(string title, int width, int height)
        {
            return new Form
            {
                Text = title,
                FormBorderStyle = FormBorderStyle.FixedDialog,
                StartPosition = FormStartPosition.CenterScreen,
                MinimizeBox = false,
                MaximizeBox = false,
                ShowInTaskbar = true,
                TopMost = true,
                AutoScaleMode = AutoScaleMode.Font,
                Font = SystemFonts.MessageBoxFont,
                ClientSize = new Size(width, height),
                Icon = Icons.App,
            };
        }

        /// <summary>Campi di testo (ed eventualmente una casella a scelta) con OK/Annulla. Null se annullato.</summary>
        public static string[] AskFields(string title, string okText, (string label, string value, string[] choices)[] fields)
        {
            int rowHeight = 52;
            using (var form = NewDialog(title, 480, 20 + fields.Length * rowHeight + 46))
            {
                var controls = new List<Control>();
                for (int i = 0; i < fields.Length; i++)
                {
                    var (label, value, choices) = fields[i];
                    form.Controls.Add(new Label { Text = label, Left = 12, Top = 12 + i * rowHeight, Width = 456, AutoSize = false, Height = 18 });
                    Control input;
                    if (choices != null)
                    {
                        var combo = new ComboBox { Left = 12, Top = 32 + i * rowHeight, Width = 456, DropDownStyle = ComboBoxStyle.DropDown };
                        combo.Items.AddRange(choices.Cast<object>().ToArray());
                        combo.Text = value ?? "";
                        input = combo;
                    }
                    else input = new TextBox { Left = 12, Top = 32 + i * rowHeight, Width = 456, Text = value ?? "" };
                    form.Controls.Add(input);
                    controls.Add(input);
                }
                int y = 20 + fields.Length * rowHeight + 6;
                var ok = new Button { Text = okText, DialogResult = DialogResult.OK, Left = 300, Top = y, Width = 80 };
                var cancel = new Button { Text = "Annulla", DialogResult = DialogResult.Cancel, Left = 388, Top = y, Width = 80 };
                form.Controls.Add(ok);
                form.Controls.Add(cancel);
                form.AcceptButton = ok;
                form.CancelButton = cancel;
                form.Shown += (s, e) =>
                {
                    form.Activate();
                    var first = controls.FirstOrDefault(c => c.Text.Length == 0) ?? controls[0];
                    first.Focus();
                    if (first is TextBox tb) tb.SelectAll();
                };
                if (form.ShowDialog() != DialogResult.OK) return null;
                return controls.Select(c => c.Text.Trim()).ToArray();
            }
        }

        /// <summary>Apre un indirizzo nel browser; se la politica del PC lo impedisce, lo copia negli appunti.</summary>
        public static void OpenInBrowser(string url, IWin32Window owner = null)
        {
            try
            {
                Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
            }
            catch (Exception e)
            {
                Log.Write("Browser non avviato: " + e.Message);
                try { Clipboard.SetText(url); } catch (Exception) { }
                MessageBox.Show(owner, "Windows non permette di aprire il browser da qui (" + e.Message + ").\n\n" +
                                "L'indirizzo è stato copiato negli appunti: incollalo nella barra del browser.\n\n" + url,
                                "RadioTray", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }

        public static void Bring(Form f)
        {
            if (f.WindowState == FormWindowState.Minimized) f.WindowState = FormWindowState.Normal;
            f.Show();
            f.Activate();
        }

        /// <summary>Scrive un file di testo UTF-8 senza rischiare di lasciarlo a metà.</summary>
        public static void WriteText(string path, string text)
        {
            string tmp = path + ".tmp";
            File.WriteAllText(tmp, text, new UTF8Encoding(false));
            if (File.Exists(path)) File.Replace(tmp, path, null);
            else File.Move(tmp, path);
        }

        /// <summary>Ordinamento delle colonne di una ListView: clic sull'intestazione, di nuovo per invertire.</summary>
        public sealed class ColumnSorter : System.Collections.IComparer
        {
            public int Column;
            public bool Descending;
            public Func<ListViewItem, int, IComparable> Key = (item, col) => item.SubItems[col].Text;

            public int Compare(object x, object y)
            {
                var a = Key((ListViewItem)x, Column);
                var b = Key((ListViewItem)y, Column);
                int r = a is string sa && b is string sb ? string.Compare(sa, sb, StringComparison.CurrentCultureIgnoreCase) : Comparer<IComparable>.Default.Compare(a, b);
                return Descending ? -r : r;
            }

            public void Attach(ListView list)
            {
                list.ListViewItemSorter = this;
                list.ColumnClick += (s, e) =>
                {
                    if (e.Column == Column) Descending = !Descending;
                    else { Column = e.Column; Descending = false; }
                    list.Sort();
                };
            }
        }
    }
}
