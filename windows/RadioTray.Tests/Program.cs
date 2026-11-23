// Test della logica senza interfaccia (stazioni, playlist, titoli, ICY, formati, messaggi del proxy).
// Gli stessi casi di tests/test_logic.m della versione Mac, dove la logica è la stessa.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using RadioTray;

static class Program
{
    static int checks, failures;

    static void Check(bool cond, [CallerArgumentExpression("cond")] string expr = "", [CallerLineNumber] int line = 0)
    {
        checks++;
        if (!cond) { failures++; Console.Error.WriteLine($"FALLITO riga {line}: {expr}"); }
    }

    static void Eq<T>(T got, T expected, [CallerArgumentExpression("got")] string expr = "", [CallerLineNumber] int line = 0)
    {
        checks++;
        if (!Equals(got, expected))
        {
            failures++;
            Console.Error.WriteLine($"FALLITO riga {line}: {expr}\n  ottenuto: {got}\n  atteso:   {expected}");
        }
    }

    static void EqList(IEnumerable<string> got, string[] expected, [CallerArgumentExpression("got")] string expr = "", [CallerLineNumber] int line = 0)
    {
        checks++;
        if (got == null || !got.SequenceEqual(expected))
        {
            failures++;
            Console.Error.WriteLine($"FALLITO riga {line}: {expr}\n  ottenuto: {(got == null ? "null" : string.Join(" | ", got))}\n  atteso:   {string.Join(" | ", expected)}");
        }
    }

    static byte[] D(string s) => Encoding.UTF8.GetBytes(s);

    static List<string> Parse(string text, string ct, out string format) =>
        PlaylistParser.UrlsFromData(D(text), ct, new Uri("http://radio.example.com/liste/stazione.pls"), out format);

    static void TestBookmarks()
    {
        string json = "[ {\"group\":\"Jazz\",\"image\":\"/tmp/j.png\",\"stations\":[{\"name\":\"A\",\"url\":\"http://a/x.pls\"}," +
                      "{\"name\":\"B\",\"url\":\"http://b\",\"notifications\":false,\"direct\":true},{\"name\":\"A\",\"url\":\"http://doppio\"}]}," +
                      "{\"group\":\"root\",\"stations\":[{\"name\":\"R\",\"url\":\"http://r\",\"mirrors\":[\"http://r2\",\"ftp://no\",\"http://r\"]}]}," +
                      "{\"group\":\"Vuoto\"} ]";
        var b = Bookmarks.Parse(json, out string error);
        Check(b != null);
        Eq(error, null);
        Eq(b.Groups.Count, 3);
        Eq(b.StationCount, 3);   // il doppione "A" viene scartato
        Eq(b.GroupNamed("Jazz").Image, "/tmp/j.png");
        Check(b.GroupNamed("root").IsRoot);
        Check(!b.GroupNamed("Jazz").IsRoot);
        Eq(b.StationNamed("A", "Jazz").Url, "http://a/x.pls");
        Check(b.StationNamed("A", "Jazz").Notifications);
        Check(!b.StationNamed("A", "Jazz").Direct);
        Check(!b.StationNamed("B", "Jazz").Notifications);
        Check(b.StationNamed("B", "Jazz").Direct);
        Eq(b.StationNamed("R", "root").Url, "http://r");
        EqList(b.StationNamed("R", "root").Mirrors, new[] { "http://r2" });
        Check(b.StationNamed("R", "Jazz") == null);
        Eq(b.GroupNamed("Vuoto").Stations.Count, 0);

        Check(Bookmarks.Parse("[ {\"group\":\"x\", ", out error) == null);
        Check(error.Contains("JSON"));
        Check(Bookmarks.Parse("{\"group\":\"x\"}", out error) == null);
        Check(error.Length > 0);
        Check(Bookmarks.Parse("[{\"stations\":[]}]", out error) == null);
        Check(error.Contains("group"));
        Check(Bookmarks.Parse("[{\"group\":\"a\",\"stations\":[{\"name\":\"x\"}]}]", out error) == null);
        Check(error.Contains("url"));
        Check(Bookmarks.Parse("[{\"group\":\"a\"},{\"group\":\"a\"}]", out error) == null);
        Check(error.Contains("due volte"));
        Eq(Bookmarks.Parse("[]", out _).Groups.Count, 0);
        // BOM all'inizio (Blocco note lo aggiunge)
        Check(Bookmarks.Parse("﻿[]", out _) != null);
    }

    static void TestJson()
    {
        var o = (Dictionary<string, object>)Json.Parse("{\"a\": [1, 2.5, -3e2], \"b\": \"x\\\"y\\u00e8\\/\", \"c\": true, \"d\": null}");
        Eq(((List<object>)o["a"]).Count, 3);
        Eq((double)((List<object>)o["a"])[2], -300.0);
        Eq((string)o["b"], "x\"yè/");
        Eq((bool)o["c"], true);
        Check(o["d"] == null);
        string w = Json.Write(new Dictionary<string, object> { ["url"] = "http://a/b", ["n"] = 70, ["list"] = new List<object> { "x" } });
        Check(!w.Contains("\\/"));
        var back = (Dictionary<string, object>)Json.Parse(w);
        Eq((string)back["url"], "http://a/b");
        Eq((double)back["n"], 70.0);
        try { Json.Parse("[1,\n 2,,]"); Check(false); }
        catch (Json.JsonException e) { Check(e.Message.Contains("riga 2")); }
    }

    static void TestBundled(string path)
    {
        var b = Bookmarks.FromFile(path, out string error);
        Check(b != null, $"{path}: {error}");
        if (b != null) Check(b.StationCount > 0);
        Console.WriteLine($"{Path.GetFileName(path)}: {b?.StationCount ?? 0} stazioni");
    }

    static void TestDirect()
    {
        Check(PlaylistParser.UrlLooksDirect("http://x/stream.mp3"));
        Check(PlaylistParser.UrlLooksDirect("https://x/a/b.AAC?token=1"));
        Check(PlaylistParser.UrlLooksDirect("https://x/live/master.m3u8"));
        Check(!PlaylistParser.UrlLooksDirect("http://x/listen.pls"));
        Check(!PlaylistParser.UrlLooksDirect("http://x/stream"));
        Check(!PlaylistParser.UrlLooksDirect("http://x/radio.m3u"));

        Check(PlaylistParser.ContentTypeIsAudio("audio/mpeg"));
        Check(PlaylistParser.ContentTypeIsAudio("audio/aacp; charset=x"));
        Check(PlaylistParser.ContentTypeIsAudio("application/ogg"));
        Check(!PlaylistParser.ContentTypeIsAudio("audio/x-mpegurl"));
        Check(!PlaylistParser.ContentTypeIsAudio("audio/x-scpls"));
        Check(!PlaylistParser.ContentTypeIsAudio("text/html"));
        Check(!PlaylistParser.ContentTypeIsAudio(null));

        Check(PlaylistParser.IsHls("application/vnd.apple.mpegurl", D("")));
        Check(PlaylistParser.IsHls("audio/x-mpegurl", D("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nlow.m3u8\n")));
        Check(!PlaylistParser.IsHls("audio/x-mpegurl", D("#EXTM3U\nhttp://a/b\n")));
    }

