using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace RadioTray
{
    /// <summary>Playlist PLS, M3U, ASX e XSPF (come src/RTPlaylistParser.m della versione Mac).</summary>
    public static class PlaylistParser
    {
        private static readonly Encoding StrictUtf8 = new UTF8Encoding(false, true);
        public static readonly Encoding Latin1 = Encoding.GetEncoding(28591);

        private static readonly HashSet<string> AudioExtensions = new HashSet<string>
        {
            "mp3", "aac", "aacp", "m4a", "mp4", "ogg", "oga", "opus", "flac", "wav", "m3u8",
        };

        /// <summary>Testo della playlist, oppure null se i dati sono binari (audio).</summary>
        public static string TextFromData(byte[] data, int length = -1)
        {
            if (data == null) return null;
            if (length < 0) length = data.Length;
            if (length == 0) return null;
            for (int i = 0; i < Math.Min(length, 512); i++)
            {
                if (data[i] == 0) return null;
            }
            string text = null;
            // il blocco letto (4 KB) può tagliare a metà un carattere UTF-8: si riprova senza gli ultimi byte
            for (int cut = 0; cut <= 3 && text == null && length > cut; cut++)
            {
                try { text = StrictUtf8.GetString(data, 0, length - cut); } catch (ArgumentException) { }
            }
            if (text == null) text = Latin1.GetString(data, 0, length);
            if (text.StartsWith("\uFEFF", StringComparison.Ordinal)) text = text.Substring(1);
            return text;
        }

        private static List<string> Lines(string text) =>
            text.Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None).Select(l => l.Trim()).Where(l => l.Length > 0).ToList();

        private static string XmlUnescape(string s) =>
            s.Replace("&lt;", "<").Replace("&gt;", ">").Replace("&quot;", "\"").Replace("&apos;", "'").Replace("&amp;", "&").Trim();

        /// <summary>URL assoluto, oppure relativo risolto rispetto a baseUri; null se non è un URL utilizzabile.</summary>
        private static string Resolve(string candidate, Uri baseUri)
        {
            if (string.IsNullOrEmpty(candidate)) return null;
            string lower = candidate.ToLowerInvariant();
            if (lower.StartsWith("http://", StringComparison.Ordinal) || lower.StartsWith("https://", StringComparison.Ordinal) || lower.StartsWith("mms://", StringComparison.Ordinal) ||
                lower.StartsWith("rtsp://", StringComparison.Ordinal) || lower.StartsWith("icy://", StringComparison.Ordinal))
                return candidate;
            if (candidate.Contains("://")) return null;   // schema sconosciuto
            if (baseUri == null) return null;
            return Uri.TryCreate(baseUri, candidate, out var u) ? u.AbsoluteUri : null;
        }

        private static List<string> Matches(string text, string pattern)
        {
            var re = new Regex(pattern, RegexOptions.IgnoreCase | RegexOptions.Singleline);
            var output = new List<string>();
            foreach (Match m in re.Matches(text))
            {
                for (int i = 1; i < m.Groups.Count; i++)
                {
                    if (m.Groups[i].Success)
                    {
                        output.Add(XmlUnescape(m.Groups[i].Value));
                        break;
                    }
                }
            }
            return output;
        }

        public static bool UrlLooksDirect(string url)
        {
            if (!Uri.TryCreate(url, UriKind.Absolute, out var u)) return false;
            string path = u.AbsolutePath;
            int slash = path.LastIndexOf('/');
            string file = slash >= 0 ? path.Substring(slash + 1) : path;
            int dot = file.LastIndexOf('.');
            if (dot < 0) return false;
            return AudioExtensions.Contains(file.Substring(dot + 1).ToLowerInvariant());
        }

        private static string BareType(string contentType)
        {
            string ct = (contentType ?? "").ToLowerInvariant();
            int semi = ct.IndexOf(';');
            if (semi >= 0) ct = ct.Substring(0, semi);
            return ct.Trim();
        }

        public static bool ContentTypeIsAudio(string contentType)
        {
            string ct = BareType(contentType);
            if (ct.StartsWith("audio/", StringComparison.Ordinal))
                return !(ct.Contains("mpegurl") || ct.Contains("scpls") || ct.Contains("x-ms-wax"));
            return ct == "application/ogg" || ct == "video/mp2t" || ct == "application/aacp";
        }

        public static bool IsHls(string contentType, byte[] data, int length = -1)
        {
            if ((contentType ?? "").ToLowerInvariant().Contains("application/vnd.apple.mpegurl")) return true;
            string text = TextFromData(data, length);
            return text != null && text.Contains("#EXT-X-");
        }

        /// <summary>
        /// Gli indirizzi contenuti nella playlist; null se i dati non sono una playlist (per esempio audio o HTML),
        /// elenco vuoto se è una playlist senza voci.
        /// </summary>
        public static List<string> UrlsFromData(byte[] data, string contentType, Uri baseUri, out string format, int length = -1)
        {
            format = null;
            string ct = (contentType ?? "").ToLowerInvariant();
            string text = TextFromData(data, length);
            if (text == null) return null;
            string lower = text.ToLowerInvariant();
            var urls = new List<string>();

            if (ct.Contains("scpls") || ct.Contains("pls+xml") || lower.Contains("[playlist]"))
            {
                format = "PLS";
                foreach (var line in Lines(text))
                {
                    if (!line.ToLowerInvariant().StartsWith("file", StringComparison.Ordinal)) continue;
                    int eq = line.IndexOf('=');
                    if (eq < 0) continue;
                    string u = Resolve(line.Substring(eq + 1).Trim(), baseUri);
                    if (u != null) urls.Add(u);
                }
            }
            else if (ct.Contains("x-ms-asf") || ct.Contains("x-ms-wax") || ct.Contains("x-ms-asx") || lower.Contains("<asx"))
            {
                format = "ASX";
                foreach (var u in Matches(text, "<ref\\s+href\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"))
                {
                    string r = Resolve(u, baseUri);
                    if (r != null) urls.Add(r);
                }
            }
            else if (ct.Contains("xspf") || (lower.Contains("<playlist") && lower.Contains("xspf")))
            {
                format = "XSPF";
                foreach (var u in Matches(text, "<location>\\s*(.*?)\\s*</location>"))
                {
                    string r = Resolve(u, baseUri);
                    if (r != null) urls.Add(r);
                }
            }
            else
            {
                bool declared = ct.Contains("mpegurl") || ct.Contains("text/uri-list") || lower.StartsWith("#extm3u", StringComparison.Ordinal);
                bool loose = ct.StartsWith("text/", StringComparison.Ordinal) || ct.Length == 0 || ct.Contains("octet-stream");
                if (!declared && !loose) return null;
                // M3U o elenco di URL: ogni riga non commentata è un URL; se il tipo non lo dichiara,
                // tutte le righe devono essere commenti o URL (altrimenti è, per esempio, una pagina HTML)
                foreach (var line in Lines(text))
                {
                    if (line.StartsWith("#", StringComparison.Ordinal)) continue;
                    string u = Resolve(line, declared ? baseUri : null);
                    if (u != null) urls.Add(u);
                    else if (!declared) return null;
                }
                if (!declared && urls.Count == 0) return null;
                format = "M3U";
            }
            return urls.Distinct().ToList();
        }
    }
}
