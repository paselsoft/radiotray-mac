// Test della logica senza interfaccia: preferiti, playlist, titoli.
// Compilato ed eseguito da `make test` (anche sul runner macOS della CI).
#import <Foundation/Foundation.h>
#import "../src/RTBookmarks.h"
#import "../src/RTPlaylistParser.h"
#import "../src/RTTrackInfo.h"
#import "../src/RTIcyParser.h"
#import "../src/RTRadioBrowser.h"
#import "../src/RTBookmarksDocument.h"
#import "../src/RTLoginItem.h"
#import "../src/RTFavoriteTracks.h"
#import "../src/RTUpdateChecker.h"
#import "../src/RTArtwork.h"
#import "../src/RTAlarm.h"
#import "../src/RTBackup.h"
#import "../src/RTStationLogo.h"
#import "../src/RTStationChecker.h"

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

static void testAddStation(void)
{
    NSString *json = @"[ {\"group\":\"Jazz\",\"image\":\"x.png\",\"extra\":7,\"stations\":[{\"name\":\"A\",\"url\":\"http://a/\",\"notifications\":false}]} ]";
    NSString *error = nil;

    // gruppo esistente: la stazione va in fondo, gli altri campi restano
    NSData *out = [RTBookmarks dataByAddingStation:@"Radio 105" url:@"http://icecast.unitedradio.it/Radio105.mp3"
                                           toGroup:@"Jazz" inData:D(json) error:&error];
    CHECK(out != nil);
    NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    CHECK([text containsString:@"http://icecast.unitedradio.it/Radio105.mp3"]);   // niente "\/"
    CHECK(![text containsString:@"\\/"]);
    RTBookmarks *b = [RTBookmarks bookmarksWithData:out error:NULL];
    CHECK(b.groups.count == 1);
    CHECK([b groupNamed:@"Jazz"].stations.count == 2);
    CHECK_EQ([b groupNamed:@"Jazz"].stations.lastObject.name, @"Radio 105");
    CHECK(![b stationNamed:@"A" inGroup:@"Jazz"].notifications);
    CHECK_EQ([b groupNamed:@"Jazz"].image, @"x.png");
    NSArray *raw = [NSJSONSerialization JSONObjectWithData:out options:0 error:NULL];
    CHECK_EQ(raw[0][@"extra"], @7);

    // gruppo nuovo e gruppo root
    out = [RTBookmarks dataByAddingStation:@"Nuova" url:@"https://n/x" toGroup:@"Notizie" inData:out error:&error];
    out = [RTBookmarks dataByAddingStation:@"Sciolta" url:@"https://s/x" toGroup:@"root" inData:out error:&error];
    b = [RTBookmarks bookmarksWithData:out error:NULL];
    CHECK(b.groups.count == 3);
    CHECK_EQ([b stationNamed:@"Nuova" inGroup:@"Notizie"].url, @"https://n/x");
    CHECK([b groupNamed:@"root"].isRoot);

    // nome già presente nel gruppo
    error = nil;
    CHECK([RTBookmarks dataByAddingStation:@"A" url:@"http://b/" toGroup:@"Jazz" inData:out error:&error] == nil);
    CHECK([error containsString:@"già"]);
    // file non valido: non si tocca
    error = nil;
    CHECK([RTBookmarks dataByAddingStation:@"X" url:@"http://x/" toGroup:@"G" inData:D(@"[ {") error:&error] == nil);
    CHECK(error.length > 0);
    // campi vuoti
    CHECK([RTBookmarks dataByAddingStation:@"  " url:@"http://x/" toGroup:@"G" inData:D(@"[]") error:NULL] == nil);
    // file vuoto valido
    b = [RTBookmarks bookmarksWithData:[RTBookmarks dataByAddingStation:@"X" url:@"http://x/" toGroup:@"G" inData:D(@"[]") error:NULL] error:NULL];
    CHECK([b stationCount] == 1);
}

static void testStationName(void)
{
    CHECK_EQ([RTIcyParser stationNameFromHeader:@" Radio 105 "], @"Radio 105");
    CHECK_EQ([RTIcyParser stationNameFromHeader:@"no name"], nil);
    CHECK_EQ([RTIcyParser stationNameFromHeader:@"Unspecified"], nil);
    CHECK_EQ([RTIcyParser stationNameFromHeader:@""], nil);
    CHECK_EQ([RTIcyParser stationNameFromHeader:nil], nil);
    // UTF-8 letto come Latin-1
    NSString *mangled = [[NSString alloc] initWithData:[@"Radio Città" dataUsingEncoding:NSUTF8StringEncoding]
                                              encoding:NSISOLatin1StringEncoding];
    CHECK_EQ([RTIcyParser stationNameFromHeader:mangled], @"Radio Città");
    // Latin-1 vero: resta com'è
    CHECK_EQ([RTIcyParser stationNameFromHeader:@"Radio Città"], @"Radio Città");
}