    static void TestPLS()
    {
        var u = Parse("[playlist]\r\nNumberOfEntries=3\r\nFile1=http://s1.example.com:8000/\r\nTitle1=Uno\r\n" +
                      "File2= http://s2.example.com/live \r\nfile3=relativo/stream\r\nFile4=http://s1.example.com:8000/\r\nVersion=2\r\n",
                      "audio/x-scpls", out string format);
        Eq(format, "PLS");
        EqList(u, new[] { "http://s1.example.com:8000/", "http://s2.example.com/live", "http://radio.example.com/liste/relativo/stream" });
        u = Parse("[Playlist]\nFile1=http://a/b\n", "text/plain", out format);
        Eq(format, "PLS");
        EqList(u, new[] { "http://a/b" });
        u = Parse("[playlist]\nNumberOfEntries=0\n", "audio/x-scpls", out _);
        Check(u != null && u.Count == 0);
    }

    static void TestM3U()
    {
        var u = Parse("#EXTM3U\n#EXTINF:-1,Radio\nhttp://a.example.com/stream\n\n#commento\nhttps://b.example.com/x.aac\n", "audio/x-mpegurl", out string format);
        Eq(format, "M3U");
        EqList(u, new[] { "http://a.example.com/stream", "https://b.example.com/x.aac" });
        EqList(Parse("http://a/1\nhttp://a/2\n", "text/plain", out _), new[] { "http://a/1", "http://a/2" });
        Check(Parse("<!DOCTYPE html><html><body>ciao</body></html>", "text/html", out _) == null);
        Check(Parse("ID3\x03 qualcosa", "application/octet-stream", out _) == null);
        Check(PlaylistParser.UrlsFromData(new byte[] { 0xFF, 0xFB, 0x90, 0x00, 0x00, 0x41 }, "text/plain", null, out _) == null);
        Check(Parse("http://a/1\n", "image/png", out _) == null);
    }

    static void TestASXAndXSPF()
    {
        var u = Parse("<ASX version=\"3.0\"><Entry><REF HREF=\"http://a.example.com/s?x=1&amp;y=2\"/></Entry>" +
                      "<entry><ref href='mms://b.example.com/s' /></entry></ASX>", "video/x-ms-asf", out string format);
        Eq(format, "ASX");
        EqList(u, new[] { "http://a.example.com/s?x=1&y=2", "mms://b.example.com/s" });
        u = Parse("<?xml version=\"1.0\"?><playlist version=\"1\" xmlns=\"http://xspf.org/ns/0/\"><trackList>" +
                  "<track><location>http://a.example.com/1</location></track>" +
                  "<track><location>\n  http://a.example.com/2\n</location></track></trackList></playlist>", "application/xspf+xml", out format);
        Eq(format, "XSPF");
        EqList(u, new[] { "http://a.example.com/1", "http://a.example.com/2" });
    }

    static void TestTrackInfo()
    {
        var t = TrackInfo.FromStreamTitle("Miles Davis - So What");
        Eq(t.Artist, "Miles Davis");
        Eq(t.Title, "So What");
        Eq(t.Text, "So What\nMiles Davis");
        t = TrackInfo.FromStreamTitle("Miles Davis - So What", split: false);
        Eq(t.Title, "Miles Davis - So What");
        Eq(t.Artist, "");
        t = TrackInfo.FromStreamTitle("  Notiziario  ");
        Eq(t.Title, "Notiziario");
        Eq(t.Text, "Notiziario");
        t = TrackInfo.FromStreamTitle("Artista - Brano - Remix");
        Eq(t.Artist, "Artista");
        Eq(t.Title, "Brano - Remix");
        Check(TrackInfo.FromStreamTitle(" - ").IsEmpty);
        Check(TrackInfo.FromStreamTitle("-").IsEmpty);
        Check(TrackInfo.FromStreamTitle(null).IsEmpty);
        t = TrackInfo.FromStreamTitle("Adele - title=\"Hello\" text=\"Hello\" song_spot=\"M\"");
        Eq(t.Artist, "Adele");
        Eq(t.Title, "Hello");
        Check(TrackInfo.Create("a", "b").SameAs(TrackInfo.Create(" a ", "b")));
        Check(!TrackInfo.Create("a", "b").SameAs(TrackInfo.Create("a", "c")));

        // Mediaset e RDS
        t = TrackInfo.FromStreamTitle("VASCO ROSSI~ALBACHIARA~ALBUM~1979~ISRC~240~0~0~RADIO 105");
        Eq(t.Artist, "Vasco Rossi");
        Eq(t.Title, "Albachiara");
        t = TrackInfo.FromStreamTitle("~GAZZELLE - OGNI VOLTA CHE SEI QUI~~0~~122~2026-11-23T09:58:40~2026-11-23T09:58:40~Radio 105");
        Eq(t.Artist, "Gazzelle");
        Eq(t.Title, "Ogni Volta Che Sei Qui");
        t = TrackInfo.FromStreamTitle("Azzurro * Adriano Celentano * 11712");
        Eq(t.Title, "Azzurro");
        Eq(t.Artist, "Adriano Celentano");
        Check(TrackInfo.FromStreamTitle("LINK * 1002264").IsEmpty);
        // maiuscole ammorbidite solo se tutto maiuscolo
        Eq(TrackInfo.Create("PINGUINI TATTICI NUCLEARI", null).Title, "Pinguini Tattici Nucleari");
        Eq(TrackInfo.Create("ABC", null).Title, "ABC");
        Eq(TrackInfo.Create("Bella CIAO", null).Title, "Bella CIAO");

        Eq(TrackInfo.FromStreamTitle("A - B").Swapped().Title, "A");
        // jingle
        Check(TrackInfo.FromStreamTitle("Radio 105").IsFillerForStation("Radio 105 Network"));
        Check(TrackInfo.FromStreamTitle("RADIO SUBASIO").IsFillerForStation("Subasio"));
        Check(TrackInfo.FromStreamTitle("Radiofreccia - Il rock").IsFillerForStation("RadioFreccia"));
        Check(!TrackInfo.FromStreamTitle("Miles Davis - So What").IsFillerForStation("Radio Jazz"));

        Eq(TrackInfo.Truncate("abcdef", 10), "abcdef");
        Eq(TrackInfo.Truncate("abcdefghij", 5), "abcd…");
        Eq(TrackInfo.Truncate("Città più lunga di così", 8).Length, 8);
    }

