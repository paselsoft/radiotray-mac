// Titolo e artista del brano a partire dal metadato ICY "StreamTitle"
// (come Radiotray-NG: divisione al primo " - ", estrazione di text="..." di iHeartRadio).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTTrackInfo : NSObject
@property (nonatomic, copy, readonly) NSString *title;    // vuoto se non c'è
@property (nonatomic, copy, readonly) NSString *artist;   // vuoto se non c'è

+ (instancetype)infoWithStreamTitle:(nullable NSString *)streamTitle split:(BOOL)split;
+ (instancetype)infoWithTitle:(nullable NSString *)title artist:(nullable NSString *)artist;
- (BOOL)isEmpty;
- (BOOL)isEqualToInfo:(nullable RTTrackInfo *)other;
/// "Titolo\nArtista" (o solo il titolo): per gli appunti.
- (NSString *)clipboardText;
@end

/// Accorcia un testo a max caratteri aggiungendo "…".
NSString *RTTruncate(NSString *text, NSUInteger max);

NS_ASSUME_NONNULL_END