static void testRadioBrowser(void)
{
    NSString *json = @"["
        "{\"name\":\" Radio 24 \",\"url\":\"http://x/listen.pls\",\"url_resolved\":\"http://x/stream\",\"countrycode\":\"it\",\"codec\":\"mp3\",\"bitrate\":128,\"tags\":\"news,talk\",\"votes\":50,\"hls\":0},"
        "{\"name\":\"Radio Ogg\",\"url\":\"http://o/\",\"url_resolved\":\"\",\"countrycode\":\"IT\",\"codec\":\"OGG\",\"bitrate\":0},"
        "{\"name\":\"Radio HLS\",\"url\":\"https://h/master.m3u8\",\"codec\":\"UNKNOWN\",\"hls\":1},"
        "{\"name\":\" Radio 24 \",\"url\":\"http://x/listen.pls\",\"url_resolved\":\"http://x/stream\"},"
        "{\"name\":\"Senza URL\",\"url\":\"\"},"
        "{\"name\":\"Altro schema\",\"url\":\"mms://m/\"},"
        "42 ]";
    NSArray<RTFoundStation *> *list = [RTRadioBrowser stationsFromJSON:D(json)];
    CHECK(list.count == 3);
    CHECK_EQ(list[0].name, @"Radio 24");
    CHECK_EQ(list[0].url, @"http://x/stream");
    CHECK_EQ(list[0].country, @"IT");
    CHECK_EQ(list[0].formatDescription, @"MP3 128 kbps");
    CHECK_EQ(list[0].tags, @"news, talk");
    CHECK(list[0].playable);
    CHECK_EQ(list[1].name, @"Radio HLS");          // le riproducibili prima
    CHECK_EQ(list[1].formatDescription, @"HLS");
    CHECK_EQ(list[2].name, @"Radio Ogg");          // non riproducibile in fondo
    CHECK(!list[2].playable);
    CHECK_EQ(list[2].url, @"http://o/");
    CHECK([RTRadioBrowser stationsFromJSON:D(@"{}")] == nil);
    CHECK([RTRadioBrowser stationsFromJSON:D(@"[]")].count == 0);
}

static void testItalianExtras(void)
{
    // titoli Mediaset
    RTTrackInfo *t = [RTTrackInfo infoWithStreamTitle:@"PINGUINI TATTICI NUCLEARI~NELLA BORSA DI ANNA~REPLAY~2026~IT5LS2600016~184~2026-11-15T15:39:05~2026-11-15T15:39:05~R101" split:YES];
    CHECK_EQ(t.artist, @"Pinguini Tattici Nucleari");
    CHECK_EQ(t.title, @"Nella Borsa Di Anna");
    t = [RTTrackInfo infoWithStreamTitle:@"U2~SILENCIO~CARNAVAL DE LUZ~2026~~144~a~b~Virgin Radio" split:YES];
    CHECK_EQ(t.artist, @"U2");
    CHECK_EQ(t.title, @"Silencio");
    t = [RTTrackInfo infoWithStreamTitle:@"U2~SILENCIO~X~2026" split:NO];
    CHECK_EQ(t.title, @"U2 - Silencio");
    // maiuscole solo se tutto il testo è maiuscolo
    t = [RTTrackInfo infoWithStreamTitle:@"THE CLASH - ROCK THE CASBAH" split:YES];
    CHECK_EQ(t.artist, @"The Clash");
    CHECK_EQ(t.title, @"Rock The Casbah");
    t = [RTTrackInfo infoWithStreamTitle:@"AC/DC - Back In Black" split:YES];
    CHECK_EQ(t.title, @"Back In Black");

    // nomi tecnici dei server
    CHECK_EQ([RTIcyParser stationNameFromHeader:@"FM_VRG_mp3_radiomediaset"], nil);
    CHECK_EQ([RTIcyParser stationNameFromHeader:@"RadioFreccia"], @"RadioFreccia");

    // unione con il file dell'utente
    NSString *mine = @"[{\"group\":\"Rai\",\"stations\":[{\"name\":\"Radio Uno\",\"url\":\"http://icestreaming.rai.it/1.mp3\"}]}]";
    NSString *list = @"[{\"group\":\"Radio italiane\",\"stations\":[{\"name\":\"RTL 102.5\",\"url\":\"https://a/rtl\"}]},"
                      "{\"group\":\"Rai\",\"stations\":[{\"name\":\"Rai Radio 1\",\"url\":\"https://icestreaming.rai.it/1.mp3\"},"
                      "{\"name\":\"Rai Radio 2\",\"url\":\"https://icestreaming.rai.it/2.mp3\"}]}]";
    NSUInteger added = 99;
    NSString *error = nil;
    NSData *out = [RTBookmarks dataByMergingStations:[RTBookmarks bookmarksWithData:D(list) error:NULL]
                                            intoData:D(mine) added:&added error:&error];
    CHECK(out != nil);
    CHECK(added == 2);   // Rai Radio 1 c'è già (stesso indirizzo, anche se http e nome diverso)
    RTBookmarks *b = [RTBookmarks bookmarksWithData:out error:NULL];
    CHECK([b stationCount] == 3);
    CHECK_EQ([b stationNamed:@"Radio Uno" inGroup:@"Rai"].url, @"http://icestreaming.rai.it/1.mp3");
    CHECK([b stationNamed:@"Rai Radio 2" inGroup:@"Rai"] != nil);
    CHECK([b stationNamed:@"RTL 102.5" inGroup:@"Radio italiane"] != nil);
    // seconda volta: niente da aggiungere
    [RTBookmarks dataByMergingStations:[RTBookmarks bookmarksWithData:D(list) error:NULL] intoData:out added:&added error:NULL];
    CHECK(added == 0);
}