    /// Stream ICY finto: [audio metaint][len][meta]... ; un titolo per blocco ("" = blocco vuoto)
    static byte[] IcyStream(int metaint, string[] titles, Encoding enc)
    {
        var d = new List<byte>();
        foreach (var t in titles)
        {
            d.AddRange(Enumerable.Repeat((byte)0xAB, metaint));
            if (t.Length == 0) { d.Add(0); continue; }
            var meta = enc.GetBytes($"StreamTitle='{t}';StreamUrl='';").ToList();
            int blocks = (meta.Count + 15) / 16;
            while (meta.Count < blocks * 16) meta.Add(0);
            d.Add((byte)blocks);
            d.AddRange(meta);
        }
        return d.ToArray();
    }

    static void TestIcy()
    {
        var titles = new[] { "Miles Davis - So What", "", "Mina - L'importante è finire", "Mina - L'importante è finire" };
        var stream = IcyStream(100, titles, Encoding.UTF8);

        int audio = 0;
        bool clean = true;
        void Audio(byte[] b, int o, int n) { audio += n; for (int k = 0; k < n; k++) if (b[o + k] != 0xAB) clean = false; }

        var p = new IcyParser(100);
        EqList(p.Feed(stream, 0, stream.Length, Audio), new[] { "Miles Davis - So What", "Mina - L'importante è finire", "Mina - L'importante è finire" });
        Eq(audio, 400);
        Check(clean);

        // a pezzetti di 7 byte e un byte alla volta: i blocchi di rete tagliano ovunque
        foreach (int step in new[] { 7, 1 })
        {
            p = new IcyParser(100);
            audio = 0;
            var found = new List<string>();
            for (int i = 0; i < stream.Length; i += step) found.AddRange(p.Feed(stream, i, Math.Min(step, stream.Length - i), Audio));
            Eq(found.Count, 3);
            Eq(found[0], "Miles Davis - So What");
            Eq(audio, 400);
            Check(clean);
        }

        // Latin-1
        var latin = IcyStream(50, new[] { "Battiato - Centro di gravità" }, PlaylistParser.Latin1);
        EqList(new IcyParser(50).Feed(latin, 0, latin.Length, null), new[] { "Battiato - Centro di gravità" });

        // senza metadati: tutto audio
        audio = 0;
        Check(new IcyParser(0).Feed(new byte[10], 0, 10, Audio).Count == 0);
        Eq(audio, 10);

        Eq(IcyParser.StreamTitleFromMetadata(D("StreamTitle='';")), "");
        Eq(IcyParser.StreamTitleFromMetadata(D("StreamUrl='x';")), null);
        Eq(IcyParser.StreamTitleFromMetadata(D("StreamTitle='Senza fine")), "Senza fine");
        Eq(IcyParser.StreamTitleFromMetadata(D("streamtitle=\"A - B\";")), "A - B");
        Eq(IcyParser.StreamTitleFromMetadata(D("StreamTitle='L'amore';")), "L'amore");
    }

    static void TestStationName()
    {
        Eq(IcyParser.StationNameFromHeader(" Radio 105 "), "Radio 105");
        Eq(IcyParser.StationNameFromHeader("no name"), null);
        Eq(IcyParser.StationNameFromHeader("Unspecified"), null);
        Eq(IcyParser.StationNameFromHeader(""), null);
        Eq(IcyParser.StationNameFromHeader(null), null);
        Eq(IcyParser.StationNameFromHeader("server_tecnico"), null);
        string mangled = PlaylistParser.Latin1.GetString(Encoding.UTF8.GetBytes("Radio Città"));
        Eq(IcyParser.StationNameFromHeader(mangled), "Radio Città");
        Eq(IcyParser.StationNameFromHeader("Radio Città"), "Radio Città");
    }

    static byte[] Mp3Frames(int count)
    {
        // MPEG1 layer III, 128 kbps, 44100 Hz, senza padding: 417 byte
        var d = new List<byte>();
        for (int i = 0; i < count; i++)
        {
            var f = new byte[417];
            f[0] = 0xFF; f[1] = 0xFB; f[2] = 0x90; f[3] = 0x00;
            d.AddRange(f);
        }
        return d.ToArray();
    }

    static byte[] AdtsFrames(int count)
    {
        var d = new List<byte>();
        for (int i = 0; i < count; i++)
        {
            int len = 200;
            var f = new byte[len];
            f[0] = 0xFF; f[1] = 0xF1; f[2] = 0x50; f[3] = (byte)(0x80 | (len >> 11));
            f[4] = (byte)((len >> 3) & 0xFF); f[5] = (byte)(((len & 7) << 5) | 0x1F); f[6] = 0xFC;
            d.AddRange(f);
        }
        return d.ToArray();
    }

    static void TestAudioFormat()
    {
        Eq(AudioFormat.FromContentType("audio/mpeg"), AudioKind.Mp3);
        Eq(AudioFormat.FromContentType("audio/aacp; charset=x"), AudioKind.Aac);
        Eq(AudioFormat.FromContentType("application/ogg"), AudioKind.Ogg);
        Eq(AudioFormat.FromContentType("text/html; charset=utf-8"), AudioKind.Html);
        Eq(AudioFormat.FromContentType("application/octet-stream"), AudioKind.Unknown);
        Eq(AudioFormat.FromContentType(null), AudioKind.Unknown);

        var mp3 = Mp3Frames(4);
        Eq(AudioFormat.Sniff(mp3, mp3.Length), AudioKind.Mp3);
        // con un pezzo di frame davanti (lo stream si prende a metà)
        var shifted = new byte[] { 1, 2, 3, 0xFF, 0x00 }.Concat(mp3).ToArray();
        Eq(AudioFormat.Sniff(shifted, shifted.Length), AudioKind.Mp3);
        var aac = AdtsFrames(4);
        Eq(AudioFormat.Sniff(aac, aac.Length), AudioKind.Aac);
        Eq(AudioFormat.Sniff(D("ID3\x04\x00 tag"), 9), AudioKind.Mp3);
        Eq(AudioFormat.Sniff(D("OggS\x00\x02"), 6), AudioKind.Ogg);
        Eq(AudioFormat.Sniff(D("  <!DOCTYPE html><html>"), 23), AudioKind.Html);
        Eq(AudioFormat.Sniff(new byte[64], 64), AudioKind.Unknown);
    }

