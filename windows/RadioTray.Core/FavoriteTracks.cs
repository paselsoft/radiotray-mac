using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

namespace RadioTray
{
    public sealed class FavoriteTrack
    {
        public string Title = "";
        public string Artist = "";
        public string Station = "";
        public DateTime Added;   // UTC

        /// <summary>"Titolo – Artista" (o solo il titolo).</summary>
        public string DisplayText => Artist.Length > 0 ? $"{Title} – {Artist}" : Title;
        /// <summary>Testo per una ricerca sul web: "Artista Titolo".</summary>
        public string SearchText => Artist.Length > 0 ? $"{Artist} {Title}" : Title;
    }

    public enum TrackSearchSite { YouTube, YouTubeMusic, Spotify, AppleMusic }

    /// <summary>
    /// Brani preferiti (brani-preferiti.json) e ascoltati di recente (ascoltati-di-recente.json):
    /// lo stesso formato della versione per Mac, [{"title","artist","station","added"}], data ISO 8601.
    /// </summary>
    public sealed class FavoriteTracks
    {
        private readonly List<FavoriteTrack> _list = new List<FavoriteTrack>();

        /// <summary>In ordine di aggiunta.</summary>
        public IReadOnlyList<FavoriteTrack> Tracks => _list;

        public static string FormatDate(DateTime utc) =>
            DateTime.SpecifyKind(utc, DateTimeKind.Utc).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

        public static DateTime ParseDate(string s)
        {
            if (!string.IsNullOrEmpty(s) && DateTime.TryParse(s, CultureInfo.InvariantCulture,
                    DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var d))
                return DateTime.SpecifyKind(d, DateTimeKind.Utc);
            return new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        }

        private static string Trim(object v) => v is string s ? s.Trim() : "";

        /// <summary>Legge il file; se manca è un elenco vuoto. Null (con errore) solo se il file esiste ed è illeggibile.</summary>
        public static FavoriteTracks FromFile(string path, out string error)
        {
            error = null;
            if (!File.Exists(path)) return new FavoriteTracks();
            try { return Parse(File.ReadAllText(path, Encoding.UTF8), out error); }
            catch (Exception e) { error = e.Message; return null; }
        }

        public static FavoriteTracks Parse(string text, out string error)
        {
            error = null;
            var result = new FavoriteTracks();
            if (string.IsNullOrWhiteSpace(text)) return result;
            object root;
            try { root = Json.Parse(text); }
            catch (Json.JsonException) { root = null; }
            if (!(root is List<object> list))
            {
                error = "Il file dei brani non è un elenco JSON valido";
                return null;
            }
            foreach (var item in list)
            {
                if (!(item is Dictionary<string, object> d)) continue;
                object Get(string k) => d.TryGetValue(k, out var v) ? v : null;
                var t = new FavoriteTrack { Title = Trim(Get("title")), Artist = Trim(Get("artist")), Station = Trim(Get("station")) };
                if (t.Title.Length == 0 && t.Artist.Length == 0) continue;
                if (t.Title.Length == 0) { t.Title = t.Artist; t.Artist = ""; }   // solo artista: lo si mostra come titolo
                t.Added = ParseDate(Trim(Get("added")));
                result._list.Add(t);
            }
            return result;
        }

        public static FavoriteTracks FromJsonValue(object value) =>
            value is List<object> ? Parse(Json.Write(value), out _) ?? new FavoriteTracks() : new FavoriteTracks();

        public List<object> ToJsonValue() => _list.Select(t => (object)new Dictionary<string, object>
        {
            ["added"] = FormatDate(t.Added),
            ["artist"] = t.Artist,
            ["station"] = t.Station,
            ["title"] = t.Title,
        }).ToList();

        public string ToJson() => Json.Write(ToJsonValue());

        public FavoriteTrack Find(string title, string artist)
        {
            title = (title ?? "").Trim();
            artist = (artist ?? "").Trim();
            return _list.FirstOrDefault(t => string.Equals(t.Title, title, StringComparison.CurrentCultureIgnoreCase) &&
                                             string.Equals(t.Artist, artist, StringComparison.CurrentCultureIgnoreCase));
        }