static void testBundledList(NSString *path)
{
    NSString *error = nil;
    RTBookmarks *b = [RTBookmarks bookmarksWithContentsOfFile:path error:&error];
    CHECK(b != nil);
    if (!b) fprintf(stderr, "  %s\n", error.UTF8String);
    CHECK([b stationCount] >= 15);
}

static void testDocument(void)
{
    NSString *json = @"[{\"group\":\"Jazz\",\"image\":\"j.png\",\"stations\":["
                      "{\"name\":\"A\",\"url\":\"http://a/\",\"notifications\":false},"
                      "{\"name\":\"B\",\"url\":\"http://b/\"}]},"
                      "{\"group\":\"Rock\",\"stations\":[{\"name\":\"C\",\"url\":\"http://c/\"}]},"
                      "{\"group\":\"root\",\"stations\":[]}]";
    NSString *error = nil;
    RTBookmarksDocument *doc = [RTBookmarksDocument documentWithData:D(json) error:&error];
    CHECK(doc != nil);
    CHECK(doc.groups.count == 3);
    RTDocGroup *jazz = doc.groups[0], *rock = doc.groups[1], *root = doc.groups[2];
    RTDocStation *a = jazz.stations[0], *b = jazz.stations[1], *c = rock.stations[0];
    CHECK(root.isRoot);
    CHECK_EQ([RTBookmarksDocument displayNameForGroup:root], @"(senza gruppo)");

    // rinomina e indirizzo
    CHECK([doc renameStation:a to:@"  Alfa "] == nil);
    CHECK_EQ(a.name, @"Alfa");
    CHECK([doc renameStation:b to:@"alfa"] != nil);           // doppione (maiuscole ignorate)
    CHECK([doc renameStation:b to:@""] != nil);
    CHECK([doc setURL:@"ftp://x" forStation:b] != nil);
    CHECK([doc setURL:@"https://b2/" forStation:b] == nil);
    CHECK([doc renameGroup:jazz to:@"Rock"] != nil);
    CHECK([doc renameGroup:jazz to:@"root"] != nil);
    CHECK([doc renameGroup:root to:@"X"] != nil);
    CHECK([doc renameGroup:jazz to:@"Jazz e blues"] == nil);

    // spostamenti
    CHECK([doc moveStation:b toGroup:jazz atIndex:0] == nil);
    CHECK(jazz.stations[0] == b);
    CHECK([doc moveStation:a toGroup:rock atIndex:0] == nil);
    CHECK(rock.stations[0] == a && rock.stations[1] == c && a.group == rock);
    CHECK([doc moveGroup:root toIndex:0] == nil);
    CHECK(doc.groups[0] == root);
    CHECK([doc moveGroup:root toIndex:99] == nil);
    CHECK(doc.groups.lastObject == root);

    // aggiunta ed eliminazione
    RTDocGroup *news = nil;
    CHECK([doc addGroupNamed:@"Notizie" atIndex:1 group:&news] == nil);
    CHECK(doc.groups[1] == news);
    CHECK([doc addGroupNamed:@"notizie" atIndex:0 group:NULL] != nil);
    RTDocStation *r24 = nil;
    CHECK([doc addStationNamed:@"Radio 24" url:@"http://r24/listen.pls" toGroup:news atIndex:0 station:&r24] == nil);
    CHECK([doc addStationNamed:@"Radio 24" url:@"http://r24/" toGroup:news atIndex:0 station:NULL] != nil);
    CHECK([doc addStationNamed:@"X" url:@"non un url" toGroup:news atIndex:0 station:NULL] != nil);
    CHECK([doc moveStation:c toGroup:news atIndex:5] == nil);   // indice oltre la fine: in fondo
    CHECK(news.stations.lastObject == c);
    CHECK([doc removeStation:a] == nil);
    CHECK([doc removeStation:a] != nil);
    CHECK([doc removeGroup:rock] == nil);
    CHECK([doc rootGroup] == root);

    // salvataggio: campi sconosciuti conservati, il risultato è un file valido
    NSData *out = [doc dataRepresentation];
    NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    CHECK(![text containsString:@"\\/"]);
    RTBookmarks *bm = [RTBookmarks bookmarksWithData:out error:&error];
    CHECK(bm != nil);
    CHECK_EQ([bm groupNamed:@"Jazz e blues"].image, @"j.png");
    CHECK_EQ([bm stationNamed:@"B" inGroup:@"Jazz e blues"].url, @"https://b2/");
    CHECK_EQ([bm stationNamed:@"Radio 24" inGroup:@"Notizie"].url, @"http://r24/listen.pls");
    CHECK([bm stationNamed:@"C" inGroup:@"Notizie"] != nil);
    CHECK([bm groupNamed:@"Rock"] == nil);
    NSArray *names = [bm.groups valueForKey:@"name"];
    CHECK_EQ(names, (@[@"Jazz e blues", @"Notizie", @"root"]));

    // "root" creato se manca
    RTBookmarksDocument *empty = [RTBookmarksDocument documentWithData:D(@"[]") error:NULL];
    CHECK([empty rootGroup].isRoot && empty.groups.count == 1);
    // file non valido: niente editor
    CHECK([RTBookmarksDocument documentWithData:D(@"[{") error:&error] == nil);
}