    static void TestNetMessages()
    {
        Check(NetMessages.ForHttpStatus(403, true, true).StartsWith(NetMessages.ProxyBlocked));
        Check(NetMessages.ForHttpStatus(403, true, false).StartsWith(NetMessages.ProxyBlocked));
        Check(NetMessages.ForHttpStatus(503, true, true).StartsWith(NetMessages.ProxyBlocked));
        Check(NetMessages.ForHttpStatus(407, false, false).Contains("proxy"));
        Eq(NetMessages.ForHttpStatus(404, true, true), "Stazione non trovata (HTTP 404)");
        Check(!NetMessages.ForHttpStatus(403, false, false).Contains("proxy"));
        Check(NetMessages.ForHttpStatus(502, true, false).Contains("proxy"));
        Eq(NetMessages.ForHttpStatus(500, false, false), null);
        Eq(NetMessages.ForHttpStatus(500, true, false), null);
        Check(NetMessages.ForHtmlInsteadOfAudio(true).StartsWith(NetMessages.ProxyBlocked));
    }


    static void TestHlsPlaylist()
    {
        var master = HlsPlaylist.Parse("#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=122225,CODECS=\"mp4a.40.5\"\nplay1.m3u8\n" +
                                       "#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS=\"mp4a.40.29\"\nhttps://cdn.example.com/low.m3u8\n" +
                                       "#EXT-X-STREAM-INF:BANDWIDTH=900000,CODECS=\"avc1.42e01e,mp4a.40.2\",RESOLUTION=640x360\nvideo.m3u8\n",
                                       new Uri("https://x.example.com/radio/master.m3u8"));
        Check(master.IsMaster);
        Eq(master.Variants.Count, 3);
        Eq(master.Variants[0].Url, "https://x.example.com/radio/play1.m3u8");
        Eq(master.Variants[0].Codecs, "mp4a.40.5");
        Check(master.Variants[2].HasVideo);
        Eq(master.ChooseVariant().Bandwidth, 122225);   // solo audio, la migliore fino a 320 kbit/s

        var media = HlsPlaylist.Parse("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:173979102\n" +
                                      "#EXT-X-DISCONTINUITY-SEQUENCE:0\n#MY-USER-HEADER-DATA:SERVER=\"primary\"\n#EXTINF:3.968,\nmedia_173979102.aac\n" +
                                      "#EXTINF:4.032,\nmedia_173979103.aac\n#EXTINF:3.968,\nmedia_173979104.aac\n",
                                      new Uri("https://stream.rds.radio/audio/rds.stream_aac/chunklist.m3u8"));
        Check(!media.IsMaster);
        Eq(media.TargetDuration, 5.0);
        Eq(media.Segments.Count, 3);
        Eq(media.Segments[0].Sequence, 173979102L);
        Eq(media.Segments[2].Sequence, 173979104L);
        Eq(media.Segments[1].Url, "https://stream.rds.radio/audio/rds.stream_aac/media_173979103.aac");
        Eq(media.Segments[1].Duration, 4.032);
        Check(!media.EndList && !media.HasInitSegment && !media.Encrypted);

        var other = HlsPlaylist.Parse("#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXT-X-KEY:METHOD=AES-128,URI=\"k\"\n#EXTINF:6,titolo, con virgola\nseg1.m4s\n#EXT-X-ENDLIST\n",
                                      new Uri("http://a/b/c.m3u8"));
        Check(other.HasInitSegment && other.Encrypted && other.EndList);
        Eq(other.Segments[0].Url, "http://a/b/seg1.m4s");
        Eq(other.Segments[0].Sequence, 0L);
        var a = HlsPlaylist.Attributes("#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS=\"a,b\",X=y");
        Eq(a["CODECS"], "a,b");
        Eq(a["X"], "y");
    }

    /// Tag ID3v2.4 con i frame dati
    static byte[] Id3Tag(params (string id, byte[] data)[] frames)
    {
        var body = new List<byte>();
        foreach (var (id, data) in frames)
        {
            body.AddRange(Encoding.ASCII.GetBytes(id));
            int n = data.Length;
            body.AddRange(new[] { (byte)((n >> 21) & 0x7F), (byte)((n >> 14) & 0x7F), (byte)((n >> 7) & 0x7F), (byte)(n & 0x7F), (byte)0, (byte)0 });
            body.AddRange(data);
        }
        int size = body.Count;
        var tag = new List<byte> { (byte)'I', (byte)'D', (byte)'3', 4, 0, 0,
                                   (byte)((size >> 21) & 0x7F), (byte)((size >> 14) & 0x7F), (byte)((size >> 7) & 0x7F), (byte)(size & 0x7F) };
        tag.AddRange(body);
        return tag.ToArray();
    }

    static byte[] TextFrame(string s) => new byte[] { 3 }.Concat(Encoding.UTF8.GetBytes(s)).ToArray();

    static void TestId3()
    {
        string rdsJson = "{\"type\":\"song\",\"id\":\"56145\",\"traccia\":\"Buonanotte Anche Stanotte\",\"artista\":\"Tananai\",\"cover\":\"https://web.rds.it/m/l56145?radio_id\\u003d1\"}";
        var priv = Id3Tag(("PRIV", Encoding.ASCII.GetBytes("com.apple.streaming.transportStreamTimestamp\0\0\0\0\0Â\u0091ÚÎ")));
        var info = Id3Tag(("EXTR", new byte[] { 0, 0, 3, (byte)'{', (byte)'}' }), ("SERV", Encoding.ASCII.GetBytes("\0\0\u0003primary")),
                          ("JSI3", new byte[] { 0, 0, 3 }.Concat(Encoding.UTF8.GetBytes(rdsJson)).ToArray()));
        var adts = AdtsFrames(3);
        var segment = priv.Concat(info).Concat(adts).ToArray();
        Eq(Id3.TagLength(segment, 0, segment.Length), priv.Length);
        Eq(Id3.LeadingTagsLength(segment, segment.Length), priv.Length + info.Length);
        Eq(Id3.StreamTitle(segment, priv.Length, segment.Length - priv.Length), "Tananai - Buonanotte Anche Stanotte");
        Eq(Id3.StreamTitle(segment, 0, segment.Length), null);   // solo il timestamp
        var song = TrackInfo.StationSongFromData(Encoding.UTF8.GetBytes("owner\0" + rdsJson));
        Check(song != null);
        Eq(song.Value.cover, "https://web.rds.it/m/l56145?radio_id=1");
        Check(TrackInfo.StationSongFromData(Encoding.UTF8.GetBytes("{\"type\":\"spot\",\"traccia\":\"x\"}")) == null);

        var tags = Id3Tag(("TIT2", TextFrame("So What")), ("TPE1", TextFrame("Miles Davis")));
        Eq(Id3.StreamTitle(tags, 0, tags.Length), "Miles Davis - So What");
        var utf16 = Id3Tag(("TIT2", new byte[] { 1 }.Concat(Encoding.Unicode.GetPreamble()).Concat(Encoding.Unicode.GetBytes("Città")).ToArray()));
        Eq(Id3.StreamTitle(utf16, 0, utf16.Length), "Città");
        Eq(Id3.TagLength(new byte[] { 0xFF, 0xF1, 0, 0, 0, 0, 0, 0, 0, 0 }, 0, 10), 0);
    }

