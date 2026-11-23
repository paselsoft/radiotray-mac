using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace RadioTray
{
    public sealed class FoundStation
    {
        public string Name = "";
        public string Url = "";
        public string Country = "";
        public string Codec = "";
        public int Bitrate;
        public string Tags = "";
        public int Votes;
        public bool Hls;

        /// <summary>Su Windows: MP3, AAC e HLS sì; Ogg, Opus, FLAC e WMA non ancora.</summary>
        public bool Playable
        {
            get
            {
                string c = Codec.ToUpperInvariant();
                return !(c.Contains("WMA") || c.Contains("OGG") || c.Contains("OPUS") || c.Contains("FLAC") || c.Contains("VORBIS"));
            }
        }

        /// <summary>"MP3 128 kbps".</summary>
        public string FormatDescription
        {
            get
            {
                string codec = Codec.Length > 0 && Codec != "UNKNOWN" ? Codec : (Hls ? "HLS" : "?");
                return Bitrate > 0 ? $"{codec} {Bitrate} kbps" : codec;
            }
        }
    }

    /// <summary>
    /// L'archivio pubblico e gratuito Radio Browser (www.radio-browser.info), lo stesso della versione per Mac:
    /// indirizzi delle ricerche, lettura della risposta e nomi alternativi da provare.
    /// </summary>
    public static class RadioBrowser
    {
        public static readonly string[] Servers =
            { "de1.api.radio-browser.info", "de2.api.radio-browser.info", "fi1.api.radio-browser.info", "all.api.radio-browser.info" };

        public enum Mode { Name, Tag, Top }

        public static string SearchUrl(string server, Mode mode, string text, string countryCode)
        {
            var q = new List<string>();
            if (mode == Mode.Name) q.Add("name=" + Uri.EscapeDataString(text ?? ""));
            else if (mode == Mode.Tag) q.Add("tag=" + Uri.EscapeDataString((text ?? "").ToLowerInvariant()));
            q.Add("hidebroken=true");
            q.Add("order=clickcount");
            q.Add("reverse=true");
            q.Add("limit=100");
            if (!string.IsNullOrEmpty(countryCode)) q.Add("countrycode=" + Uri.EscapeDataString(countryCode));
            return $"https://{server}/json/stations/search?" + string.Join("&", q);
        }

        private static string Str(object v)
        {
            if (v is string s) return s.Trim();
            if (v is double d) return d.ToString(CultureInfo.InvariantCulture);
            if (v is bool b) return b ? "1" : "0";
            return "";
        }

        private static int Int(object v) => int.TryParse(Str(v), NumberStyles.Integer, CultureInfo.InvariantCulture, out int n) ? n : 0;

        /// <summary>Le stazioni della risposta; quelle che Windows non sa suonare vanno in fondo. Null se non è JSON valido.</summary>
        public static List<FoundStation> StationsFromJson(string json)
        {
            object root;
            try { root = Json.Parse(json); }
            catch (Json.JsonException) { return null; }
            if (!(root is List<object> list)) return null;
            var playable = new List<FoundStation>();
            var other = new List<FoundStation>();
            var seen = new HashSet<string>();
            foreach (var item in list)
            {
                if (!(item is Dictionary<string, object> d)) continue;
                object Get(string k) => d.TryGetValue(k, out var v) ? v : null;
                var s = new FoundStation { Name = Str(Get("name")) };
                string resolved = Str(Get("url_resolved"));
                s.Url = resolved.Length > 0 ? resolved : Str(Get("url"));
                if (s.Name.Length == 0 || s.Url.Length == 0) continue;
                string lower = s.Url.ToLowerInvariant();
                if (!lower.StartsWith("http://", StringComparison.Ordinal) && !lower.StartsWith("https://", StringComparison.Ordinal)) continue;
                // stessa stazione registrata più volte: si tiene la prima (la più ascoltata)
                if (!seen.Add(s.Name.ToLowerInvariant() + "|" + lower)) continue;
                s.Country = Str(Get("countrycode")).ToUpperInvariant();
                s.Codec = Str(Get("codec")).ToUpperInvariant();
                s.Bitrate = Int(Get("bitrate"));
                s.Tags = Str(Get("tags")).Replace(",", ", ");
                s.Votes = Int(Get("votes"));
                s.Hls = Int(Get("hls")) != 0;
                (s.Playable ? playable : other).Add(s);
            }
            playable.AddRange(other);
            return playable;
        }

        private static readonly string[][] Aliases =
        {
            new[] { "radio monte carlo", "RMC" }, new[] { "radio montecarlo", "RMC" }, new[] { "radiomontecarlo", "RMC" }, new[] { "monte carlo", "RMC" },
            new[] { "radio dimensione suono", "RDS" }, new[] { "dimensione suono", "RDS" },
            new[] { "radio deejay", "Deejay" }, new[] { "radio dee jay", "Deejay" }, new[] { "radio dj", "Deejay" },
            new[] { "radio 105 network", "Radio 105" }, new[] { "rete 105", "Radio 105" },
            new[] { "radio capital", "Capital" }, new[] { "radio kiss kiss", "Kiss Kiss" },
            new[] { "radio italia solo musica italiana", "Radio Italia" },
            new[] { "radio freccia", "Radiofreccia" }, new[] { "radio subasio", "Subasio" },
            new[] { "radio m2o", "m2o" }, new[] { "radio virgin", "Virgin Radio" }, new[] { "radio r101", "R101" }, new[] { "radio 101", "R101" },
            new[] { "rtl 102,5", "RTL 102.5" }, new[] { "rtl1025", "RTL 102.5" }, new[] { "radio rtl", "RTL 102.5" },
            new[] { "radio rai", "Rai Radio" }, new[] { "radio uno", "Rai Radio 1" }, new[] { "radio due", "Rai Radio 2" }, new[] { "radio tre", "Rai Radio 3" },
            new[] { "radio 24 il sole 24 ore", "Radio 24" }, new[] { "radio ventiquattro", "Radio 24" },
        };

        private static string RemoveAccents(string s)
        {
            var d = s.Normalize(NormalizationForm.FormD);
            var sb = new StringBuilder();
            foreach (char c in d) if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
            return sb.ToString().Normalize(NormalizationForm.FormC);
        }

        /// <summary>
        /// Nomi da provare quando la ricerca non trova nulla: sigle note ("Radio Monte Carlo Hits" → "RMC Hits"),
        /// nome senza "Radio", iniziali ("Radio Dimensione Suono" → "RDS"). Mai il nome di partenza.
        /// </summary>
        public static List<string> AlternativeNames(string name)
        {
            string clean = RemoveAccents((name ?? "").Trim());
            while (clean.Contains("  ")) clean = clean.Replace("  ", " ");
            string lower = clean.ToLowerInvariant();
            var output = new List<string>();
            void Add(string c)
            {
                c = c.Trim();
                if (c.Length < 2 || string.Equals(c, clean, StringComparison.OrdinalIgnoreCase)) return;
                if (output.Any(x => string.Equals(x, c, StringComparison.OrdinalIgnoreCase))) return;
                output.Add(c);
            }
            foreach (var a in Aliases)
            {
                string key = a[0];
                if (lower == key || (lower.StartsWith(key, StringComparison.Ordinal) && lower[key.Length] == ' '))
                    Add(a[1] + clean.Substring(key.Length));
            }
            var words = clean.Split(' ');
            if (words.Length >= 2 && words[0].ToLowerInvariant() == "radio") Add(string.Join(" ", words.Skip(1)));
            if (words.Length >= 3)
            {
                var initials = new StringBuilder();
                int n = 0;
                foreach (var w in words)
                {
                    if (w.Length == 0 || !char.IsLetter(w[0])) break;
                    initials.Append(char.ToUpperInvariant(w[0]));
                    n++;
                }
                if (n >= 3)
                {
                    Add(initials.ToString());
                    if (n > 3) Add(initials.ToString(0, 3) + " " + string.Join(" ", words.Skip(3)));
                }
            }
            if (words.Length == 2 && words[0].ToLowerInvariant() == "radio") Add("Radio" + words[1].ToLowerInvariant());
            if (words.Length == 1 && lower.StartsWith("radio", StringComparison.Ordinal) && lower.Length > 6) Add("Radio " + clean.Substring(5));
            return output;
        }
    }
}
