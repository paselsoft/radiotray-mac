using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace RadioTray
{
    /// <summary>
    /// Il file di backup della versione per Mac (RadioTray-backup.json, "format": "radiotray-mac-backup"):
    /// stazioni, brani preferiti, ascoltati di recente e impostazioni. Windows lo legge e lo scrive nello stesso formato,
    /// così si passa dal Mac al PC e viceversa.
    /// </summary>
    public sealed class Backup
    {
        public const string Format = "radiotray-mac-backup";

        public List<object> Bookmarks;   // contenuto di bookmarks.json (null se assente)
        public FavoriteTracks Favorites = new FavoriteTracks();
        public FavoriteTracks History = new FavoriteTracks();
        public Dictionary<string, object> Settings = new Dictionary<string, object>();
        public string AppVersion;
        public DateTime? Created;

        public int StationCount
        {
            get
            {
                if (Bookmarks == null) return 0;
                var b = RadioTray.Bookmarks.Parse(Json.Write(Bookmarks), out _);
                return b?.StationCount ?? 0;
            }
        }

        public static Backup Parse(string text, out string error)
        {
            error = null;
            object root;
            try { root = Json.Parse(text); }
            catch (Json.JsonException) { root = null; }
            if (!(root is Dictionary<string, object> d) || !(d.TryGetValue("format", out var f) && f as string == Format))
            {
                error = "Il file non è un backup di RadioTray.";
                return null;
            }
            if (d.TryGetValue("version", out var v) && v is double ver && ver > 1)
            {
                error = "Il backup è stato creato da una versione più recente di RadioTray: aggiorna l'app e riprova.";
                return null;
            }
            foreach (var key in new[] { "bookmarks", "favorites", "history" })
            {
                if (d.TryGetValue(key, out var section) && section != null && !(section is List<object>))
                {
                    error = $"Il backup è danneggiato (sezione \"{key}\").";
                    return null;
                }
            }
            var b = new Backup();
            if (d.TryGetValue("bookmarks", out var bm) && bm is List<object> bl && bl.Count > 0)
            {
                if (RadioTray.Bookmarks.Parse(Json.Write(bl), out string be) == null)
                {
                    error = "Le stazioni nel backup non sono valide: " + be;
                    return null;
                }
                b.Bookmarks = bl;
            }
            if (d.TryGetValue("favorites", out var fav)) b.Favorites = FavoriteTracks.FromJsonValue(fav);
            if (d.TryGetValue("history", out var his)) b.History = FavoriteTracks.FromJsonValue(his);
            if (d.TryGetValue("settings", out var s) && s is Dictionary<string, object> sd) b.Settings = sd;
            b.AppVersion = d.TryGetValue("app", out var app) ? app as string : null;
            if (d.TryGetValue("created", out var c) && c is string cs) b.Created = FavoriteTracks.ParseDate(cs);
            return b;
        }

        public string ToJson()
        {
            var root = new Dictionary<string, object>
            {
                ["app"] = AppVersion ?? "",
                ["bookmarks"] = Bookmarks ?? new List<object>(),
                ["created"] = FavoriteTracks.FormatDate(Created ?? DateTime.UtcNow),
                ["favorites"] = Favorites.ToJsonValue(),
                ["format"] = Format,
                ["history"] = History.ToJsonValue(),
                ["settings"] = Settings,
                ["version"] = 1,
            };
            return Json.Write(root);
        }

        /// <summary>Un elenco di testi dalle impostazioni (per esempio le stazioni con titolo e artista al contrario).</summary>
        public List<string> SettingStrings(string key) =>
            Settings.TryGetValue(key, out var v) && v is List<object> l ? l.OfType<string>().ToList() : new List<string>();

        public string SettingString(string key) => Settings.TryGetValue(key, out var v) ? v as string : null;

        public int? SettingInt(string key) =>
            Settings.TryGetValue(key, out var v) && v is double d ? (int?)(int)Math.Round(d, MidpointRounding.AwayFromZero) : null;

        public bool? SettingBool(string key) =>
            Settings.TryGetValue(key, out var v) ? (v is bool b ? b : v is double d ? d != 0 : (bool?)null) : null;

        // nomi delle impostazioni della versione per Mac
        public const string KeyVolume = "volume-level";
        public const string KeyLastGroup = "last-station-group";
        public const string KeyLastStation = "last-station";
        public const string KeyNotifications = "notifications";
        public const string KeyLastUrl = "last-opened-url";
        public const string KeySwapped = "swapped-title-artist-stations";
        public const string KeyIgnored = "ignored-title-stations";
    }
}