    /// Pacchetti TS: PAT → PMT (audio AAC su 0x101, ID3 su 0x102) → PES audio e ID3
    static byte[] TsStream(byte[] audio, byte[] id3, int audioType = 0x0F)
    {
        var packets = new List<byte>();
        void Packet(int pid, bool start, byte[] payload, int offset, int count)
        {
            var p = new byte[188];
            p[0] = 0x47; p[1] = (byte)((start ? 0x40 : 0) | (pid >> 8)); p[2] = (byte)pid;
            int room = 184;
            if (count < room)
            {
                // adaptation field di riempimento
                int stuffing = room - count;
                p[3] = 0x30;
                p[4] = (byte)(stuffing - 1);
                if (stuffing > 1) { p[5] = 0; for (int k = 6; k < 4 + stuffing; k++) p[k] = 0xFF; }
                Buffer.BlockCopy(payload, offset, p, 4 + stuffing, count);
            }
            else
            {
                p[3] = 0x10;
                Buffer.BlockCopy(payload, offset, p, 4, 184);
            }
            packets.AddRange(p);
        }
        void Section(int pid, byte[] section) => Packet(pid, true, new byte[] { 0 }.Concat(section).ToArray(), 0, section.Length + 1);
        Section(0, new byte[] { 0x00, 0xB0, 0x0D, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xE1, 0x00, 0, 0, 0, 0 });
        Section(0x100, new byte[] { 0x02, 0xB0, 0x17, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x01, 0xF0, 0x00,
                                    (byte)audioType, 0xE1, 0x01, 0xF0, 0x00, 0x15, 0xE1, 0x02, 0xF0, 0x00, 0, 0, 0, 0 });
        void Pes(int pid, byte streamId, byte[] data)
        {
            var pes = new byte[] { 0, 0, 1, streamId, 0, 0, 0x80, 0x80, 5, 0x21, 0, 1, 0, 1 }.Concat(data).ToArray();
            for (int k = 0; k < pes.Length; k += 184) Packet(pid, k == 0, pes, k, Math.Min(184, pes.Length - k));
        }
        Pes(0x102, 0xBD, id3);
        Pes(0x101, 0xC0, audio);
        return packets.ToArray();
    }

    static void TestTs()
    {
        var audio = AdtsFrames(10);
        var id3 = Id3Tag(("TIT2", TextFrame("Azzurro")), ("TPE1", TextFrame("Adriano Celentano")));
        var ts = TsStream(audio, id3);
        foreach (int step in new[] { ts.Length, 100, 7 })
        {
            var demux = new TsDemuxer();
            var got = new List<byte>();
            var titles = new List<string>();
            demux.AudioData += (b, o, n) => { for (int k = 0; k < n; k++) got.Add(b[o + k]); };
            demux.Title += t => titles.Add(t);
            for (int i = 0; i < ts.Length; i += step) demux.Feed(ts, i, Math.Min(step, ts.Length - i));
            demux.Flush();
            Eq(demux.Audio, AudioKind.Aac);
            Check(got.SequenceEqual(audio), $"audio estratto a blocchi di {step}");
            EqList(titles, new[] { "Adriano Celentano - Azzurro" });
        }
        var mp3 = new TsDemuxer();
        mp3.Feed(TsStream(Mp3Frames(2), new byte[0], 0x03), 0, TsStream(Mp3Frames(2), new byte[0], 0x03).Length);
        Eq(mp3.Audio, AudioKind.Mp3);
    }

    static void TestOnAir()
    {
        Check(OnAir.ServiceUrl("https://4c4b867c89244861ac216426883d1ad0.msvdn.net/radiodeejay/radiodeejay/play1.m3u8").Contains("deejay.it"));
        Check(OnAir.ServiceUrl("https://4c4b867c89244861ac216426883d1ad0.msvdn.net/radiocapital/radiocapital/master_ma.m3u8").Contains("capital.it"));
        Check(OnAir.ServiceUrl("https://x.msvdn.net/radiom2o/radiom2o/master_ma.m3u8").Contains("m2o.it"));
        Eq(OnAir.ServiceUrl("http://icecast.unitedradio.it/Radio105.mp3"), null);

        var s = OnAir.SongFromGediJson("{\"title\":\"Stop the Wedding! ASHE\",\"author\":\"Deejay Chiama Italia\",\"image\":\"https:\\/\\/www.deejay.it\\/c\\/ASHE_-_Stop_The_Wedding!__AI_1b.jpg\"}");
        Eq(s.Value.title, "Stop the Wedding!");
        Eq(s.Value.artist, "ASHE");
        s = OnAir.SongFromGediJson("{\"title\":\"Sere Nere TIZIANO FERRO\"}");
        Eq(s.Value.artist, "TIZIANO FERRO");
        s = OnAir.SongFromGediJson("{\"title\":\"VIVA LA VIDA\",\"image\":\"https://x/COLDPLAY_-_Viva_La_Vida__AI_x.jpg\"}");
        Eq(s.Value.title, "VIVA LA VIDA");
        Eq(s.Value.artist, "COLDPLAY");
        s = OnAir.SongFromGediJson("{\"title\":\"Deejay Chiama Italia\"}");
        Eq(s.Value.title, "Deejay Chiama Italia");
        Eq(s.Value.artist, "");
        Check(OnAir.SongFromGediJson("{\"title\":\"\"}") == null);
        Check(OnAir.SongFromGediJson("<html>") == null);
    }


