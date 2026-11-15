// Test della logica senza interfaccia: preferiti, playlist, titoli.
// Compilato ed eseguito da `make test` (anche sul runner macOS della CI).
#import <Foundation/Foundation.h>
#import "../src/RTBookmarks.h"
#import "../src/RTPlaylistParser.h"
#import "../src/RTTrackInfo.h"
#import "../src/RTIcyParser.h"

static int failures = 0;
static int checks = 0;

#define CHECK(cond) do { checks++; if (!(cond)) { failures++; fprintf(stderr, "FALLITO %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define CHECK_EQ(a, b) do { checks++; id _a = (a), _b = (b); if (!((_a == nil && _b == nil) || [_a isEqual:_b])) { failures++; \
    fprintf(stderr, "FALLITO %s:%d: %s\n  ottenuto: %s\n  atteso:   %s\n", __FILE__, __LINE__, #a, [[_a description] UTF8String], [[_b description] UTF8String]); } } while (0)

static NSData *D(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }

static NSArray *Parse(NSString *text, NSString *ct, NSString **format)
{
    return [RTPlaylistParser urlsFromData:D(text) contentType:ct
                                  baseURL:[NSURL URLWithString:@"http://radio.example.com/liste/stazione.pls"]
                               formatName:format];
}

static void testBookmarks(void)
{
    NSString *json = @"[ {\"group\":\"Jazz\",\"image\":\"/tmp/j.png\",\"stations\":["
                      "{\"name\":\"A\",\"url\":\"http://a/x.pls\"},"
                      "{\"name\":\"B\",\"url\":\"http://b/y\",\"notifications\":false,\"direct\":true},"
                      "{\"name\":\"A\",\"url\":\"http://doppia\"}]},"
                      "{\"group\":\"root\",\"stations\":[{\"name\":\"R\",\"url\":\" http://r \"}]},"
                      "{\"group\":\"Vuoto\"} ]";
    NSString *error = nil;
    RTBookmarks *b = [RTBookmarks bookmarksWithData:D(json) error:&error];
    CHECK(b != nil);
    CHECK(error == nil);
    CHECK(b.groups.count == 3);
    CHECK([b stationCount] == 3);   // il doppione "A" viene scartato
    CHECK_EQ([b groupNamed:@"Jazz"].image, @"/tmp/j.png");
    CHECK([b groupNamed:@"root"].isRoot);
    CHECK(![b groupNamed:@"Jazz"].isRoot);
    CHECK_EQ([b stationNamed:@"A" inGroup:@"Jazz"].url, @"http://a/x.pls");
    CHECK([b stationNamed:@"A" inGroup:@"Jazz"].notifications);
    CHECK(![b stationNamed:@"A" inGroup:@"Jazz"].direct);
    CHECK(![b stationNamed:@"B" inGroup:@"Jazz"].notifications);
    CHECK([b stationNamed:@"B" inGroup:@"Jazz"].direct);
    CHECK_EQ([b stationNamed:@"R" inGroup:@"root"].url, @"http://r");
    CHECK([b stationNamed:@"R" inGroup:@"Jazz"] == nil);
    CHECK([b groupNamed:@"Vuoto"].stations.count == 0);

    error = nil;
    CHECK([RTBookmarks bookmarksWithData:D(@"[ {\"group\":\"x\", ") error:&error] == nil);
    CHECK([error containsString:@"JSON"]);
    error = nil;
    CHECK([RTBookmarks bookmarksWithData:D(@"{\"group\":\"x\"}") error:&error] == nil);
    CHECK(error.length > 0);
    error = nil;
    CHECK([RTBookmarks bookmarksWithData:D(@"[{\"stations\":[]}]") error:&error] == nil);
    CHECK([error containsString:@"group"]);
    error = nil;
    CHECK([RTBookmarks bookmarksWithData:D(@"[{\"group\":\"a\",\"stations\":[{\"name\":\"x\"}]}]") error:&error] == nil);
    CHECK([error containsString:@"url"]);
    error = nil;
    CHECK([RTBookmarks bookmarksWithData:D(@"[{\"group\":\"a\"},{\"group\":\"a\"}]") error:&error] == nil);
    CHECK([error containsString:@"due volte"]);
    CHECK([RTBookmarks bookmarksWithData:D(@"[]") error:NULL].groups.count == 0);
}

static void testBundledBookmarks(NSString *path)
{
    NSString *error = nil;
    RTBookmarks *b = [RTBookmarks bookmarksWithContentsOfFile:path error:&error];
    CHECK(b != nil);
    if (!b) fprintf(stderr, "  %s\n", error.UTF8String);
    CHECK([b stationCount] > 0);
}

static void testDirect(void)
{
    CHECK([RTPlaylistParser urlLooksDirect:@"http://x/stream.mp3"]);
    CHECK([RTPlaylistParser urlLooksDirect:@"https://x/a/b.AAC?token=1"]);
    CHECK([RTPlaylistParser urlLooksDirect:@"https://x/live/master.m3u8"]);
    CHECK(![RTPlaylistParser urlLooksDirect:@"http://x/listen.pls"]);
    CHECK(![RTPlaylistParser urlLooksDirect:@"http://x/stream"]);
    CHECK(![RTPlaylistParser urlLooksDirect:@"http://x/radio.m3u"]);

    CHECK([RTPlaylistParser contentTypeIsAudio:@"audio/mpeg"]);
    CHECK([RTPlaylistParser contentTypeIsAudio:@"audio/aacp; charset=x"]);
    CHECK([RTPlaylistParser contentTypeIsAudio:@"application/ogg"]);
    CHECK(![RTPlaylistParser contentTypeIsAudio:@"audio/x-mpegurl"]);
    CHECK(![RTPlaylistParser contentTypeIsAudio:@"audio/x-scpls"]);
    CHECK(![RTPlaylistParser contentTypeIsAudio:@"text/html"]);
    CHECK(![RTPlaylistParser contentTypeIsAudio:nil]);

    CHECK([RTPlaylistParser isHLSContentType:@"application/vnd.apple.mpegurl" data:D(@"")]);
    CHECK([RTPlaylistParser isHLSContentType:@"audio/x-mpegurl" data:D(@"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nlow.m3u8\n")]);
    CHECK(![RTPlaylistParser isHLSContentType:@"audio/x-mpegurl" data:D(@"#EXTM3U\nhttp://a/b\n")]);
}

static void testPLS(void)
{
    NSString *format = nil;
    NSArray *u = Parse(@"[playlist]\r\nNumberOfEntries=3\r\nFile1=http://s1.example.com:8000/\r\nTitle1=Uno\r\n"
                       "File2= http://s2.example.com/live \r\nfile3=relativo/stream\r\nFile4=http://s1.example.com:8000/\r\nVersion=2\r\n",
                       @"audio/x-scpls", &format);
    CHECK_EQ(format, @"PLS");
    CHECK_EQ(u, (@[@"http://s1.example.com:8000/", @"http://s2.example.com/live",
                   @"http://radio.example.com/liste/relativo/stream"]));
    // riconosciuta dal contenuto anche con tipo generico
    u = Parse(@"[Playlist]\nFile1=http://a/b\n", @"text/plain", &format);
    CHECK_EQ(format, @"PLS");
    CHECK_EQ(u, @[@"http://a/b"]);
    u = Parse(@"[playlist]\nNumberOfEntries=0\n", @"audio/x-scpls", NULL);
    CHECK(u != nil && u.count == 0);
}

static void testM3U(void)
{
    NSString *format = nil;
    NSArray *u = Parse(@"#EXTM3U\n#EXTINF:-1,Radio\nhttp://a.example.com/stream\n\n#commento\nhttps://b.example.com/x.aac\n",
                       @"audio/x-mpegurl", &format);
    CHECK_EQ(format, @"M3U");
    CHECK_EQ(u, (@[@"http://a.example.com/stream", @"https://b.example.com/x.aac"]));
    // elenco di URL con text/plain
    u = Parse(@"http://a/1\nhttp://a/2\n", @"text/plain", &format);
    CHECK_EQ(u, (@[@"http://a/1", @"http://a/2"]));
    // pagina HTML: non è una playlist
    CHECK(Parse(@"<!DOCTYPE html><html><body>ciao</body></html>", @"text/html", NULL) == nil);
    // tipo audio sconosciuto senza testo valido
    CHECK(Parse(@"ID3\x03 qualcosa", @"application/octet-stream", NULL) == nil);
    // dati binari
    unsigned char bin[] = {0xFF, 0xFB, 0x90, 0x00, 0x00, 0x41};
    CHECK([RTPlaylistParser urlsFromData:[NSData dataWithBytes:bin length:sizeof bin] contentType:@"text/plain"
                                 baseURL:nil formatName:NULL] == nil);
    // tipo non testuale e non dichiarato
    CHECK(Parse(@"http://a/1\n", @"image/png", NULL) == nil);
}

static void testASX(void)
{
    NSString *format = nil;
    NSArray *u = Parse(@"<ASX version=\"3.0\"><Entry><REF HREF=\"http://a.example.com/s?x=1&amp;y=2\"/></Entry>"
                       "<entry><ref href='mms://b.example.com/s' /></entry></ASX>", @"video/x-ms-asf", &format);
    CHECK_EQ(format, @"ASX");
    CHECK_EQ(u, (@[@"http://a.example.com/s?x=1&y=2", @"mms://b.example.com/s"]));
}

static void testXSPF(void)
{
    NSString *format = nil;
    NSArray *u = Parse(@"<?xml version=\"1.0\"?><playlist version=\"1\" xmlns=\"http://xspf.org/ns/0/\"><trackList>"
                       "<track><location>http://a.example.com/1</location></track>"
                       "<track><location>\n  http://a.example.com/2\n</location></track></trackList></playlist>",
                       @"application/xspf+xml", &format);
    CHECK_EQ(format, @"XSPF");
    CHECK_EQ(u, (@[@"http://a.example.com/1", @"http://a.example.com/2"]));
}

static void testTrackInfo(void)
{
    RTTrackInfo *t = [RTTrackInfo infoWithStreamTitle:@"Miles Davis - So What" split:YES];
    CHECK_EQ(t.artist, @"Miles Davis");
    CHECK_EQ(t.title, @"So What");
    CHECK_EQ(t.clipboardText, @"So What\nMiles Davis");

    t = [RTTrackInfo infoWithStreamTitle:@"Miles Davis - So What" split:NO];
    CHECK_EQ(t.title, @"Miles Davis - So What");
    CHECK_EQ(t.artist, @"");

    t = [RTTrackInfo infoWithStreamTitle:@"  Notiziario  " split:YES];
    CHECK_EQ(t.title, @"Notiziario");
    CHECK_EQ(t.artist, @"");
    CHECK_EQ(t.clipboardText, @"Notiziario");

    t = [RTTrackInfo infoWithStreamTitle:@"Artista - Brano - Remix" split:YES];
    CHECK_EQ(t.artist, @"Artista");
    CHECK_EQ(t.title, @"Brano - Remix");

    t = [RTTrackInfo infoWithStreamTitle:@" - " split:YES];
    CHECK(t.isEmpty);
    t = [RTTrackInfo infoWithStreamTitle:@"-" split:YES];
    CHECK(t.isEmpty);
    t = [RTTrackInfo infoWithStreamTitle:nil split:YES];
    CHECK(t.isEmpty);

    t = [RTTrackInfo infoWithStreamTitle:@"Adele - title=\"Hello\" text=\"Hello\" song_spot=\"M\"" split:YES];
    CHECK_EQ(t.artist, @"Adele");
    CHECK_EQ(t.title, @"Hello");

    CHECK([[RTTrackInfo infoWithTitle:@"a" artist:@"b"] isEqualToInfo:[RTTrackInfo infoWithTitle:@" a " artist:@"b"]]);
    CHECK(![[RTTrackInfo infoWithTitle:@"a" artist:@"b"] isEqualToInfo:[RTTrackInfo infoWithTitle:@"a" artist:@"c"]]);

    CHECK_EQ(RTTruncate(@"abcdef", 10), @"abcdef");
    CHECK_EQ(RTTruncate(@"abcdefghij", 5), @"abcd…");
    CHECK(RTTruncate(@"Città più lunga di così", 8).length == 8);
}

/// Stream ICY finto: [audio metaint][len][meta]... ; titles = un titolo per blocco ("" = blocco vuoto)
static NSData *IcyStream(NSUInteger metaint, NSArray<NSString *> *titles, NSStringEncoding enc)
{
    NSMutableData *d = [NSMutableData data];
    for (NSString *t in titles) {
        NSMutableData *audio = [NSMutableData dataWithLength:metaint];
        memset(audio.mutableBytes, 0xAB, metaint);
        [d appendData:audio];
        if (t.length == 0) {
            unsigned char zero = 0;
            [d appendBytes:&zero length:1];
            continue;
        }
        NSMutableData *meta = [[[NSString stringWithFormat:@"StreamTitle='%@';StreamUrl='';", t] dataUsingEncoding:enc] mutableCopy];
        NSUInteger blocks = (meta.length + 15) / 16;
        meta.length = blocks * 16;
        unsigned char len = (unsigned char)blocks;
        [d appendBytes:&len length:1];
        [d appendData:meta];
    }
    return d;
}

static void testIcy(void)
{
    NSArray *titles = @[@"Miles Davis - So What", @"", @"Mina - L'importante è finire", @"Mina - L'importante è finire"];
    NSData *stream = IcyStream(100, titles, NSUTF8StringEncoding);

    // tutto in un colpo
    RTIcyParser *p = [[RTIcyParser alloc] initWithMetaInterval:100];
    CHECK_EQ([p feed:stream], (@[@"Miles Davis - So What", @"Mina - L'importante è finire", @"Mina - L'importante è finire"]));

    // a pezzetti di 7 byte (i blocchi di rete tagliano ovunque)
    p = [[RTIcyParser alloc] initWithMetaInterval:100];
    NSMutableArray *found = [NSMutableArray array];
    for (NSUInteger i = 0; i < stream.length; i += 7) {
        [found addObjectsFromArray:[p feed:[stream subdataWithRange:NSMakeRange(i, MIN((NSUInteger)7, stream.length - i))]]];
    }
    CHECK(found.count == 3);
    CHECK_EQ(found.firstObject, @"Miles Davis - So What");

    // un byte alla volta
    p = [[RTIcyParser alloc] initWithMetaInterval:100];
    [found removeAllObjects];
    const unsigned char *b = stream.bytes;
    for (NSUInteger i = 0; i < stream.length; i++) [found addObjectsFromArray:[p feed:[NSData dataWithBytes:b + i length:1]]];
    CHECK(found.count == 3);

    // Latin-1
    p = [[RTIcyParser alloc] initWithMetaInterval:50];
    CHECK_EQ([p feed:IcyStream(50, @[@"Battiato - Centro di gravità"], NSISOLatin1StringEncoding)], @[@"Battiato - Centro di gravità"]);

    CHECK_EQ([RTIcyParser streamTitleFromMetadata:D(@"StreamTitle='';")], @"");
    CHECK_EQ([RTIcyParser streamTitleFromMetadata:D(@"StreamUrl='x';")], nil);
    CHECK_EQ([RTIcyParser streamTitleFromMetadata:D(@"StreamTitle='Senza fine")], @"Senza fine");
    CHECK_EQ([RTIcyParser streamTitleFromMetadata:D(@"streamtitle=\"A - B\";")], @"A - B");
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        testBookmarks();
        if (argc > 1) testBundledBookmarks([NSString stringWithUTF8String:argv[1]]);
        testDirect();
        testPLS();
        testM3U();
        testASX();
        testXSPF();
        testTrackInfo();
        testIcy();
        printf("%d verifiche, %d fallite\n", checks, failures);
    }
    return failures ? 1 : 0;
}
