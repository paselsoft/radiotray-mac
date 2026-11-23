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
        foreach (var path in args) TestBundled(path);
        Console.WriteLine($"{checks} controlli, {failures} falliti");
        return failures == 0 ? 0 : 1;
    }
}
