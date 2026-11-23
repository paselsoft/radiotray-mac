using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace RadioTray
{
    public sealed class Station
    {
        public string Name = "";
        public string Url = "";
        public string Image;
        public bool Notifications = true;
        public bool Direct;
        public List<string> Mirrors = new List<string>();
    }

    public sealed class Group
    {
        public string Name = "";
        public string Image;
        public List<Station> Stations = new List<Station>();
        public bool IsRoot => Name == Bookmarks.RootGroupName;
    }

    /// <summary>
    /// Il file bookmarks.json, nello stesso formato di Radiotray-NG e di RadioTray per Mac:
    /// [ { "group": "Nome", "stations": [ { "name": ..., "url": ... } ] } ]; il gruppo "root" va direttamente nel menu.
    /// </summary>
    public sealed class Bookmarks
    {
        public const string RootGroupName = "root";
        public List<Group> Groups = new List<Group>();

        public int StationCount => Groups.Sum(g => g.Stations.Count);

        public Group GroupNamed(string name) => Groups.FirstOrDefault(g => g.Name == name);

        public Station StationNamed(string name, string group) => GroupNamed(group)?.Stations.FirstOrDefault(s => s.Name == name);

        private static string Str(object v)
        {
            if (v is string s)
            {
                s = s.Trim();
                return s.Length > 0 ? s : null;
            }
            return null;
        }

        private static bool Bool(object v, bool fallback)
        {
            if (v is bool b) return b;
            if (v is double d) return d != 0;
            if (v is string s)
            {
                s = s.ToLowerInvariant();
                if (s == "true" || s == "1") return true;
                if (s == "false" || s == "0") return false;
            }
            return fallback;
        }

        public static Bookmarks FromFile(string path, out string error)
        {
            string text;
            try
            {
                text = File.ReadAllText(path, Encoding.UTF8);
            }
            catch (Exception e)
            {
                error = $"Impossibile leggere {Path.GetFileName(path)}: {e.Message}";
                return null;
            }
            return Parse(text, out error);
        }

        public static Bookmarks Parse(string text, out string error)
        {
            error = null;
            object root;
            try
            {
                root = Json.Parse(text);
            }
            catch (Json.JsonException e)
            {
                error = "Il file delle stazioni non è un JSON valido: " + e.Message;
                return null;
            }
            if (!(root is List<object> list))
            {
                error = "Il file delle stazioni deve contenere un elenco di gruppi: [ { \"group\": ..., \"stations\": [...] } ]";
                return null;
            }

            var result = new Bookmarks();
            var groupNames = new HashSet<string>();
            int index = 0;
            foreach (var g in list)
            {
                index++;
                if (!(g is Dictionary<string, object> go))
                {
                    error = $"Il gruppo n. {index} non è un oggetto JSON";
                    return null;
                }
                string groupName = Str(go.TryGetValue("group", out var gn) ? gn : null);
                if (groupName == null)
                {
                    error = $"Il gruppo n. {index} non ha il campo \"group\"";
                    return null;
                }
                if (!groupNames.Add(groupName))
                {
                    error = $"Il gruppo \"{groupName}\" compare due volte";
                    return null;
                }
                go.TryGetValue("stations", out var stationsValue);
                if (stationsValue != null && !(stationsValue is List<object>))
                {
                    error = $"Nel gruppo \"{groupName}\" il campo \"stations\" deve essere un elenco";
                    return null;
                }
                var group = new Group { Name = groupName, Image = Str(go.TryGetValue("image", out var gi) ? gi : null) };
                var stationNames = new HashSet<string>();
                foreach (var s in (stationsValue as List<object>) ?? new List<object>())
                {
                    if (!(s is Dictionary<string, object> so)) continue;
                    object Get(string key) => so.TryGetValue(key, out var v) ? v : null;
                    string name = Str(Get("name")), url = Str(Get("url"));
                    if (name == null || url == null)
                    {
                        error = $"Nel gruppo \"{groupName}\" c'è una stazione senza \"name\" o \"url\"";
                        return null;
                    }
                    // come Radiotray-NG: i nomi doppi nello stesso gruppo vengono ignorati
                    if (!stationNames.Add(name)) continue;
                    var station = new Station
                    {
                        Name = name,
                        Url = url,
                        Image = Str(Get("image")),
                        Notifications = Bool(Get("notifications"), true),
                        Direct = Bool(Get("direct"), false),
                    };
                    if (Get("mirrors") is List<object> mirrors)
                    {
                        foreach (var m in mirrors)
                        {
                            string u = Str(m);
                            if (u != null && (u.StartsWith("http://", StringComparison.Ordinal) || u.StartsWith("https://", StringComparison.Ordinal)) && u != url) station.Mirrors.Add(u);
                        }
                    }
                    group.Stations.Add(station);
                }
                result.Groups.Add(group);
            }
            return result;
        }
    }
}
