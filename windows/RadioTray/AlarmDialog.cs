using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace RadioTray
{
    /// <summary>Impostazione della radiosveglia: ora, giorni, stazione, volume crescente.</summary>
    internal static class AlarmDialog
    {
        public sealed class Result
        {
            public bool Enabled;
            public int Minutes;
            public int Days;
            public string Group, Station;
            public bool FadeIn;
        }

        public static Result Ask(Result current, List<(string group, string station)> stations)
        {
            using (var form = Ui.NewDialog("Radiosveglia", 440, 300))
            {
                var enabled = new CheckBox { Text = "Sveglia attiva", Checked = current.Enabled, Left = 12, Top = 12, AutoSize = true };
                var timeLabel = new Label { Text = "Ora:", Left = 12, Top = 46, AutoSize = true };
                var time = new DateTimePicker
                {
                    Format = DateTimePickerFormat.Custom, CustomFormat = "HH:mm", ShowUpDown = true, Left = 80, Top = 42, Width = 80,
                    Value = DateTime.Today.AddMinutes(current.Minutes),
                };
                var daysLabel = new Label { Text = "Giorni:", Left = 12, Top = 82, AutoSize = true };
                var names = new[] { "Lu", "Ma", "Me", "Gi", "Ve", "Sa", "Do" };
                var boxes = new List<CheckBox>();
                for (int i = 0; i < 7; i++)
                {
                    var b = new CheckBox { Text = names[i], Left = 80 + i * 48, Top = 80, Width = 46, Checked = (current.Days & (1 << i)) != 0 };
                    boxes.Add(b);
                    form.Controls.Add(b);
                }
                var stationLabel = new Label { Text = "Stazione:", Left = 12, Top = 120, AutoSize = true };
                var station = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Left = 80, Top = 116, Width = 344 };
                foreach (var (g, s) in stations) station.Items.Add(g == Bookmarks.RootGroupName ? s : $"{s}  ({g})");
                int index = stations.FindIndex(x => x.group == current.Group && x.station == current.Station);
                station.SelectedIndex = index >= 0 ? index : (stations.Count > 0 ? 0 : -1);
                var fade = new CheckBox { Text = "Volume crescente (dal basso al volume abituale in 2 minuti)", Checked = current.FadeIn, Left = 12, Top = 156, AutoSize = true };
                var note = new Label
                {
                    Text = "Il PC deve essere acceso, con RadioTray avviato (non in sospensione).\nSe si risveglia entro 10 minuti dall'ora, la sveglia suona lo stesso.",
                    Left = 12, Top = 188, Width = 416, Height = 40, ForeColor = SystemColors.GrayText,
                };
                var ok = new Button { Text = "Salva", DialogResult = DialogResult.OK, Left = 260, Top = 256, Width = 80 };
                var cancel = new Button { Text = "Annulla", DialogResult = DialogResult.Cancel, Left = 348, Top = 256, Width = 80 };
                form.Controls.AddRange(new Control[] { enabled, timeLabel, time, daysLabel, stationLabel, station, fade, note, ok, cancel });
                form.AcceptButton = ok;
                form.CancelButton = cancel;
                if (form.ShowDialog() != DialogResult.OK) return null;
                int days = 0;
                for (int i = 0; i < 7; i++) if (boxes[i].Checked) days |= 1 << i;
                var chosen = station.SelectedIndex >= 0 ? stations[station.SelectedIndex] : (null, null);
                return new Result
                {
                    Enabled = enabled.Checked && days != 0 && chosen.Item2 != null,
                    Minutes = time.Value.Hour * 60 + time.Value.Minute,
                    Days = days,
                    Group = chosen.Item1,
                    Station = chosen.Item2,
                    FadeIn = fade.Checked,
                };
            }
        }
    }
}
