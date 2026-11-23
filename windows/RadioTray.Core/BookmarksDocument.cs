using System;
using System.Collections.Generic;
using System.Linq;

namespace RadioTray
{
    /// <summary>
    /// bookmarks.json da modificare (editor delle stazioni, Aggiungi alle stazioni, importazione): lavora sul JSON
    /// originale, così i campi che l'editor non conosce (image, mirrors, direct…) restano com'erano.
    /// I metodi restituiscono un messaggio d'errore, oppure null se tutto va bene.
    /// </summary>
    public sealed class BookmarksDocument
    {
        public sealed class DocGroup
        {
            internal Dictionary<string, object> Raw;
            public string Name => Raw.TryGetValue("group", out var v) ? (v as string ?? "").Trim() : "";
            public bool IsRoot => Name == RadioTray.Bookmarks.RootGroupName;
            public string DisplayName => IsRoot ? "(senza gruppo)" : Name;
            internal List<object> StationList
            {
                get
                {
                    if (!(Raw.TryGetValue("stations", out var v) && v is List<object> l))
                    {
                        l = new List<object>();
                        Raw["stations"] = l;
                    }
                    return l;
                }
            }
            public List<DocStation> Stations => StationList.OfType<Dictionary<string, object>>().Select(d => new DocStation { Raw = d, Group = this }).ToList();
        }

        public sealed class DocStation
        {
            internal Dictionary<string, object> Raw;
            public DocGroup Group;
            private string Get(string k) => Raw.TryGetValue(k, out var v) ? (v as string ?? "").Trim() : "";
            public string Name => Get("name");
            public string Url => Get("url");
            public bool Notifications => !(Raw.TryGetValue("notifications", out var v) && v is bool b && !b);
            public override bool Equals(object obj) => obj is DocStation s && ReferenceEquals(s.Raw, Raw);
            public override int GetHashCode() => Raw.GetHashCode();
        }

        private readonly List<object> _root;

        private BookmarksDocument(List<object> root) { _root = root; }

        public static BookmarksDocument Parse(string text, out string error)
        {
            if (RadioTray.Bookmarks.Parse(text, out error) == null) return null;
            return new BookmarksDocument((List<object>)Json.Parse(text));
        }

        public static BookmarksDocument Empty() => new BookmarksDocument(new List<object>());

        public List<object> JsonValue => _root;

        public string ToJson() => Json.Write(_root);

        public List<DocGroup> Groups => _root.OfType<Dictionary<string, object>>().Select(d => new DocGroup { Raw = d }).ToList();

        public DocGroup GroupNamed(string name) => Groups.FirstOrDefault(g => g.Name == name);

        public static bool IsWebUrl(string url) =>
            Uri.TryCreate((url ?? "").Trim(), UriKind.Absolute, out var u) && (u.Scheme == Uri.UriSchemeHttp || u.Scheme == Uri.UriSchemeHttps);

        public string AddGroup(string name, out DocGroup created)
        {
            created = null;
            name = (name ?? "").Trim();
            if (name.Length == 0) return "Serve un nome per il gruppo";
            if (GroupNamed(name) != null) return $"C'è già un gruppo chiamato \"{name}\"";
            var raw = new Dictionary<string, object> { ["group"] = name, ["stations"] = new List<object>() };
            // il gruppo "root" resta in fondo
            int rootIndex = _root.FindIndex(o => o is Dictionary<string, object> d && (d.TryGetValue("group", out var g) ? g as string : null) == RadioTray.Bookmarks.RootGroupName);
            if (name != RadioTray.Bookmarks.RootGroupName && rootIndex >= 0) _root.Insert(rootIndex, raw);
            else _root.Add(raw);
            created = new DocGroup { Raw = raw };
            return null;
        }

        public DocGroup RootGroup()
        {
            var root = GroupNamed(RadioTray.Bookmarks.RootGroupName);
            if (root == null) AddGroup(RadioTray.Bookmarks.RootGroupName, out root);
            return root;
        }

        public string RenameGroup(DocGroup group, string name)
        {
            name = (name ?? "").Trim();
            if (name.Length == 0) return "Serve un nome per il gruppo";
            if (group.IsRoot) return "Il gruppo delle stazioni senza gruppo non si può rinominare";
            if (name == group.Name) return null;
            if (GroupNamed(name) != null) return $"C'è già un gruppo chiamato \"{name}\"";
            group.Raw["group"] = name;
            return null;
        }

