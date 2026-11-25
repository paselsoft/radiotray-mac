#import "RTRemoteController.h"
#import "RTRemote.h"
#import "RTRemoteServer.h"
#import <CoreImage/CoreImage.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>

@interface RTRemoteController () <RTRemoteServerDelegate>
@property (nonatomic, strong) RTRemoteServer *server;
@property (nonatomic, strong, nullable) NSData *page;
@property (nonatomic, strong, nullable) NSData *icon;
@end

@implementation RTRemoteController

- (instancetype)init
{
    if ((self = [super init])) {
        _server = [RTRemoteServer new];
        _server.delegate = self;
        _token = @"";
    }
    return self;
}

- (BOOL)running
{
    return self.server.running;
}

- (NSString *)start
{
    return [self.server startOnPort:RTRemotePort];
}

- (void)stop
{
    [self.server stop];
}

#pragma mark - Indirizzi

- (NSString *)address
{
    // nome Bonjour del Mac ("iMac-di-Paolo" → iMac-di-Paolo.local)
    NSString *host = nil;
    CFStringRef local = SCDynamicStoreCopyLocalHostName(NULL);
    if (local) {
        host = [(__bridge NSString *)local stringByAppendingString:@".local"];
        CFRelease(local);
    }
    if (host.length == 0) return [self ipAddress] ?: [RTRemote addressForHost:@"localhost" token:self.token];
    return [RTRemote addressForHost:host token:self.token];
}

- (NSString *)ipAddress
{
    // il primo IPv4 della rete di casa su un'interfaccia attiva (Wi-Fi o Ethernet)
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return nil;
    NSString *found = nil;
    for (struct ifaddrs *i = list; i && !found; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET) continue;
        if (!(i->ifa_flags & IFF_UP) || (i->ifa_flags & IFF_LOOPBACK)) continue;
        if (strncmp(i->ifa_name, "en", 2) != 0) continue;
        char buf[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &((struct sockaddr_in *)i->ifa_addr)->sin_addr, buf, sizeof buf);
        NSString *ip = [NSString stringWithUTF8String:buf];
        if ([RTRemote isLocalAddressString:ip] && ![ip hasPrefix:@"169.254."]) found = ip;
    }
    freeifaddrs(list);
    return found ? [RTRemote addressForHost:found token:self.token] : nil;
}