        /// <summary>Aggiunge il brano; se c'è già (stesso titolo e artista, maiuscole ignorate) restituisce quello esistente.</summary>
        public FavoriteTrack Add(string title, string artist, string station, DateTime utc, out bool alreadyPresent)
        {
            title = (title ?? "").Trim();
            artist = (artist ?? "").Trim();
            if (title.Length == 0) { title = artist; artist = ""; }
            var existing = Find(title, artist);
            alreadyPresent = existing != null;
            if (existing != null) return existing;
            var t = new FavoriteTrack { Title = title, Artist = artist, Station = (station ?? "").Trim(), Added = utc };
            _list.Add(t);
            return t;
        }

        public void Remove(IEnumerable<FavoriteTrack> tracks)
        {
            var set = new HashSet<FavoriteTrack>(tracks);
            _list.RemoveAll(set.Contains);
        }

        /// <summary>
        /// Per la cronologia: il brano va in fondo (se c'era già viene spostato, con stazione e ora nuove)
        /// e si tengono solo gli ultimi <paramref name="limit"/>. False se era già l'ultimo (niente da salvare).
        /// </summary>
        public bool Record(string title, string artist, string station, DateTime utc, int limit)
        {
            title = (title ?? "").Trim();
            artist = (artist ?? "").Trim();
            if (title.Length == 0) { title = artist; artist = ""; }
            if (title.Length == 0) return false;
            var existing = Find(title, artist);
            if (existing != null && existing == _list.LastOrDefault()) return false;
            if (existing != null) _list.Remove(existing);
            _list.Add(new FavoriteTrack { Title = title, Artist = artist, Station = (station ?? "").Trim(), Added = utc });
            while (limit > 0 && _list.Count > limit) _list.RemoveAt(0);
            return true;
        }

        /// <summary>Aggiunge i brani che mancano (per l'importazione di un backup). Restituisce quanti.</summary>
        public int Merge(FavoriteTracks other)
        {
            int added = 0;
            foreach (var t in other.Tracks)
            {
                Add(t.Title, t.Artist, t.Station, t.Added, out bool present);
                if (!present) added++;
            }
            _list.Sort((a, b) => a.Added.CompareTo(b.Added));
            return added;
        }

        /// <summary>Stazioni presenti, in ordine alfabetico.</summary>
        public List<string> Stations() =>
            _list.Select(t => t.Station).Where(s => s.Length > 0).Distinct().OrderBy(s => s, StringComparer.CurrentCultureIgnoreCase).ToList();

        public static string Fold(string s)
        {
            var d = (s ?? "").Normalize(NormalizationForm.FormD);
            var sb = new StringBuilder(d.Length);
            foreach (char c in d)
                if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(char.ToLowerInvariant(c));
            return sb.ToString();
        }

        /// <summary>
        /// Brani che contengono tutte le parole di <paramref name="query"/> (in titolo, artista o stazione; maiuscole e accenti ignorati),
        /// della stazione indicata (null = tutte).
        /// </summary>
        public List<FavoriteTrack> Matching(string query, string station)
        {
            var words = Fold(query).Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            return _list.Where(t =>
            {
                if (!string.IsNullOrEmpty(station) && t.Station != station) return false;
                string hay = Fold(t.Title + " " + t.Artist + " " + t.Station);
                return words.All(w => hay.Contains(w));
            }).ToList();
        }

        /// <summary>CSV per Excel (separatore ";", UTF-8 con BOM, date italiane nell'ora locale).</summary>
        public static string Csv(IEnumerable<FavoriteTrack> tracks)
        {
            string F(string s) => "\"" + (s ?? "").Replace("\"", "\"\"") + "\"";
            var sb = new StringBuilder("﻿Titolo;Artista;Stazione;Aggiunto il\r\n");
            foreach (var t in tracks)
                sb.Append($"{F(t.Title)};{F(t.Artist)};{F(t.Station)};{F(t.Added.ToLocalTime().ToString("dd/MM/yyyy HH:mm", CultureInfo.InvariantCulture))}\r\n");
            return sb.ToString();
        }

        public static string SearchUrl(FavoriteTrack t, TrackSearchSite site)
        {
            string q = Uri.EscapeDataString(t.SearchText);
            switch (site)
            {
                case TrackSearchSite.YouTubeMusic: return "https://music.youtube.com/search?q=" + q;
                case TrackSearchSite.Spotify: return "https://open.spotify.com/search/" + q;
                case TrackSearchSite.AppleMusic: return "https://music.apple.com/it/search?term=" + q;
                default: return "https://www.youtube.com/results?search_query=" + q;
            }
        }
    }
}