    static void TestFavorites()
    {
        var day = new DateTime(2026, 11, 23, 9, 30, 0, DateTimeKind.Utc);
        var f = FavoriteTracks.Parse("[{\"title\":\"So What\",\"artist\":\"Miles Davis\",\"station\":\"Jazz24\",\"added\":\"2026-01-02T10:00:00Z\"}," +
                                     "{\"title\":\"\",\"artist\":\"Solo Artista\",\"station\":\"X\",\"added\":\"2026-01-03T10:00:00Z\"}," +
                                     "{\"title\":\"\",\"artist\":\"\"},{\"title\":\"Città\",\"artist\":\"Battiato\",\"station\":\"Rai Radio 1\",\"added\":\"bad\"}]", out string error);
        Check(f != null && error == null);
        Eq(f.Tracks.Count, 3);
        Eq(f.Tracks[1].Title, "Solo Artista");
        Eq(f.Tracks[1].Artist, "");
        Eq(f.Tracks[0].Added, new DateTime(2026, 1, 2, 10, 0, 0, DateTimeKind.Utc));
        Eq(f.Tracks[2].Added.Year, 1970);
        Eq(f.Tracks[0].DisplayText, "So What – Miles Davis");
        Eq(f.Tracks[0].SearchText, "Miles Davis So What");

        f.Add("so what", "MILES DAVIS", "Altra", day, out bool present);
        Check(present);
        Eq(f.Tracks.Count, 3);
        f.Add("Azzurro", "Adriano Celentano", "Radio 105", day, out present);
        Check(!present);
        Eq(f.Tracks.Count, 4);

        EqList(f.Matching("davis", null).Select(t => t.Title), new[] { "So What" });
        EqList(f.Matching("citta battiato", null).Select(t => t.Title), new[] { "Città" });   // accenti e ordine ignorati
        EqList(f.Matching("", "Radio 105").Select(t => t.Title), new[] { "Azzurro" });
        EqList(f.Stations(), new[] { "Jazz24", "Radio 105", "Rai Radio 1", "X" });

        // andata e ritorno nel formato del Mac
        string json = f.ToJson();
        Check(json.Contains("\"added\": \"2026-11-23T09:30:00Z\""));
        Check(!json.Contains("\\/"));
        var back = FavoriteTracks.Parse(json, out _);
        Eq(back.Tracks.Count, 4);
        Eq(back.Tracks[3].Station, "Radio 105");

        string csv = FavoriteTracks.Csv(new[] { new FavoriteTrack { Title = "A \"b\"", Artist = "C;D", Station = "S", Added = day } });
        Check(csv.StartsWith("﻿Titolo;Artista;Stazione;Aggiunto il\r\n"));
        Check(csv.Contains("\"A \"\"b\"\"\";\"C;D\";\"S\";"));

        Eq(FavoriteTracks.SearchUrl(new FavoriteTrack { Title = "Sere Nere", Artist = "Tiziano Ferro & Co/x" }, TrackSearchSite.YouTube),
           "https://www.youtube.com/results?search_query=Tiziano%20Ferro%20%26%20Co%2Fx%20Sere%20Nere");
        Check(FavoriteTracks.SearchUrl(new FavoriteTrack { Title = "Città" }, TrackSearchSite.Spotify).EndsWith("Citt%C3%A0"));

        // cronologia
        var h = new FavoriteTracks();
        Check(h.Record("A", "x", "S", day, 3));
        Check(!h.Record("A", "x", "S", day, 3));   // già l'ultimo
        Check(h.Record("B", "", "S", day, 3));
        Check(h.Record("C", "", "S", day, 3));
        Check(h.Record("A", "X", "T", day, 3));    // spostato in fondo
        EqList(h.Tracks.Select(t => t.Title), new[] { "B", "C", "A" });
        Check(h.Record("D", "", "S", day, 3));
        EqList(h.Tracks.Select(t => t.Title), new[] { "C", "A", "D" });
        Check(!h.Record("", "", "S", day, 3));

        Check(FavoriteTracks.Parse("{}", out error) == null && error != null);
        Eq(FavoriteTracks.Parse("", out _).Tracks.Count, 0);

        var other = FavoriteTracks.Parse("[{\"title\":\"So What\",\"artist\":\"Miles Davis\",\"added\":\"2025-01-01T00:00:00Z\"},{\"title\":\"Nuovo\",\"added\":\"2025-06-01T00:00:00Z\"}]", out _);
        Eq(back.Merge(other), 1);
        EqList(back.Tracks.Select(t => t.Title), new[] { "Città", "Nuovo", "So What", "Solo Artista", "Azzurro" });   // in ordine di data (Città senza data)
    }

    static void TestRadioBrowser()
    {
        string json = "[{\"name\":\"Radio 105\",\"url\":\"http://x/105.pls\",\"url_resolved\":\"http://icecast.unitedradio.it/Radio105.mp3\",\"countrycode\":\"it\",\"codec\":\"MP3\",\"bitrate\":128,\"tags\":\"pop,hits\",\"votes\":10,\"hls\":0}," +
                      "{\"name\":\"Radio 105\",\"url\":\"http://icecast.unitedradio.it/Radio105.mp3\",\"codec\":\"MP3\"}," +
                      "{\"name\":\"Ogg Radio\",\"url_resolved\":\"https://o/x.ogg\",\"codec\":\"OGG\",\"bitrate\":0}," +
                      "{\"name\":\"Deejay\",\"url_resolved\":\"https://a/b.m3u8\",\"codec\":\"UNKNOWN\",\"hls\":1}," +
                      "{\"name\":\"MMS\",\"url_resolved\":\"mms://x\"},{\"name\":\"\",\"url_resolved\":\"http://y\"}]";
        var list = RadioBrowser.StationsFromJson(json);
        Eq(list.Count, 3);
        Eq(list[0].Url, "http://icecast.unitedradio.it/Radio105.mp3");
        Eq(list[0].Country, "IT");
        Eq(list[0].Tags, "pop, hits");
        Eq(list[0].FormatDescription, "MP3 128 kbps");
        Eq(list[1].Name, "Deejay");
        Eq(list[1].FormatDescription, "HLS");
        Eq(list[2].Name, "Ogg Radio");   // non riproducibile: in fondo
        Check(!list[2].Playable);
        Check(RadioBrowser.StationsFromJson("<html>") == null);

        Eq(RadioBrowser.SearchUrl("de1.api.radio-browser.info", RadioBrowser.Mode.Name, "rock & roll", "IT"),
           "https://de1.api.radio-browser.info/json/stations/search?name=rock%20%26%20roll&hidebroken=true&order=clickcount&reverse=true&limit=100&countrycode=IT");
        Check(RadioBrowser.SearchUrl("x", RadioBrowser.Mode.Tag, "Jazz", null).Contains("tag=jazz&"));
        Check(!RadioBrowser.SearchUrl("x", RadioBrowser.Mode.Top, "", "").Contains("countrycode"));

        EqList(RadioBrowser.AlternativeNames("Radio Monte Carlo Hits"), new[] { "RMC Hits", "Monte Carlo Hits", "RMCH", "RMC Hits" }.Distinct().ToArray());
        Check(RadioBrowser.AlternativeNames("Radio Dimensione Suono").Contains("RDS"));
        Check(RadioBrowser.AlternativeNames("Radio Subasio").Contains("Subasio"));
        Check(RadioBrowser.AlternativeNames("Radio Freccia").Contains("Radiofreccia"));
        Check(RadioBrowser.AlternativeNames("Radiofreccia").Contains("Radio freccia"));
        Check(!RadioBrowser.AlternativeNames("Jazz").Any());
    }