- (NSImage *)QRCodeForString:(NSString *)text side:(CGFloat)side
{
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    if (!filter) return nil;
    [filter setValue:[text dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *qr = filter.outputImage;
    if (!qr) return nil;
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cg = [context createCGImage:qr fromRect:qr.extent];
    if (!cg) return nil;
    NSImage *small = [[NSImage alloc] initWithCGImage:cg size:NSMakeSize(qr.extent.size.width, qr.extent.size.height)];
    CGImageRelease(cg);
    // ingrandito senza sfumature (punti netti, leggibili dalla fotocamera), con un bordo bianco
    NSImage *out = [[NSImage alloc] initWithSize:NSMakeSize(side, side)];
    [out lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0, 0, side, side));
    [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationNone;
    CGFloat margin = side * 0.06;
    [small drawInRect:NSMakeRect(margin, margin, side - 2 * margin, side - 2 * margin)
             fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [out unlockFocus];
    return out;
}

#pragma mark - Immagini

/// JPEG (o PNG) dell'immagine, ridotta al lato massimo indicato.
static NSData *RTImageData(NSImage *image, CGFloat maxSide, BOOL png)
{
    if (!image || image.size.width <= 0 || image.size.height <= 0) return nil;
    CGFloat scale = MIN(1.0, maxSide / MAX(image.size.width, image.size.height));
    // si disegna in pixel: le immagini Retina hanno size in punti
    NSInteger w = MAX(1, (NSInteger)round(image.size.width * scale * 2)), h = MAX(1, (NSInteger)round(image.size.height * scale * 2));
    if (MAX(w, h) > maxSide) {
        CGFloat f = maxSide / MAX(w, h);
        w = MAX(1, (NSInteger)round(w * f));
        h = MAX(1, (NSInteger)round(h * f));
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8
                                                               samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    if (!rep) return nil;
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext setCurrentContext:ctx];
    ctx.imageInterpolation = NSImageInterpolationHigh;
    if (!png) {
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, w, h));
    }
    [image drawInRect:NSMakeRect(0, 0, w, h) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    return png ? [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
               : [rep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{ NSImageCompressionFactor: @0.82 }];
}

- (NSData *)iconData
{
    if (!self.icon) {
        NSImage *app = [NSImage imageNamed:NSImageNameApplicationIcon];
        self.icon = RTImageData(app, 180, YES);
    }
    return self.icon;
}

- (NSData *)pageData
{
    if (!self.page) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"telecomando" ofType:@"html"];
        self.page = path ? [NSData dataWithContentsOfFile:path] : nil;
    }
    return self.page;
}

#pragma mark - RTRemoteServerDelegate

- (void)remoteServer:(RTRemoteServer *)server handleRequest:(RTRemoteRequest *)request reply:(void (^)(NSData *))reply
{
    id<RTRemoteDataSource> source = self.dataSource;
    RTRemoteRoute route = [RTRemote routeForRequest:request token:self.token];
    NSData *notFound = [RTRemote responseWithStatus:404 type:@"text/plain; charset=utf-8"
                                               body:[@"Non trovato. Apri l'indirizzo con il codice che trovi nel menu di RadioTray."
                                                     dataUsingEncoding:NSUTF8StringEncoding]];
    switch (route) {
        case RTRemoteRouteNotFound:
            reply(notFound);
            return;
        case RTRemoteRouteForbidden:
            NSLog(@"RadioTray: telecomando, codice di sicurezza sbagliato");
            reply([RTRemote responseWithStatus:403 type:@"text/plain; charset=utf-8"
                                          body:[@"Codice di sicurezza sbagliato o cambiato: riapri l'indirizzo dal menu di RadioTray."
                                                dataUsingEncoding:NSUTF8StringEncoding]]);
            return;
        case RTRemoteRouteRedirect:
            reply([RTRemote redirectTo:[request.path stringByAppendingString:@"/"]]);
            return;
        case RTRemoteRoutePage: {
            NSData *page = [self pageData];
            reply(page ? [RTRemote responseWithStatus:200 type:@"text/html; charset=utf-8" body:page] : notFound);
            return;
        }
        case RTRemoteRouteIcon: {
            NSData *icon = [self iconData];
            reply(icon ? [RTRemote responseWithStatus:200 type:@"image/png" body:icon] : notFound);
            return;
        }
        case RTRemoteRouteState:
            reply([RTRemote JSONResponse:source ? [source remoteState] : @{}]);
            return;
        case RTRemoteRouteStations:
            reply([RTRemote JSONResponse:source ? [source remoteStations] : @{ @"groups": @[] }]);
            return;
        case RTRemoteRouteRecent:
            reply([RTRemote JSONResponse:source ? [source remoteRecent] : @{ @"tracks": @[] }]);
            return;
        case RTRemoteRouteCommand: {
            NSDictionary *command = [RTRemote commandFromRequest:request];
            if (!command) {
                reply([RTRemote responseWithStatus:400 type:nil body:nil]);
                return;
            }
            [source remoteCommand:command];
            // lo stato dopo il comando (un attimo dopo: accendere o cambiare stazione non è immediato)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                reply([RTRemote JSONResponse:source ? [source remoteState] : @{}]);
            });
            return;
        }
        case RTRemoteRouteCover: {
            NSData *data = RTImageData([source remoteCoverImage], 600, NO);
            reply(data ? [RTRemote responseWithStatus:200 type:@"image/jpeg" body:data] : notFound);
            return;
        }
        case RTRemoteRouteLogo: {
            NSString *g = request.query[@"group"], *s = request.query[@"station"];
            NSImage *logo = g.length && s.length ? [source remoteLogoForGroup:g station:s] : nil;
            NSData *data = RTImageData(logo, 96, YES);
            reply(data ? [RTRemote responseWithStatus:200 type:@"image/png" body:data] : notFound);
            return;
        }
    }
    reply(notFound);
}

@end