static void testLoginItem(void)
{
    NSDictionary *p = [RTLoginItem agentPlistForAppPath:@"/Applications/RadioTray.app"];
    CHECK_EQ(p[@"ProgramArguments"], (@[@"/usr/bin/open", @"-g", @"/Applications/RadioTray.app"]));
    CHECK_EQ(p[@"RunAtLoad"], @YES);
    CHECK([[RTLoginItem agentPath] hasSuffix:@"Library/LaunchAgents/io.github.paselsoft.radiotray-mac.plist"]);
    // dal disco scaricato non si attiva (e non si scrive niente)
    NSString *problem = [RTLoginItem setEnabled:YES appPath:@"/Volumes/RadioTray/RadioTray.app"];
    CHECK(problem.length > 0);
}

static void testFavorites(void)
{
    RTFavoriteTracks *f = [RTFavoriteTracks tracksWithData:nil error:NULL];
    CHECK(f.tracks.count == 0);
    NSDate *d1 = [NSDate dateWithTimeIntervalSince1970:1700000000];
    NSDate *d2 = [NSDate dateWithTimeIntervalSince1970:1800000000];
    BOOL already = YES;
    RTFavoriteTrack *a = [f addTitle:@" Fresh Moods " artist:@"Divent" station:@"SomaFM Groove Salad" date:d1 alreadyPresent:&already];
    CHECK(!already);
    CHECK_EQ(a.title, @"Fresh Moods");
    CHECK_EQ(a.displayText, @"Fresh Moods – Divent");
    CHECK_EQ(a.searchText, @"Divent Fresh Moods");
    [f addTitle:@"fresh moods" artist:@"DIVENT" station:@"Altra" date:d2 alreadyPresent:&already];
    CHECK(already);                       // stesso brano, maiuscole diverse
    CHECK(f.tracks.count == 1);
    [f addTitle:@"Questa insostenibile leggerezza dell'essere" artist:@"Antonello Venditti" station:@"Radio Monte Carlo"
           date:d2 alreadyPresent:NULL];
    [f addTitle:@"" artist:@"Solo Artista" station:@"Radio Città" date:d1 alreadyPresent:NULL];
    CHECK(f.tracks.count == 3);
    CHECK_EQ(f.tracks[2].title, @"Solo Artista");
    CHECK([f trackWithTitle:@"FRESH MOODS" artist:@"divent"] == a);

    // salvataggio e rilettura
    NSData *data = [f dataRepresentation];
    RTFavoriteTracks *g = [RTFavoriteTracks tracksWithData:data error:NULL];
    CHECK(g.tracks.count == 3);
    CHECK_EQ(g.tracks[1].artist, @"Antonello Venditti");
    CHECK(fabs([g.tracks[0].added timeIntervalSinceDate:d1]) < 1);
    CHECK([RTFavoriteTracks tracksWithData:D(@"{}") error:NULL] == nil);

    // stazioni, ricerca (maiuscole e accenti ignorati, più parole), filtro, ordinamento
    CHECK_EQ([g stations], (@[@"Radio Città", @"Radio Monte Carlo", @"SomaFM Groove Salad"]));
    NSArray *byDate = @[[NSSortDescriptor sortDescriptorWithKey:@"added" ascending:NO]];
    CHECK([g tracksMatching:@"" station:nil sortDescriptors:byDate].count == 3);
    CHECK_EQ([g tracksMatching:@"" station:nil sortDescriptors:byDate].firstObject.artist, @"Antonello Venditti");
    CHECK([g tracksMatching:@"citta" station:nil sortDescriptors:@[]].count == 1);
    CHECK([g tracksMatching:@"venditti leggerezza" station:nil sortDescriptors:@[]].count == 1);
    CHECK([g tracksMatching:@"venditti divent" station:nil sortDescriptors:@[]].count == 0);
    CHECK([g tracksMatching:nil station:@"SomaFM Groove Salad" sortDescriptors:@[]].count == 1);
    NSArray *byTitle = @[[NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES selector:@selector(localizedStandardCompare:)]];
    CHECK_EQ([g tracksMatching:nil station:nil sortDescriptors:byTitle].firstObject.title, @"Fresh Moods");

    // eliminazione
    [g removeTracks:@[g.tracks[0]]];
    CHECK(g.tracks.count == 2);

    // CSV: intestazione, virgolette raddoppiate, separatore ";"
    RTFavoriteTracks *h = [RTFavoriteTracks new];
    [h addTitle:@"Il \"mio\" brano" artist:@"A; B" station:@"S" date:d1 alreadyPresent:NULL];
    NSData *csvData = [RTFavoriteTracks csvForTracks:h.tracks];
    // BOM UTF-8 (EF BB BF) all'inizio del file: la lettura come testo lo toglie, quindi si controllano i byte
    const unsigned char *bom = csvData.bytes;
    CHECK(csvData.length > 3 && bom[0] == 0xEF && bom[1] == 0xBB && bom[2] == 0xBF);
    NSString *csv = [[NSString alloc] initWithData:[csvData subdataWithRange:NSMakeRange(3, csvData.length - 3)]
                                          encoding:NSUTF8StringEncoding];
    CHECK([csv hasPrefix:@"Titolo;Artista;Stazione;Aggiunto il\r\n"]);
    CHECK([csv containsString:@"\"Il \"\"mio\"\" brano\";\"A; B\";\"S\";"]);

    // ricerche sul web
    RTFavoriteTrack *t = h.tracks[0];
    t.title = @"Città";
    t.artist = @"Mina & Celentano";
    NSString *yt = [RTFavoriteTracks searchURLForTrack:t site:RTTrackSearchYouTube].absoluteString;
    CHECK([yt hasPrefix:@"https://www.youtube.com/results?search_query=Mina"]);
    CHECK([yt containsString:@"%26"]);   // la "&" non spezza la ricerca
    CHECK([[RTFavoriteTracks searchURLForTrack:t site:RTTrackSearchAppleMusic].absoluteString hasPrefix:@"https://music.apple.com/it/search?term="]);
    NSString *sp = [RTFavoriteTracks searchURLForTrack:t site:RTTrackSearchSpotify].absoluteString;
    CHECK([sp hasPrefix:@"https://open.spotify.com/search/Mina%20"]);
    CHECK([[RTFavoriteTracks searchURLForTrack:t site:RTTrackSearchYouTubeMusic].absoluteString
           hasPrefix:@"https://music.youtube.com/search?q=Mina%20%26%20Celentano%20Citt%C3%A0"]);
}