        public string RemoveGroup(DocGroup group)
        {
            _root.Remove(group.Raw);
            return null;
        }

        /// <summary>Sposta il gruppo di <paramref name="delta"/> posizioni (-1 su, +1 giù).</summary>
        public string MoveGroup(DocGroup group, int delta)
        {
            int i = _root.IndexOf(group.Raw), j = i + delta;
            if (i < 0 || j < 0 || j >= _root.Count) return null;
            _root.RemoveAt(i);
            _root.Insert(j, group.Raw);
            return null;
        }

        public string AddStation(DocGroup group, string name, string url, out DocStation created)
        {
            created = null;
            name = (name ?? "").Trim();
            url = (url ?? "").Trim();
            if (name.Length == 0) return "Serve un nome per la stazione";
            if (!IsWebUrl(url)) return "L'indirizzo deve cominciare con http:// o https://";
            if (group.Stations.Any(s => s.Name == name)) return $"Nel gruppo \"{group.DisplayName}\" c'è già una stazione chiamata \"{name}\"";
            var raw = new Dictionary<string, object> { ["name"] = name, ["url"] = url };
            group.StationList.Add(raw);
            created = new DocStation { Raw = raw, Group = group };
            return null;
        }

        public string RenameStation(DocStation station, string name)
        {
            name = (name ?? "").Trim();
            if (name.Length == 0) return "Serve un nome per la stazione";
            if (name == station.Name) return null;
            if (station.Group.Stations.Any(s => s.Name == name)) return $"Nel gruppo \"{station.Group.DisplayName}\" c'è già una stazione chiamata \"{name}\"";
            station.Raw["name"] = name;
            return null;
        }

        public string SetUrl(DocStation station, string url)
        {
            url = (url ?? "").Trim();
            if (!IsWebUrl(url)) return "L'indirizzo deve cominciare con http:// o https://";
            station.Raw["url"] = url;
            return null;
        }

        public void SetNotifications(DocStation station, bool on)
        {
            if (on) station.Raw.Remove("notifications");
            else station.Raw["notifications"] = false;
        }

        public void RemoveStation(DocStation station) => station.Group.StationList.Remove(station.Raw);

        public string MoveStation(DocStation station, int delta)
        {
            var list = station.Group.StationList;
            int i = list.IndexOf(station.Raw), j = i + delta;
            if (i < 0 || j < 0 || j >= list.Count) return null;
            list.RemoveAt(i);
            list.Insert(j, station.Raw);
            return null;
        }

        public string MoveStationToGroup(DocStation station, DocGroup target, out DocStation moved)
        {
            moved = station;
            if (ReferenceEquals(station.Group.Raw, target.Raw)) return null;
            if (target.Stations.Any(s => s.Name == station.Name)) return $"Nel gruppo \"{target.DisplayName}\" c'è già una stazione chiamata \"{station.Name}\"";
            station.Group.StationList.Remove(station.Raw);
            target.StationList.Add(station.Raw);
            moved = new DocStation { Raw = station.Raw, Group = target };
            return null;
        }

        private static string UrlKey(string url)
        {
            string u = (url ?? "").ToLowerInvariant();
            if (u.StartsWith("https://", StringComparison.Ordinal)) u = u.Substring(8);
            else if (u.StartsWith("http://", StringComparison.Ordinal)) u = u.Substring(7);
            return u.TrimEnd('/');
        }

        public bool ContainsUrl(string url) => Groups.SelectMany(g => g.Stations).Any(s => UrlKey(s.Url) == UrlKey(url));

        /// <summary>Aggiunge le stazioni che mancano (stesso indirizzo, http/https e "/" finale ignorati). Restituisce quante.</summary>
        public int Merge(Bookmarks extra)
        {
            int added = 0;
            foreach (var g in extra.Groups)
            {
                foreach (var s in g.Stations)
                {
                    if (ContainsUrl(s.Url)) continue;
                    var group = GroupNamed(g.Name);
                    if (group == null && AddGroup(g.Name, out group) != null) continue;
                    if (AddStation(group, s.Name, s.Url, out var created) != null) continue;   // nome già presente nel gruppo
                    if (!s.Notifications) SetNotifications(created, false);
                    if (s.Direct) created.Raw["direct"] = true;
                    if (s.Mirrors.Count > 0) created.Raw["mirrors"] = s.Mirrors.Cast<object>().ToList();
                    if (s.Image != null) created.Raw["image"] = s.Image;
                    added++;
                }
            }
            return added;
        }
    }
}
