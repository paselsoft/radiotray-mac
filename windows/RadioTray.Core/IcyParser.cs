using System;
using System.Collections.Generic;
using System.Text;

namespace RadioTray
{
    /// <summary>
    /// Separa l'audio dai metadati ICY (Shoutcast/Icecast con "Icy-MetaData: 1"): ogni icy-metaint byte di audio
    /// arriva un byte di lunghezza (×16) e il blocco "StreamTitle='...';". Così una sola connessione serve
    /// sia per l'audio sia per i titoli.
    /// </summary>
    public sealed class IcyParser
    {
        private enum Phase { Audio, Length, Meta }

        private readonly int _metaInterval;
        private Phase _phase = Phase.Audio;
        private int _remaining;
        private readonly List<byte> _meta = new List<byte>();

        /// <param name="metaInterval">icy-metaint; 0 = lo stream non ha metadati (tutto audio)</param>
        public IcyParser(int metaInterval)
        {
            _metaInterval = metaInterval;
            _remaining = metaInterval;
        }

        /// <summary>
        /// Elabora un blocco di rete: l'audio va ad <paramref name="audio"/> (anche a pezzi), i titoli trovati
        /// vengono restituiti nell'ordine.
        /// </summary>
        public List<string> Feed(byte[] data, int offset, int count, Action<byte[], int, int> audio)
        {
            var titles = new List<string>();
            if (_metaInterval <= 0)
            {
                if (count > 0) audio?.Invoke(data, offset, count);
                return titles;
            }
            int i = offset, end = offset + count;
            while (i < end)
            {
                switch (_phase)
                {
                    case Phase.Audio:
                    {
                        int take = Math.Min(_remaining, end - i);
                        if (take > 0) audio?.Invoke(data, i, take);
                        i += take;
                        _remaining -= take;
                        if (_remaining == 0) _phase = Phase.Length;
                        break;
                    }
                    case Phase.Length:
                    {
                        int metaLength = data[i++] * 16;
                        if (metaLength == 0)
                        {
                            _phase = Phase.Audio;
                            _remaining = _metaInterval;
                        }
                        else
                        {
                            _phase = Phase.Meta;
                            _remaining = metaLength;
                            _meta.Clear();
                        }
                        break;
                    }
                    case Phase.Meta:
                    {
                        int take = Math.Min(_remaining, end - i);
                        for (int k = 0; k < take; k++) _meta.Add(data[i + k]);
                        i += take;
                        _remaining -= take;
                        if (_remaining == 0)
                        {
                            string title = StreamTitleFromMetadata(_meta.ToArray());
                            if (title != null) titles.Add(title);
                            _phase = Phase.Audio;
                            _remaining = _metaInterval;
                        }
                        break;
                    }
                }
            }
            return titles;
        }

        private static readonly Encoding StrictUtf8 = new UTF8Encoding(false, true);

        public static string StreamTitleFromMetadata(byte[] metadata)
        {
            if (metadata == null) return null;
            // il blocco è riempito di zeri fino a un multiplo di 16
            int n = metadata.Length;
            while (n > 0 && metadata[n - 1] == 0) n--;
            string text;
            try { text = StrictUtf8.GetString(metadata, 0, n); }
            catch (ArgumentException) { text = PlaylistParser.Latin1.GetString(metadata, 0, n); }

            int key = text.IndexOf("StreamTitle=", StringComparison.OrdinalIgnoreCase);
            if (key < 0) return null;
            int start = key + "StreamTitle=".Length;
            if (start >= text.Length) return "";
            char quote = text[start];
            if (quote == '\'' || quote == '"')
            {
                start++;
                // il titolo può contenere apostrofi: la fine è la virgoletta seguita da ";" (o la fine del testo)
                int stop = text.IndexOf(quote + ";", start, StringComparison.Ordinal);
                if (stop < 0)
                {
                    stop = text.Length;
                    if (stop > start && text[stop - 1] == quote) stop--;
                }
                return text.Substring(start, stop - start);
            }
            int semi = text.IndexOf(';', start);
            return text.Substring(start, (semi < 0 ? text.Length : semi) - start);
        }

        /// <summary>Il nome della stazione dall'intestazione icy-name; null se è generico o tecnico.</summary>
        public static string StationNameFromHeader(string value)
        {
            if (string.IsNullOrEmpty(value)) return null;
            string name = value;
            // le intestazioni HTTP arrivano come Latin-1: se in realtà erano UTF-8 ("Radio CittÃ "), si ricodifica
            bool latinOnly = true;
            foreach (char c in name) if (c > 0xFF) { latinOnly = false; break; }
            if (latinOnly)
            {
                try
                {
                    string utf8 = StrictUtf8.GetString(PlaylistParser.Latin1.GetBytes(name));
                    if (utf8.Length > 0) name = utf8;
                }
                catch (ArgumentException) { }
            }
            name = name.Trim();
            if (name.Length == 0) return null;
            // nome tecnico del server, non della radio: niente spazi e trattini bassi
            if (!name.Contains(" ") && name.Contains("_")) return null;
            string lower = name.ToLowerInvariant();
            foreach (var generic in new[] { "no name", "noname", "unspecified", "unknown", "-", "stream", "icecast", "shoutcast",
                                            "this is my server name", "default" })
            {
                if (lower == generic) return null;
            }
            return name;
        }
    }
}
