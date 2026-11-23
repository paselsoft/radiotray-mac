using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace RadioTray
{
    /// <summary>Playlist HLS (.m3u8): "master" con le varianti oppure "media" con i segmenti.</summary>
    public sealed class HlsPlaylist
    {
        public sealed class Variant
        {
            public string Url;
            public int Bandwidth;
            public string Codecs = "";
            public bool HasVideo;
        }

        public sealed class Segment
        {
            public string Url;
            public double Duration;
            public long Sequence;
        }

        public List<Variant> Variants = new List<Variant>();
        public List<Segment> Segments = new List<Segment>();
        public double TargetDuration = 6;
        public long MediaSequence;
        public bool EndList;
        /// <summary>Segmenti fMP4/CMAF (EXT-X-MAP): non ancora gestiti.</summary>
        public bool HasInitSegment;
        /// <summary>Segmenti cifrati (EXT-X-KEY diverso da NONE): non gestiti.</summary>
        public bool Encrypted;

        public bool IsMaster => Variants.Count > 0;

        private static string Resolve(string uri, Uri baseUri) =>
            Uri.TryCreate(baseUri, uri.Trim(), out var u) ? u.AbsoluteUri : null;

        /// <summary>Gli attributi di una riga "#EXT-X-…:A=1,B="x,y"".</summary>
        public static Dictionary<string, string> Attributes(string line)
        {
            var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            int colon = line.IndexOf(':');
            if (colon < 0) return result;
            string s = line.Substring(colon + 1);
            int i = 0;
            while (i < s.Length)
            {
                int eq = s.IndexOf('=', i);
                if (eq < 0) break;
                string key = s.Substring(i, eq - i).Trim();
                i = eq + 1;
                string value;
                if (i < s.Length && s[i] == '"')
                {
                    int end = s.IndexOf('"', i + 1);
                    if (end < 0) end = s.Length;
                    value = s.Substring(i + 1, end - i - 1);
                    i = Math.Min(s.Length, end + 1);
                }
                else
                {
                    int end = s.IndexOf(',', i);
                    if (end < 0) end = s.Length;
                    value = s.Substring(i, end - i).Trim();
                    i = end;
                }
                result[key] = value;
                if (i < s.Length && s[i] == ',') i++;
            }
            return result;
        }

        public static HlsPlaylist Parse(string text, Uri baseUri)
        {
            var p = new HlsPlaylist();
            if (text == null) return p;
            var lines = text.Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None).Select(l => l.Trim()).ToList();
            Variant pendingVariant = null;
            double pendingDuration = -1;
            long sequence = 0;
            bool sequenceSet = false;
            foreach (var line in lines)
            {
                if (line.Length == 0) continue;
                if (line.StartsWith("#EXT-X-STREAM-INF", StringComparison.OrdinalIgnoreCase))
                {
                    var a = Attributes(line);
                    pendingVariant = new Variant();
                    if (a.TryGetValue("BANDWIDTH", out var bw)) int.TryParse(bw, NumberStyles.Integer, CultureInfo.InvariantCulture, out pendingVariant.Bandwidth);
                    if (a.TryGetValue("CODECS", out var codecs)) pendingVariant.Codecs = codecs;
                    pendingVariant.HasVideo = a.ContainsKey("RESOLUTION") || pendingVariant.Codecs.IndexOf("avc", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                              pendingVariant.Codecs.IndexOf("hvc", StringComparison.OrdinalIgnoreCase) >= 0;
                }
                else if (line.StartsWith("#EXT-X-TARGETDURATION:", StringComparison.OrdinalIgnoreCase))
                {
                    double.TryParse(line.Substring(22), NumberStyles.Float, CultureInfo.InvariantCulture, out p.TargetDuration);
                }
                else if (line.StartsWith("#EXT-X-MEDIA-SEQUENCE:", StringComparison.OrdinalIgnoreCase))
                {
                    if (long.TryParse(line.Substring(22), NumberStyles.Integer, CultureInfo.InvariantCulture, out var ms))
                    {
                        p.MediaSequence = ms;
                        if (!sequenceSet) { sequence = ms; sequenceSet = true; }
                    }
                }
                else if (line.StartsWith("#EXTINF:", StringComparison.OrdinalIgnoreCase))
                {
                    string d = line.Substring(8);
                    int comma = d.IndexOf(',');
                    if (comma >= 0) d = d.Substring(0, comma);
                    double.TryParse(d, NumberStyles.Float, CultureInfo.InvariantCulture, out pendingDuration);
                    if (pendingDuration < 0) pendingDuration = 0;
                }
                else if (line.StartsWith("#EXT-X-ENDLIST", StringComparison.OrdinalIgnoreCase))
                {
                    p.EndList = true;
                }
                else if (line.StartsWith("#EXT-X-MAP", StringComparison.OrdinalIgnoreCase))
                {
                    p.HasInitSegment = true;
                }
                else if (line.StartsWith("#EXT-X-KEY", StringComparison.OrdinalIgnoreCase))
                {
                    var a = Attributes(line);
                    if (a.TryGetValue("METHOD", out var m) && !m.Equals("NONE", StringComparison.OrdinalIgnoreCase)) p.Encrypted = true;
                }
                else if (!line.StartsWith("#", StringComparison.Ordinal))
                {
                    string url = Resolve(line, baseUri);
                    if (url == null) continue;
                    if (pendingVariant != null)
                    {
                        pendingVariant.Url = url;
                        p.Variants.Add(pendingVariant);
                        pendingVariant = null;
                    }
                    else
                    {
                        p.Segments.Add(new Segment { Url = url, Duration = Math.Max(0, pendingDuration), Sequence = sequence++ });
                        pendingDuration = -1;
                    }
                }
            }
            return p;
        }

        /// <summary>
        /// La variante da ascoltare: solo audio se c'è, la qualità più alta fino a 320 kbit/s
        /// (altrimenti la più bassa disponibile).
        /// </summary>
        public Variant ChooseVariant()
        {
            if (Variants.Count == 0) return null;
            var pool = Variants.Where(v => !v.HasVideo).ToList();
            if (pool.Count == 0) pool = Variants;
            var good = pool.Where(v => v.Bandwidth <= 320000).OrderByDescending(v => v.Bandwidth).FirstOrDefault();
            return good ?? pool.OrderBy(v => v.Bandwidth).First();
        }
    }
}