    static void TestBackup()
    {
        string mac = "{\"app\":\"1.16.0\",\"format\":\"radiotray-mac-backup\",\"version\":1,\"created\":\"2026-11-20T08:00:00Z\"," +
                     "\"bookmarks\":[{\"group\":\"Jazz\",\"stations\":[{\"name\":\"Swiss Jazz\",\"url\":\"http://stream.srg-ssr.ch/m/rsj/mp3_128\",\"mirrors\":[\"http://m2/x\"]}]}]," +
                     "\"favorites\":[{\"title\":\"So What\",\"artist\":\"Miles Davis\",\"station\":\"Swiss Jazz\",\"added\":\"2026-11-01T10:00:00Z\"}]," +
                     "\"history\":[],\"settings\":{\"volume-level\":65,\"notifications\":false,\"swapped-title-artist-stations\":[\"Radio italiane\\nRadio 105\"]}}";
        var b = Backup.Parse(mac, out string error);
        Check(b != null, error);
        Eq(b.StationCount, 1);
        Eq(b.Favorites.Tracks.Count, 1);
        Eq(b.History.Tracks.Count, 0);
        Eq(b.SettingInt(Backup.KeyVolume), 65);
        Eq(b.SettingBool(Backup.KeyNotifications), false);
        EqList(b.SettingStrings(Backup.KeySwapped), new[] { "Radio italiane\nRadio 105" });
        Eq(b.AppVersion, "1.16.0");
        Eq(b.Created, new DateTime(2026, 11, 20, 8, 0, 0, DateTimeKind.Utc));

        var again = Backup.Parse(b.ToJson(), out error);
        Check(again != null, error);
        Eq(again.StationCount, 1);
        Eq(again.Favorites.Tracks[0].Artist, "Miles Davis");

        Check(Backup.Parse("{\"format\":\"altro\"}", out error) == null && error.Contains("non è un backup"));
        Check(Backup.Parse("{\"format\":\"radiotray-mac-backup\",\"version\":2}", out error) == null && error.Contains("più recente"));
        Check(Backup.Parse("{\"format\":\"radiotray-mac-backup\",\"favorites\":{}}", out error) == null && error.Contains("favorites"));
        Check(Backup.Parse("[1]", out _) == null);
    }

    static void TestBookmarksDocument()
    {
        string json = "[{\"group\":\"Jazz\",\"image\":\"x.png\",\"extra\":7,\"stations\":[{\"name\":\"A\",\"url\":\"http://a/\",\"mirrors\":[\"http://a2/\"]}]},{\"group\":\"root\",\"stations\":[]}]";
        var doc = BookmarksDocument.Parse(json, out string error);
        Check(doc != null, error);
        var jazz = doc.GroupNamed("Jazz");
        Eq(doc.AddStation(jazz, "Radio 105", "http://icecast.unitedradio.it/Radio105.mp3", out var r105), null);
        Check(doc.AddStation(jazz, "A", "http://b/", out _).Contains("già"));
        Check(doc.AddStation(jazz, "B", "ftp://b/", out _).Contains("http"));
        Check(doc.AddStation(jazz, " ", "http://b/", out _) != null);
        Eq(doc.AddGroup("Notizie", out var news), null);
        Eq(doc.Groups.Last().Name, "root");          // il gruppo root resta in fondo
        Eq(doc.Groups[1].Name, "Notizie");
        Check(doc.AddGroup("jazz", out _) == null);  // nomi diversi per maiuscole: ammessi come in Radiotray-NG
        Check(doc.AddGroup("Jazz", out _).Contains("già"));
        Check(doc.RenameGroup(doc.GroupNamed("root"), "X") != null);
        Eq(doc.RenameStation(r105, "105"), null);
        Eq(doc.MoveStation(r105, -1), null);
        EqList(jazz.Stations.Select(s => s.Name), new[] { "105", "A" });
        doc.SetNotifications(r105, false);
        Eq(doc.MoveStationToGroup(r105, news, out var moved), null);
        Eq(moved.Group.Name, "Notizie");
        Eq(doc.MoveGroup(news, -1), null);
        Eq(doc.Groups[0].Name, "Notizie");

        var b = Bookmarks.Parse(doc.ToJson(), out error);
        Check(b != null, error);
        Check(!b.StationNamed("105", "Notizie").Notifications);
        EqList(b.StationNamed("A", "Jazz").Mirrors, new[] { "http://a2/" });   // i campi sconosciuti restano
        Check(doc.ToJson().Contains("\"extra\": 7"));
        Check(doc.ToJson().Contains("\"image\": \"x.png\""));

        var extra = Bookmarks.Parse("[{\"group\":\"Jazz\",\"stations\":[{\"name\":\"A doppia\",\"url\":\"https://a\"},{\"name\":\"Nuova\",\"url\":\"http://n/\",\"mirrors\":[\"http://n2/\"]}]}," +
                                    "{\"group\":\"Rock\",\"stations\":[{\"name\":\"R\",\"url\":\"http://r/\"}]}]", out _);
        Eq(doc.Merge(extra), 2);   // "https://a" è già "http://a/"
        b = Bookmarks.Parse(doc.ToJson(), out _);
        EqList(b.StationNamed("Nuova", "Jazz").Mirrors, new[] { "http://n2/" });
        Check(b.GroupNamed("Rock") != null);
        Check(BookmarksDocument.Parse("[{", out error) == null && error != null);
        doc.RemoveGroup(doc.GroupNamed("Rock"));
        Check(doc.GroupNamed("Rock") == null);
    }


