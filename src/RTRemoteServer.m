#import "RTRemoteServer.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

static const NSTimeInterval RTRemoteReadTimeout = 10.0;

@interface RTRemoteServer ()
@property (nonatomic) int listenSocket;
@property (nonatomic, strong, nullable) dispatch_source_t acceptSource;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, readwrite) BOOL running;
@end

@implementation RTRemoteServer

- (instancetype)init
{
    if ((self = [super init])) {
        _listenSocket = -1;
        _queue = dispatch_queue_create("radiotray.remote", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (NSString *)startOnPort:(uint16_t)port
{
    [self stop];
    // IPv6 con IPv4 incluso (indirizzi ::ffff:a.b.c.d): una sola presa per tutti e due
    int s = socket(AF_INET6, SOCK_STREAM, 0);
    if (s < 0) return [NSString stringWithFormat:@"socket: %s", strerror(errno)];
    int yes = 1, no = 0;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &no, sizeof no);
    setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
    struct sockaddr_in6 addr;
    memset(&addr, 0, sizeof addr);
    addr.sin6_len = sizeof addr;
    addr.sin6_family = AF_INET6;
    addr.sin6_port = htons(port);
    addr.sin6_addr = in6addr_any;
    if (bind(s, (struct sockaddr *)&addr, sizeof addr) != 0) {
        int err = errno;
        close(s);
        if (err == EADDRINUSE) return [NSString stringWithFormat:@"La porta %u è già usata da un altro programma.", (unsigned)port];
        return [NSString stringWithFormat:@"Impossibile usare la porta %u (%s).", (unsigned)port, strerror(err)];
    }
    if (listen(s, 16) != 0) {
        int err = errno;
        close(s);
        return [NSString stringWithFormat:@"listen: %s", strerror(err)];
    }
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK);
    self.listenSocket = s;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)s, 0, self.queue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{ [weakSelf acceptConnections]; });
    dispatch_source_set_cancel_handler(source, ^{ close(s); });
    self.acceptSource = source;
    dispatch_resume(source);
    self.running = YES;
    NSLog(@"RadioTray: telecomando in ascolto sulla porta %u", (unsigned)port);
    return nil;
}

- (void)stop
{
    if (self.acceptSource) dispatch_source_cancel(self.acceptSource);   // chiude la presa
    self.acceptSource = nil;
    self.listenSocket = -1;
    self.running = NO;
}

/// Indirizzo di chi chiede, come testo ("192.168.1.20", "fe80::…").
static NSString *RTPeerAddress(const struct sockaddr_storage *ss)
{
    char buf[INET6_ADDRSTRLEN] = {0};
    if (ss->ss_family == AF_INET) {
        inet_ntop(AF_INET, &((const struct sockaddr_in *)ss)->sin_addr, buf, sizeof buf);
    } else if (ss->ss_family == AF_INET6) {
        inet_ntop(AF_INET6, &((const struct sockaddr_in6 *)ss)->sin6_addr, buf, sizeof buf);
    }
    return [NSString stringWithUTF8String:buf];
}

static void RTWriteAll(int fd, NSData *data)
{
    // scrittura bloccante (con il limite SO_SNDTIMEO): la presa accettata eredita O_NONBLOCK
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);
    struct timeval tv = { .tv_sec = 5, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    const uint8_t *p = data.bytes;
    size_t left = data.length;
    while (left > 0) {
        ssize_t n = write(fd, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        p += n;
        left -= (size_t)n;
    }
}

- (void)acceptConnections
{
    while (YES) {
        struct sockaddr_storage peer;
        socklen_t len = sizeof peer;
        int fd = accept(self.listenSocket, (struct sockaddr *)&peer, &len);
        if (fd < 0) return;   // EWOULDBLOCK: nessun'altra connessione in attesa
        int yes = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
        NSString *address = RTPeerAddress(&peer);
        if (![RTRemote isLocalAddressString:address]) {
            NSLog(@"RadioTray: telecomando, rifiutata una connessione da %@ (non è la rete di casa)", address);
            RTWriteAll(fd, [RTRemote responseWithStatus:403 type:@"text/plain; charset=utf-8"
                                                   body:[@"Solo dalla rete di casa." dataUsingEncoding:NSUTF8StringEncoding]]);
            close(fd);
            continue;
        }
        [self readFrom:fd];
    }
}

/// Legge la richiesta (al massimo 10 secondi), poi la passa al delegato e scrive la risposta.
- (void)readFrom:(int)fd
{
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);   // lettura senza bloccare la coda

    NSMutableData *buffer = [NSMutableData data];
    dispatch_queue_t queue = self.queue;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, self.queue);
    __block BOOL finished = NO;
    __weak typeof(self) weakSelf = self;
    void (^finish)(void) = ^{
        if (finished) return;
        finished = YES;
        dispatch_source_cancel(source);
    };
    // la presa si chiude solo dopo aver risposto (o se non si risponde affatto)
    __block BOOL replying = NO;
    dispatch_source_set_cancel_handler(source, ^{ if (!replying) close(fd); });
    dispatch_source_set_event_handler(source, ^{
        uint8_t chunk[4096];
        ssize_t n = read(fd, chunk, sizeof chunk);
        if (n <= 0) {
            if (n < 0 && (errno == EAGAIN || errno == EINTR)) return;
            finish();
            return;
        }
        [buffer appendBytes:chunk length:(NSUInteger)n];
        BOOL invalid = NO;
        RTRemoteRequest *request = [RTRemoteRequest requestFromData:buffer invalid:&invalid];
        if (invalid) {
            RTWriteAll(fd, [RTRemote responseWithStatus:400 type:nil body:nil]);
            finish();
            return;
        }
        if (!request) return;   // ne servono altri
        replying = YES;
        finish();
        dispatch_async(dispatch_get_main_queue(), ^{
            RTRemoteServer *strongSelf = weakSelf;
            __block BOOL answered = NO;
            void (^reply)(NSData *) = ^(NSData *response) {
                if (answered) return;
                answered = YES;
                BOOL head = [request.method isEqualToString:@"HEAD"];
                dispatch_async(queue, ^{
                    NSData *out = response;
                    if (head) {   // solo le intestazioni
                        NSRange end = [response rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4] options:0
                                                      range:NSMakeRange(0, response.length)];
                        if (end.location != NSNotFound) out = [response subdataWithRange:NSMakeRange(0, NSMaxRange(end))];
                    }
                    RTWriteAll(fd, out);
                    close(fd);
                });
            };
            if (strongSelf.delegate) [strongSelf.delegate remoteServer:strongSelf handleRequest:request reply:reply];
            else reply([RTRemote responseWithStatus:404 type:nil body:nil]);
        });
    });
    dispatch_resume(source);
    // limite di tempo per ricevere la richiesta
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RTRemoteReadTimeout * NSEC_PER_SEC)), self.queue, ^{ finish(); });
}

@end
