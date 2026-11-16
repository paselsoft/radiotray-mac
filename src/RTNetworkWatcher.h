// Si accorge quando cambia la rete (Wi-Fi che cade e torna, rete diversa, cavo collegato):
// guarda la rete principale del Mac in SystemConfiguration.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class RTNetworkWatcher;

@protocol RTNetworkWatcherDelegate <NSObject>
/// La rete è tornata o è cambiata (sulla coda principale). Non viene chiamato quando la rete sparisce.
- (void)networkWatcherDidChangeNetwork:(RTNetworkWatcher *)watcher;
@end

@interface RTNetworkWatcher : NSObject
@property (nonatomic, weak, nullable) id<RTNetworkWatcherDelegate> delegate;
- (void)start;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