    static void TestArtwork()
    {
        Eq(Artwork.CoreTitle("Hello (Remastered 2011)"), "Hello");
        Eq(Artwork.CoreTitle("Song [Live] - Edit"), "Song");
        Eq(Artwork.CoreTitle("Blinding Lights feat. X"), "Blinding Lights");
        Eq(Artwork.CoreTitle("(Intro)"), "(Intro)");
        Eq(Artwork.Normalized("Città-Più 2!"), "cittapiu2");
        Eq(Artwork.CacheKey("Hello (Live)", "Adèle"), "adele|hello");
        Eq(Artwork.SearchUrl("Sere Nere (Live)", "Tiziano Ferro"),
           "https://itunes.apple.com/search?term=Tiziano%20Ferro%20Sere%20Nere&media=music&entity=song&limit=10");

        string json = "{\"results\":[" +
                      "{\"artistName\":\"Altro\",\"trackName\":\"Hello\",\"artworkUrl100\":\"https://x/wrong/100x100bb.jpg\"}," +
                      "{\"artistName\":\"Adele\",\"trackName\":\"Someone Like You\",\"artworkUrl100\":\"https://x/other/100x100bb.jpg\"}," +
                      "{\"artistName\":\"Adele\",\"trackName\":\"Hello (Live)\",\"artworkUrl100\":\"https://x/right/100x100bb.jpg\"}]}";
        Eq(Artwork.ArtworkUrlFromJson(json, "Hello", "Adele"), "https://x/right/600x600bb.jpg");
        Eq(Artwork.ArtworkUrlFromJson(json, "Rolling", "Adele"), "https://x/other/600x600bb.jpg");   // artista giusto, titolo diverso
        Eq(Artwork.ArtworkUrlFromJson(json, "Hello", "Lionel Richie"), null);                         // artista sbagliato: niente
        Eq(Artwork.ArtworkUrlFromJson("{\"results\":[{\"artistName\":\"Mina\",\"trackName\":\"Acqua e sale\",\"artworkUrl100\":\"https://x/m/100x100.jpg\"}]}",
                                      "Acqua e sale", "Mina & Celentano"), "https://x/m/600x600.jpg");
        Eq(Artwork.ArtworkUrlFromJson("<html>", "a", "b"), null);

        EqList(Artwork.FaviconsFromJson("[{\"favicon\":\"https://a/logo.png\"},{\"favicon\":\"https://a/logo.svg\"},{\"favicon\":\"https://www.facebook.com/x\"}," +
                                        "{\"favicon\":\"\"},{\"favicon\":\"https://a/logo.png\"},{\"favicon\":\" http://b/l.jpg \"}]"),
               new[] { "https://a/logo.png", "http://b/l.jpg" });
        Check(Artwork.LogoByUrlQuery("de1", "http://x/a b").EndsWith("byurl?url=http%3A%2F%2Fx%2Fa%20b"));

        // copertine ufficiali
        var tag = Id3Tag(("JSI3", new byte[] { 0, 0, 3 }.Concat(Encoding.UTF8.GetBytes("{\"type\":\"song\",\"traccia\":\"T\",\"artista\":\"A\",\"cover\":\"https://web.rds.it/c.jpg\"}")).ToArray()));
        Eq(Id3.StreamTitleAndCover(tag, 0, tag.Length, out string cover), "A - T");
        Eq(cover, "https://web.rds.it/c.jpg");
        var g = OnAir.SongFromGediJson("{\"title\":\"Sere Nere TIZIANO FERRO\",\"image\":\"https://www.deejay.it/c.jpg\"}", out string gc);
        Eq(g.Value.artist, "TIZIANO FERRO");
        Eq(gc, "https://www.deejay.it/c.jpg");
    }

    static void TestAlarm()
    {
        var monday = new DateTime(2026, 11, 23, 7, 30, 0);   // lunedì
        Eq(Alarm.DayBit(monday), 1);
        Eq(Alarm.DayBit(monday.AddDays(6)), 64);              // domenica
        Check(Alarm.ShouldFire(monday, 450, Alarm.Weekdays, null));
        Check(Alarm.ShouldFire(monday.AddMinutes(10), 450, Alarm.Weekdays, null));
        Check(!Alarm.ShouldFire(monday.AddMinutes(11), 450, Alarm.Weekdays, null));
        Check(!Alarm.ShouldFire(monday.AddMinutes(-1), 450, Alarm.Weekdays, null));
        Check(!Alarm.ShouldFire(monday, 450, Alarm.Weekdays, monday.AddMinutes(-1)));   // già suonata oggi
        Check(Alarm.ShouldFire(monday, 450, Alarm.Weekdays, monday.AddDays(-3)));
        Check(!Alarm.ShouldFire(monday.AddDays(5), 450, Alarm.Weekdays, null));          // sabato
        Eq(Alarm.NextFire(monday, 450, Alarm.Weekdays), monday.AddDays(1));               // già passata: domani
        Eq(Alarm.NextFire(monday.AddMinutes(-5), 450, Alarm.Weekdays), monday);
        Eq(Alarm.NextFire(monday.AddDays(4).AddHours(1), 450, Alarm.Weekdays), monday.AddDays(7));   // venerdì dopo l'ora → lunedì
        Eq(Alarm.NextFire(monday, 450, 0), null);
        Eq(Alarm.DescribeDays(Alarm.Weekdays), "Lu–Ve");
        Eq(Alarm.DescribeDays(Alarm.EveryDay), "Tutti i giorni");
        Eq(Alarm.DescribeDays(0x60), "Sa, Do");
        Eq(Alarm.DescribeDays(1 | 4 | 16), "Lu, Me, Ve");
        Eq(Alarm.DescribeMinutes(450), "07:30");
    }

    static int Main(string[] args)
    {
        TestJson();
        TestBookmarks();
        TestDirect();
        TestPLS();
        TestM3U();
        TestASXAndXSPF();
        TestTrackInfo();
        TestIcy();
        TestStationName();
        TestAudioFormat();
        TestNetMessages();
        TestHlsPlaylist();
        TestId3();
        TestTs();
        TestOnAir();
        TestFavorites();
        TestRadioBrowser();
        TestBackup();
        TestBookmarksDocument();
        TestArtwork();
        TestAlarm();
        foreach (var path in args) TestBundled(path);
        Console.WriteLine($"{checks} controlli, {failures} falliti");
        return failures == 0 ? 0 : 1;
    }
}
