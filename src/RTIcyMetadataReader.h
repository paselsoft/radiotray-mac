// Legge il titolo del brano direttamente dallo stream, con una seconda connessione che chiede
// i metadati ICY e scarta l'audio. Serve perché su macOS 10.13 AVPlayer non li consegna.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class RTIcyMetadataReader;

@protocol RTIcyMetadataReaderDelegate <NSObject>
/// Chiamato sul thread principale solo quando il titolo cambia.
- (void)metadataReader:(RTIcyMetadataReader *)reader didReadStreamTitle:(NSString *)title;
@optional
/// Nome della stazione dichiarato dal server (intestazione icy-name), se c'è.
- (void)metadataReader:(RTIcyMetadataReader *)reader didReadStationName:(NSString *)name;
/// Bitrate (kbps, 0 se non dichiarato) e Content-Type dello stream, letti dalle intestazioni.
- (void)metadataReader:(RTIcyMetadataReader *)reader didReadBitrate:(NSInteger)kbps contentType:(nullable NSString *)contentType;
@end

@interface RTIcyMetadataReader : NSObject
@property (nonatomic, weak, nullable) id<RTIcyMetadataReaderDelegate> delegate;
/// YES dopo che il server ha dichiarato di non inviare metadati: inutile riprovare.
@property (nonatomic, readonly) BOOL unsupported;

- (void)startWithURL:(NSString *)url;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