static void testHistoryAndUpdates(void)
{
    RTFavoriteTracks *h = [RTFavoriteTracks new];
    NSDate *d = [NSDate date];
    CHECK([h recordTitle:@"A" artist:@"X" station:@"S1" date:d limit:3]);
    CHECK(![h recordTitle:@"a" artist:@"x" station:@"S1" date:d limit:3]);   // uguale all'ultimo: niente
    CHECK([h recordTitle:@"B" artist:@"Y" station:@"S1" date:d limit:3]);
    CHECK([h recordTitle:@"A" artist:@"X" station:@"S2" date:d limit:3]);    // torna: spostato in fondo
    CHECK(h.tracks.count == 2);
    CHECK_EQ(h.tracks.lastObject.station, @"S2");
    [h recordTitle:@"C" artist:@"" station:@"S" date:d limit:3];
    [h recordTitle:@"D" artist:@"" station:@"S" date:d limit:3];
    CHECK(h.tracks.count == 3);                                              // limite
    CHECK_EQ(h.tracks.firstObject.title, @"A");
    CHECK(![h recordTitle:@"" artist:@"" station:@"S" date:d limit:3]);
    [h removeAllTracks];
    CHECK(h.tracks.count == 0);

    CHECK([RTUpdateChecker version:@"1.2.0" isNewerThan:@"1.1.0"]);
    CHECK([RTUpdateChecker version:@"v1.10.0" isNewerThan:@"1.9.2"]);
    CHECK([RTUpdateChecker version:@"1.1.1" isNewerThan:@"1.1"]);
    CHECK(![RTUpdateChecker version:@"1.1.0" isNewerThan:@"1.1.0"]);
    CHECK(![RTUpdateChecker version:@"1.0.9" isNewerThan:@"1.1.0"]);
    CHECK(![RTUpdateChecker version:@"1.1" isNewerThan:@"1.1.0"]);
    NSDictionary *r = [RTUpdateChecker releaseFromJSON:D(@"{\"tag_name\":\"v1.3.0\",\"html_url\":\"https://github.com/x/y/releases/tag/v1.3.0\",\"draft\":false,\"prerelease\":false}")];
    CHECK_EQ(r[@"version"], @"1.3.0");
    CHECK_EQ(r[@"url"], @"https://github.com/x/y/releases/tag/v1.3.0");
    CHECK([RTUpdateChecker releaseFromJSON:D(@"{\"tag_name\":\"v2\",\"html_url\":\"u\",\"prerelease\":true}")] == nil);
    CHECK([RTUpdateChecker releaseFromJSON:D(@"{\"message\":\"Not Found\"}")] == nil);
    CHECK([RTUpdateChecker releaseFromJSON:D(@"[]")] == nil);
}

static NSDate *Day(NSInteger y, NSInteger m, NSInteger d, NSInteger h, NSInteger min, NSCalendar *cal)
{
    NSDateComponents *c = [NSDateComponents new];
    c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min;
    return [cal dateFromComponents:c];
}

