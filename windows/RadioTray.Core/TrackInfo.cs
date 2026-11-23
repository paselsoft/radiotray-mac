using System;
using System.Globalization;
using System.Linq;
using System.Text;

namespace RadioTray
{
    /// <summary>Titolo e artista del brano (come src/RTTrackInfo.m della versione Mac).</summary>
    public sealed class TrackInfo
    {
        public string Title { get; private set; } = "";
        public string Artist { get; private set; } = "";

        public bool IsEmpty => Title.Length == 0 && Artist.Length == 0;

        public static string Truncate(string text, int max)
        {
            if (text == null) return "";
            var info = new StringInfo(text);
            if (info.LengthInTextElements <= max || max < 2) return text;
            return info.SubstringByTextElements(0, max - 1).Trim() + "…";
        }

        /// <summary>"PINGUINI TATTICI NUCLEARI" → "Pinguini Tattici Nucleari" (solo se tutto maiuscolo).</summary>
        private static string SoftenCaps(string s)
        {
            if (s.Length < 4 || !s.Any(char.IsLetter)) return s;
            var it = CultureInfo.GetCultureInfo("it-IT");
            if (s != s.ToUpper(it)) return s;
            var sb = new StringBuilder(s.Length);
            bool start = true;
            foreach (char c in s)
            {
                sb.Append(start ? char.ToUpper(c, it) : char.ToLower(c, it));
                start = char.IsWhiteSpace(c);
            }
            return sb.ToString();
        }

        public static TrackInfo Create(string title, string artist)
        {
            var info = new TrackInfo
            {
                Title = SoftenCaps((title ?? "").Trim()),
                Artist = SoftenCaps((artist ?? "").Trim()),
            };
            // un titolo fatto solo di "-" è un tag vuoto
            if (info.Title == "-") info.Title = "";
            if (info.Artist == "-") info.Artist = "";
            return info;
        }

        public static TrackInfo FromStreamTitle(string streamTitle, bool split = true)
        {
            string raw = (streamTitle ?? "").Trim();

            // radio Mediaset (105, Virgin, R101, RMC…): "ARTISTA~TITOLO~ALBUM~ANNO~ISRC~DURATA~inizio~fine~STAZIONE"
            var fields = raw.Split('~');
            if (fields.Length >= 3)
            {
                string a = fields[0].Trim(), t = fields[1].Trim();
                if (t.Length == 0) return Create(a, null);
                // Radio 105 a volte: "~ARTISTA - TITOLO~~0~~122~…" (artista vuoto, tutto nel secondo campo)
                if (a.Length == 0) return FromStreamTitle(t.Replace("~", " "), split);
                return split ? Create(t, a) : Create($"{a} - {t}", null);
            }

            // RDS e altre: "Titolo * Artista * 11712" (l'ultimo campo è un codice interno)
            var starred = raw.Split(new[] { " * " }, StringSplitOptions.None);
            if (starred.Length >= 2)
            {
                string t = starred[0].Trim(), a = starred[1].Trim();
                if (t.Length > 0 && a.Length > 0)
                    return split ? Create(t, a) : Create($"{a} - {t}", null);
            }

            if (!split) return Create(raw, null);

            int sep = raw.IndexOf(" - ", StringComparison.Ordinal);
            if (sep < 0) return Create(raw, null);
            string artist = raw.Substring(0, sep).Trim();
            string title = raw.Substring(sep + 3).Trim();

            // iHeartRadio: title="..." text="Titolo vero" song_spot=...
            int text = title.IndexOf("text=\"", StringComparison.Ordinal);
            if (text >= 0)
            {
                int start = text + 6;
                int end = title.IndexOf('"', start);
                if (end >= 0) title = title.Substring(start, end - start);
            }
            // "Artista - " senza titolo: meglio mostrare il testo intero
            if (title.Length == 0) return Create(artist, null);
            return Create(title, artist);
        }

        public TrackInfo Swapped()
        {
            if (Title.Length == 0 || Artist.Length == 0) return this;
            return new TrackInfo { Title = Artist, Artist = Title };
        }

        private static string Simple(string s)
        {
            string d = (s ?? "").Normalize(NormalizationForm.FormD);
            var sb = new StringBuilder();
            foreach (char c in d)
            {
                if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
                if (char.IsLetterOrDigit(c)) sb.Append(char.ToLowerInvariant(c));
            }
            return sb.ToString();
        }

        /// <summary>Jingle o pubblicità: la radio manda solo il proprio nome invece di un brano.</summary>
        public bool IsFillerForStation(string station)
        {
            string s = Simple(station), t = Simple(Title), a = Simple(Artist);
            if (t.Length == 0 && a.Length == 0) return false;
            // "Radio 105" per la stazione "Radio 105 Network", "RadioFreccia" per "Radiofreccia"
            if (s.Length >= 5 && ((t.Length >= 5 && s.Contains(t)) || (t.Length > 0 && t.Contains(s)) || (a.Length > 0 && a.Contains(s)) ||
                                  (a.Length >= 5 && s.Contains(a))))
                return true;
            // il nome di una radio senza un vero titolo ("Radio Subasio")
            return t.StartsWith("radio", StringComparison.Ordinal) && a.Length == 0 && t.Length <= 12;
        }

        public bool SameAs(TrackInfo other) => other != null && Title == other.Title && Artist == other.Artist;

        /// <summary>Titolo e artista su due righe (per gli appunti e le notifiche).</summary>
        public string Text
        {
            get
            {
                if (Artist.Length == 0) return Title;
                if (Title.Length == 0) return Artist;
                return Title + "\n" + Artist;
            }
        }
    }
}
