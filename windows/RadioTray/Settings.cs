using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace RadioTray
{
    /// <summary>Le impostazioni, in %APPDATA%\RadioTray\settings.json.</summary>
    internal sealed class Settings
    {
        public string LastGroup;
        public string LastStation;
        public string LastOpenedUrl;
        public int Volume = 80;
        public bool Notifications = true;
        public bool PlayOnStart;
        /// <summary>Stazioni che scrivono "Titolo - Artista" invece di "Artista - Titolo".</summary>
        public List<string> SwappedStations = new List<string>();
        /// <summary>Stazioni di cui non si mostrano i titoli (sbagliati o vecchi).</summary>
        public List<string> IgnoredTitleStations = new List<string>();

        public static Settings Load()
        {
            var s = new Settings();
            try
            {
                if (!File.Exists(AppPaths.Settings)) return s;
                if (!(Json.Parse(File.ReadAllText(AppPaths.Settings, Encoding.UTF8)) is Dictionary<string, object> d)) return s;
                string Str(string k) => d.TryGetValue(k, out var v) ? v as string : null;
                bool Bool(string k, bool f) => d.TryGetValue(k, out var v) && v is bool b ? b : f;
                s.LastGroup = Str("lastGroup");
                s.LastStation = Str("lastStation");
                s.LastOpenedUrl = Str("lastOpenedUrl");
                if (d.TryGetValue("volume", out var vol) && vol is double dv) s.Volume = Math.Max(0, Math.Min(100, (int)dv));
                s.Notifications = Bool("notifications", true);
                s.PlayOnStart = Bool("playOnStart", false);
                List<string> Strings(string k) => d.TryGetValue(k, out var v) && v is List<object> l
                    ? l.OfType<string>().ToList() : new List<string>();
                s.SwappedStations = Strings("swappedStations");
                s.IgnoredTitleStations = Strings("ignoredTitleStations");
            }
            catch (Exception e)
            {
                Log.Write("Impostazioni non leggibili, si usano quelle predefinite: " + e.Message);
            }
            return s;
        }

        public void Save()
        {
            var d = new Dictionary<string, object>
            {
                ["lastGroup"] = LastGroup,
                ["lastStation"] = LastStation,
                ["lastOpenedUrl"] = LastOpenedUrl,
                ["volume"] = Volume,
                ["notifications"] = Notifications,
                ["playOnStart"] = PlayOnStart,
                ["swappedStations"] = SwappedStations,
                ["ignoredTitleStations"] = IgnoredTitleStations,
            };
            try
            {
                AppPaths.Ensure();
                string tmp = AppPaths.Settings + ".tmp";
                File.WriteAllText(tmp, Json.Write(d), new UTF8Encoding(false));
                if (File.Exists(AppPaths.Settings)) File.Replace(tmp, AppPaths.Settings, null);
                else File.Move(tmp, AppPaths.Settings);
            }
            catch (Exception e)
            {
                Log.Write("Impossibile salvare le impostazioni: " + e.Message);
            }
        }
    }
}
