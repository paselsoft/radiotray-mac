using System;
using System.Collections.Generic;

namespace RadioTray
{
    /// <summary>
    /// Titoli dai servizi "in onda" delle radio che non li mandano nello stream: Deejay, Capital e m2o (GEDI).
    /// </summary>
    public static class OnAir
    {
        /// <summary>L'indirizzo del servizio per questo stream, oppure null.</summary>
        public static string ServiceUrl(string streamUrl)
        {
            string u = (streamUrl ?? "").ToLowerInvariant();
            if (!u.Contains("msvdn.net")) return null;
            if (u.Contains("/radiodeejay/")) return "https://www.deejay.it/api/pub/v2/all/gdwc-audio-player/onair?format=json";
            if (u.Contains("/radiocapital/")) return "https://www.capital.it/api/pub/v2/all/gdwc-audio-player/onair?format=json";
            if (u.Contains("/radiom2o/")) return "https://www.m2o.it/api/pub/v2/all/gdwc-audio-player/onair?format=json";
            return null;
        }

        /// <summary>Parola tutta maiuscola ("SARAH", "GLOCKENBACH,", "&amp;").</summary>
        private static bool IsUpperWord(string w)
        {
            if (w.Length == 0) return false;
            if (w == "&" || w == "X" || w == "+") return true;
            bool letter = false;
            foreach (char c in w) if (char.IsLetter(c)) { letter = true; break; }
            return letter && w == w.ToUpperInvariant() && w != w.ToLowerInvariant();
        }

        /// <summary>
        /// Dal JSON di GEDI: (titolo, artista). Il campo "title" è "Titolo del brano ARTISTA IN MAIUSCOLO";
        /// se non si sa dividere è il nome del programma (artista vuoto). Null se il JSON non va.
        /// </summary>
        public static (string title, string artist)? SongFromGediJson(string json)
        {
            Dictionary<string, object> d;
            try { d = Json.Parse(json) as Dictionary<string, object>; }
            catch (Json.JsonException) { return null; }
            if (d == null) return null;
            string full = (d.TryGetValue("title", out var t) ? t as string : null)?.Trim() ?? "";
            if (full.Length == 0) return null;
            string cover = d.TryGetValue("image", out var im) ? im as string ?? "" : "";

            var words = full.Split(' ');
            int cut = words.Length;
            while (cut > 0 && IsUpperWord(words[cut - 1])) cut--;
            if (cut > 0 && cut < words.Length)
                return (string.Join(" ", words, 0, cut), string.Join(" ", words, cut, words.Length - cut));

            // tutto maiuscolo: si prova il nome del file della copertina, "ARTISTA_-_Titolo__AI_….jpg"
            string file = "";
            if (Uri.TryCreate(cover, UriKind.Absolute, out var cu))
            {
                string path = cu.AbsolutePath;
                file = Uri.UnescapeDataString(path.Substring(path.LastIndexOf('/') + 1));
            }
            int end = file.IndexOf("__", StringComparison.Ordinal);
            if (end >= 0) file = file.Substring(0, end);
            int dash = file.IndexOf("_-_", StringComparison.Ordinal);
            if (cut == 0 && dash >= 0) return (full, file.Substring(0, dash).Replace('_', ' '));
            return (full, "");
        }
    }
}
