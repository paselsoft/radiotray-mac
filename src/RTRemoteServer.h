// Server HTTP minimo per il telecomando: socket BSD e GCD, solo la rete di casa, una richiesta per connessione.
#import <Foundation/Foundation.h>
#import "RTRemote.h"

NS_ASSUME_NONNULL_BEGIN

@class RTRemoteServer;

@protocol RTRemoteServerDelegate <NSObject>
/// Sulla coda principale. reply: la risposta completa (RTRemote responseWithStatus…), da chiamare una volta.
- (void)remoteServer:(RTRemoteServer *)server handleRequest:(RTRemoteRequest *)request reply:(void (^)(NSData *response))reply;
@end

@interface RTRemoteServer : NSObject
@property (nonatomic, weak, nullable) id<RTRemoteServerDelegate> delegate;
@property (nonatomic, readonly) BOOL running;
/// Comincia ad ascoltare sulla porta; nil se va bene, altrimenti il problema in italiano.
- (nullable NSString *)startOnPort:(uint16_t)port;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