static void testAlarmAndArtwork(void)
{
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneWithName:@"Europe/Rome"];
    // lunedì 16 novembre 2026
    NSDate *mon0729 = Day(2026, 11, 16, 7, 29, cal), *mon0730 = Day(2026, 11, 16, 7, 30, cal);
    NSDate *mon0740 = Day(2026, 11, 16, 7, 40, cal), *mon0741 = Day(2026, 11, 16, 7, 41, cal);
    NSDate *sat0730 = Day(2026, 11, 21, 7, 30, cal);
    NSInteger t = 7 * 60 + 30;
    CHECK(![RTAlarm shouldFireAt:mon0729 minutes:t days:RTAlarmWeekdays lastFired:nil calendar:cal]);
    CHECK([RTAlarm shouldFireAt:mon0730 minutes:t days:RTAlarmWeekdays lastFired:nil calendar:cal]);
    CHECK([RTAlarm shouldFireAt:mon0740 minutes:t days:RTAlarmWeekdays lastFired:nil calendar:cal]);    // Mac appena sveglio
    CHECK(![RTAlarm shouldFireAt:mon0741 minutes:t days:RTAlarmWeekdays lastFired:nil calendar:cal]);   // troppo tardi
    CHECK(![RTAlarm shouldFireAt:mon0740 minutes:t days:RTAlarmWeekdays lastFired:mon0730 calendar:cal]); // già suonata oggi
    CHECK([RTAlarm shouldFireAt:mon0730 minutes:t days:RTAlarmWeekdays lastFired:Day(2026, 11, 13, 7, 30, cal) calendar:cal]);
    CHECK(![RTAlarm shouldFireAt:sat0730 minutes:t days:RTAlarmWeekdays lastFired:nil calendar:cal]);   // sabato escluso
    CHECK([RTAlarm shouldFireAt:sat0730 minutes:t days:RTAlarmSaturday | RTAlarmSunday lastFired:nil calendar:cal]);
    CHECK_EQ([RTAlarm nextFireAfter:mon0730 minutes:t days:RTAlarmWeekdays calendar:cal], Day(2026, 11, 17, 7, 30, cal));
    CHECK_EQ([RTAlarm nextFireAfter:mon0729 minutes:t days:RTAlarmWeekdays calendar:cal], mon0730);
    CHECK_EQ([RTAlarm nextFireAfter:Day(2026, 11, 20, 8, 0, cal) minutes:t days:RTAlarmWeekdays calendar:cal], Day(2026, 11, 23, 7, 30, cal));
    CHECK([RTAlarm nextFireAfter:mon0729 minutes:t days:0 calendar:cal] == nil);
    CHECK_EQ([RTAlarm describeDays:RTAlarmWeekdays], @"Lu–Ve");
    CHECK_EQ([RTAlarm describeDays:RTAlarmEveryDay], @"Tutti i giorni");
    CHECK_EQ([RTAlarm describeDays:RTAlarmMonday | RTAlarmWednesday | RTAlarmFriday], @"Lu, Me, Ve");
    CHECK_EQ([RTAlarm describeMinutes:7 * 60 + 5], @"07:05");

    CHECK_EQ([RTArtwork normalized:@"Città & Mina!"], @"cittamina");
    NSString *json = @"{\"results\":["
        "{\"artistName\":\"Altro\",\"trackName\":\"Fresh Moods\",\"artworkUrl100\":\"https://a/1/100x100bb.jpg\"},"
        "{\"artistName\":\"Divent\",\"trackName\":\"Altro brano\",\"artworkUrl100\":\"https://a/2/100x100bb.jpg\"},"
        "{\"artistName\":\"Divent\",\"trackName\":\"Fresh Moods (Radio Edit)\",\"artworkUrl100\":\"https://a/3/100x100bb.jpg\"}]}";
    CHECK_EQ([RTArtwork artworkURLFromJSON:D(json) title:@"Fresh Moods" artist:@"Divent"], @"https://a/3/600x600bb.jpg");
    // solo l'artista giusto, anche se il titolo non corrisponde
    CHECK_EQ([RTArtwork artworkURLFromJSON:D(json) title:@"Sconosciuto" artist:@"DIVENT"], @"https://a/2/600x600bb.jpg");
    // artista diverso: nessuna copertina (meglio niente che sbagliata)
    CHECK([RTArtwork artworkURLFromJSON:D(json) title:@"Fresh Moods" artist:@"Nessuno"] == nil);
    // "Mina & Celentano" accetta "Mina"
    NSString *mina = @"{\"results\":[{\"artistName\":\"Mina\",\"trackName\":\"Acqua e sale\",\"artworkUrl100\":\"https://m/100x100bb.jpg\"}]}";
    CHECK_EQ([RTArtwork artworkURLFromJSON:D(mina) title:@"Acqua e sale" artist:@"Mina & Celentano"], @"https://m/600x600bb.jpg");
    CHECK([RTArtwork artworkURLFromJSON:D(@"{}") title:@"a" artist:@"b"] == nil);
}

