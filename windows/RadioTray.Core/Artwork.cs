using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace RadioTray
{
    /// <summary>
    /// Copertine dal catalogo pubblico di Apple (iTunes Search API: gratuita, senza chiave) e loghi delle stazioni
    /// dall'archivio Radio Browser. Come sul Mac, una copertina si accetta solo se l'artista corrisponde.
    /// </summary>
    public static class Artwork
    {
        /// <summary>Testo semplificato per i confronti: minuscolo, senza accenti, solo lettere e cifre.</summary>
        public static string Normalized(string text)
        {
            var d = (text ?? "").Normalize(NormalizationForm.FormD);
            var sb = new StringBuilder();
            foreach (char c in d)
            {
                if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
                if (char.IsLetterOrDigit(c)) sb.Append(char.ToLowerInvariant(c));
            }
            return sb.ToString();
        }

        /// <summary>Il titolo senza le aggiunte: "Song (Remix)", "Song [Live]", "Song - Edit", "Song feat. X" → "Song".</summary>
        public static string CoreTitle(string title)
        {
            string t = title ?? "";
            foreach (var cut in new[] { " (", " [", " - ", " feat.", " ft." })
            {
                int i = t.IndexOf(cut, StringComparison.OrdinalIgnoreCase);
                if (i > 0) t = t.Substring(0, i);
            }
            return t;
        }

        private static bool Matches(string a, string b)
        {
            string x = Normalized(a), y = Normalized(b);
            if (x.Length == 0 || y.Length == 0) return false;
            return x == y || x.Contains(y) || y.Contains(x);
        }

        public static string SearchUrl(string title, string artist) =>
            "https://itunes.apple.com/search?term=" + Uri.EscapeDataString($"{artist} {CoreTitle(title)}") +
            "&media=music&entity=song&limit=10";

        /// <summary>Chiave della cache: artista e titolo semplificati.</summary>
        public static string CacheKey(string title, string artist) => Normalized(artist) + "|" + Normalized(CoreTitle(title));

        /// <summary>Indirizzo della copertina (600×600) scelto tra i risultati, oppure null.</summary>
        public static string ArtworkUrlFromJson(string json, string title, string artist)
        {
            Dictionary<string, object> root;
            try { root = Json.Parse(json) as Dictionary<string, object>; }
            catch (Json.JsonException) { return null; }
            if (root == null || !(root.TryGetValue("results", out var r) && r is List<object> results)) return null;
            string firstArtist = (artist ?? "").Split('&', ',', '/')[0];
            string best = null;
            int bestScore = 0;
            foreach (var item in results.OfType<Dictionary<string, object>>())
            {
                string art = item.TryGetValue("artworkUrl100", out var a) ? a as string : null;
                string rArtist = item.TryGetValue("artistName", out var ra) ? ra as string : null;
                string rTrack = item.TryGetValue("trackName", out var rt) ? rt as string : null;
                if (art == null || rArtist == null) continue;
                // l'artista deve corrispondere (anche solo in parte: "Mina" e "Mina & Celentano")
                if (!Matches(rArtist, artist) && !Matches(rArtist, firstArtist)) continue;
                int score = rTrack != null && Matches(CoreTitle(rTrack), CoreTitle(title)) ? 2 : 1;
                if (score > bestScore) { bestScore = score; best = art; }
            }
            return best?.Replace("100x100", "600x600");
        }

        public static string LogoByUrlQuery(string server, string stationUrl) =>
            $"https://{server}/json/stations/byurl?url=" + Uri.EscapeDataString(stationUrl ?? "");

        public static string LogoByNameQuery(string server, string name) =>
            $"https://{server}/json/stations/search?name=" + Uri.EscapeDataString(name ?? "") + "&order=clickcount&reverse=true&limit=10";

        /// <summary>I loghi utilizzabili tra i risultati di Radio Browser (niente SVG né pagine di Facebook).</summary>
        public static List<string> FaviconsFromJson(string json)
        {
            var output = new List<string>();
            List<object> list;
            try { list = Json.Parse(json) as List<object>; }
            catch (Json.JsonException) { return output; }
            if (list == null) return output;
            foreach (var s in list.OfType<Dictionary<string, object>>())
            {
                string f = (s.TryGetValue("favicon", out var v) ? v as string : null)?.Trim() ?? "";
                string lower = f.ToLowerInvariant();
                if (!lower.StartsWith("http://", StringComparison.Ordinal) && !lower.StartsWith("https://", StringComparison.Ordinal)) continue;
                if (lower.Contains(".svg") || lower.Contains("facebook.com")) continue;
                if (!output.Contains(f)) output.Add(f);
            }
            return output;
        }
    }

    /// <summary>Radiosveglia: ora, giorni della settimana (lunedì = bit 0 … domenica = bit 6), come sul Mac.</summary>
    public static class Alarm
    {
        public const int Weekdays = 0x1F;
        public const int EveryDay = 0x7F;
        /// <summary>Minuti di tolleranza: un PC che si risveglia poco dopo l'ora fa suonare lo stesso.</summary>
        public const int GraceMinutes = 10;

        public static int DayBit(DateTime local) => 1 << (((int)local.DayOfWeek + 6) % 7);

        /// <summary>
        /// Deve suonare adesso? Oggi è un giorno scelto, sono passati da 0 a 10 minuti dall'ora
        /// (minuti dalla mezzanotte) e non ha già suonato oggi.
        /// </summary>
        public static bool ShouldFire(DateTime nowLocal, int minutes, int days, DateTime? lastFiredLocal)
        {
            if ((days & DayBit(nowLocal)) == 0) return false;
            if (lastFiredLocal.HasValue && lastFiredLocal.Value.Date == nowLocal.Date) return false;
            int late = nowLocal.Hour * 60 + nowLocal.Minute - minutes;
            return late >= 0 && late <= GraceMinutes;
        }

        /// <summary>Prossima volta in cui suonerà, oppure null se nessun giorno è scelto.</summary>
        public static DateTime? NextFire(DateTime nowLocal, int minutes, int days)
        {
            if ((days & EveryDay) == 0) return null;
            for (int offset = 0; offset <= 7; offset++)
            {
                var day = nowLocal.Date.AddDays(offset);
                if ((days & DayBit(day)) == 0) continue;
                var fire = day.AddMinutes(minutes);
                if (fire > nowLocal) return fire;
            }
            return null;
        }

        /// <summary>"Lu–Ve", "Tutti i giorni", "Sa, Do", "Lu, Me, Ve"…</summary>
        public static string DescribeDays(int days)
        {
            days &= EveryDay;
            if (days == EveryDay) return "Tutti i giorni";
            if (days == Weekdays) return "Lu–Ve";
            if (days == 0x60) return "Sa, Do";
            if (days == 0) return "Nessun giorno";
            var names = new[] { "Lu", "Ma", "Me", "Gi", "Ve", "Sa", "Do" };
            return string.Join(", ", Enumerable.Range(0, 7).Where(i => (days & (1 << i)) != 0).Select(i => names[i]));
        }

        public static string DescribeMinutes(int minutes) => $"{minutes / 60:00}:{minutes % 60:00}";
    }
}