static void testBackup(void)
{
    RTBackupContents *c = [RTBackupContents new];
    c.bookmarks = D(@"[{\"group\":\"Jazz\",\"stations\":[{\"name\":\"A\",\"url\":\"http://a/x\"}]}]");
    RTFavoriteTracks *f = [RTFavoriteTracks new];
    [f addTitle:@"Brano" artist:@"Artista" station:@"A" date:[NSDate dateWithTimeIntervalSince1970:1800000000] alreadyPresent:NULL];
    c.favorites = [f dataRepresentation];
    c.history = nil;
    c.settings = [RTBackup exportableSettings:@{ @"volume-level": @70, @"notifications": @YES,
                                                 @"listening-seconds": @{ @"Jazz\nA": @3600 },
                                                 @"last-update-check": [NSDate date],          // data: esclusa
                                                 @"NSWindow Frame Stazioni": @"0 0 100 100",    // di sistema: esclusa
                                                 @"alarm-last-fired": @"x" }];
    CHECK(c.settings.count == 3);
    CHECK_EQ(c.settings[@"volume-level"], @70);
    c.appVersion = @"1.4.0";
    c.created = [NSDate dateWithTimeIntervalSince1970:1800000000];

    NSData *data = [RTBackup dataForContents:c];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    CHECK([text containsString:@"\"format\" : \"radiotray-mac-backup\""]);
    CHECK([text containsString:@"http://a/x"]);

    NSString *error = nil;
    RTBackupContents *back = [RTBackup contentsFromData:data error:&error];
    CHECK(back != nil);
    CHECK([[RTBookmarks bookmarksWithData:back.bookmarks error:NULL] stationCount] == 1);
    CHECK_EQ([RTFavoriteTracks tracksWithData:back.favorites error:NULL].tracks.firstObject.artist, @"Artista");
    CHECK(back.history == nil);
    CHECK_EQ(back.settings[@"listening-seconds"][@"Jazz\nA"], @3600);
    CHECK_EQ(back.appVersion, @"1.4.0");
    CHECK(fabs([back.created timeIntervalSince1970] - 1800000000) < 1);

    CHECK([RTBackup contentsFromData:D(@"{\"a\":1}") error:&error] == nil);
    CHECK([error containsString:@"non è un backup"]);
    CHECK([RTBackup contentsFromData:D(@"{\"format\":\"radiotray-mac-backup\",\"version\":9}") error:&error] == nil);
    CHECK([error containsString:@"più recente"]);
    CHECK([RTBackup contentsFromData:D(@"{\"format\":\"radiotray-mac-backup\",\"version\":1,\"bookmarks\":{}}") error:&error] == nil);

    // copie datate: si tengono le ultime 2
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    for (int day = 1; day <= 4; day++) {
        CHECK([RTBackup writeBackup:data toFolder:dir keep:2 date:[NSDate dateWithTimeIntervalSince1970:1800000000 + day * 86400]] == nil);
    }
    NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    CHECK(files.count == 3);   // RadioTray-backup.json + 2 copie datate
    CHECK([files containsObject:@"RadioTray-backup.json"]);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
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
        testAddStation();
        testStationName();
        testRadioBrowser();
        testItalianExtras();
        testDocument();
        testLoginItem();
        testFavorites();
        testHistoryAndUpdates();
        testAlarmAndArtwork();
        testBackup();
        // 1.4.1: formato "Titolo * Artista * codice" e scambio
        {
            RTTrackInfo *t = [RTTrackInfo infoWithStreamTitle:@"Tusa * Karol G, Nicki Minaj * 11712" split:YES];
            CHECK_EQ(t.title, @"Tusa");
            CHECK_EQ(t.artist, @"Karol G, Nicki Minaj");
            t = [RTTrackInfo infoWithStreamTitle:@"Round And Round - Spandau Ballet" split:YES];
            CHECK_EQ(t.artist, @"Round And Round");
            CHECK_EQ(t.swapped.title, @"Round And Round");
            CHECK_EQ(t.swapped.artist, @"Spandau Ballet");
            CHECK([[RTTrackInfo infoWithTitle:@"Solo" artist:nil].swapped.title isEqualToString:@"Solo"]);
            CHECK_EQ([RTTrackInfo infoWithStreamTitle:@"Tusa * Karol G" split:NO].title, @"Karol G - Tusa");
            // 1.4.2: il nome della stazione non è un brano
            CHECK([[RTTrackInfo infoWithStreamTitle:@"Radio 105" split:YES] isFillerForStation:@"Radio 105 Network"]);
            CHECK([[RTTrackInfo infoWithStreamTitle:@"RadioFreccia" split:YES] isFillerForStation:@"Radiofreccia"]);
            CHECK([[RTTrackInfo infoWithStreamTitle:@"Radio Kiss Kiss - Play everywhere!" split:YES] isFillerForStation:@"Radio Kiss Kiss"]);
            CHECK([[RTTrackInfo infoWithStreamTitle:@"-~RADIO SUBASIO - Suoni Emozioni e Sogni~~~~~x~y~United Music Radio Subasio" split:YES]
                   isFillerForStation:@"Radio Subasio"]);
            CHECK(![[RTTrackInfo infoWithStreamTitle:@"Queen - Radio Ga Ga" split:YES] isFillerForStation:@"Radio Monte Carlo"]);
            CHECK(![[RTTrackInfo infoWithStreamTitle:@"Sting - Fields Of Gold" split:YES] isFillerForStation:@"Radio 105 Network"]);
            // logo dall'archivio
            CHECK_EQ([RTStationLogo bestFaviconFromJSON:D(@"[{\"favicon\":\"https://x/logo.svg\"},{\"favicon\":\"\"},"
                      "{\"favicon\":\"https://www.facebook.com/a/b\"},{\"favicon\":\"https://www.radioitalia.it/images/logo.png\"}]")],
                     @"https://www.radioitalia.it/images/logo.png");
            CHECK([RTStationLogo bestFaviconFromJSON:D(@"[]")] == nil);
        }
        // 1.5.0: copertine ufficiali di RDS (JSON nei metadati HLS, preceduto da byte binari)
        {
            NSMutableData *priv = [NSMutableData dataWithBytes:"RDS\0\x01" length:5];
            [priv appendData:D(@"{\"type\":\"song\",\"titolo\":\"Flowers\",\"artista\":\"Miley Cyrus\","
                               "\"cover\":\"https://web.rds.it/m/l56169?radio_id=1\"}")];
            NSDictionary *song = [RTTrackInfo stationSongFromData:priv];
            CHECK_EQ(song[@"title"], @"Flowers");
            CHECK_EQ(song[@"artist"], @"Miley Cyrus");
            CHECK_EQ(song[@"cover"], @"https://web.rds.it/m/l56169?radio_id=1");
            CHECK([RTTrackInfo stationSongFromData:D(@"{\"type\":\"spot\",\"titolo\":\"Pubblicità\"}")] == nil);
            CHECK([RTTrackInfo stationSongFromData:D(@"Sting - Fields Of Gold")] == nil);
            CHECK([RTTrackInfo stationSongFromData:nil] == nil);
            // verifica delle stazioni
            CHECK([RTStationChecker isAudioResponseStatus:200 contentType:@"audio/mpeg"]);
            CHECK([RTStationChecker isAudioResponseStatus:200 contentType:@"application/vnd.apple.mpegurl"]);
            CHECK([RTStationChecker isAudioResponseStatus:200 contentType:nil]);
            CHECK(![RTStationChecker isAudioResponseStatus:200 contentType:@"text/html; charset=utf-8"]);
            CHECK(![RTStationChecker isAudioResponseStatus:404 contentType:@"audio/mpeg"]);
        }
        // 1.6.0: importazione di playlist scaricate
        {
            NSString *problem = nil;
            NSArray *st = [RTPlaylistParser stationsFromPlaylistData:D(@"[playlist]\nNumberOfEntries=3\n"
                "File1=http://a.example/stream\nTitle1=(#1 - 12/500) Radio Paradise\n"
                "File2=http://b.example/stream\nTitle2=(#2 - 3/500) Radio Paradise\n"
                "File3=http://c.example/stream\nVersion=2\n") fileName:@"radioparadise.pls" problem:&problem];
            CHECK(st.count == 1);
            CHECK_EQ(st.firstObject[@"name"], @"Radio Paradise");
            CHECK_EQ(st.firstObject[@"url"], @"http://a.example/stream");
            st = [RTPlaylistParser stationsFromPlaylistData:D(@"#EXTM3U\n#EXTINF:-1,Radio Uno\nhttp://x/1\n"
                "#EXTINF:-1,Radio Due\nhttps://x/2\n") fileName:@"lista.m3u" problem:NULL];
            CHECK(st.count == 2);
            CHECK_EQ(st[1][@"name"], @"Radio Due");
            CHECK_EQ(st[1][@"url"], @"https://x/2");
            st = [RTPlaylistParser stationsFromPlaylistData:D(@"http://y/live.mp3\r\nhttp://y/backup.mp3\r\n")
                                                   fileName:@"radio_italia-anni_60.m3u" problem:NULL];
            CHECK(st.count == 1);
            CHECK_EQ(st.firstObject[@"name"], @"radio italia anni 60");
            CHECK_EQ(st.firstObject[@"url"], @"http://y/live.mp3");
            problem = nil;
            CHECK([RTPlaylistParser stationsFromPlaylistData:D(@"#EXTM3U\n#EXT-X-VERSION:3\nseg1.ts\n") fileName:@"a.m3u8" problem:&problem] == nil);
            CHECK([problem containsString:@"HLS"]);
            CHECK([RTPlaylistParser stationsFromPlaylistData:D(@"[playlist]\nNumberOfEntries=0\n") fileName:@"x.pls" problem:&problem] == nil);
        }
        if (argc > 2) testBundledList([NSString stringWithUTF8String:argv[2]]);
        printf("%d verifiche, %d fallite\n", checks, failures);
    }
    return failures ? 1 : 0;
}
