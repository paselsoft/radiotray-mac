// Uscite audio del Mac (altoparlanti, cuffie, casse USB, AirPlay…) da CoreAudio.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTAudioOutput : NSObject
@property (nonatomic, copy) NSString *uid;    // identificativo stabile, da dare ad AVPlayer
@property (nonatomic, copy) NSString *name;   // "Altoparlanti interni", "AirPlay"…
@end

@interface RTAudioOutputs : NSObject
/// Dispositivi che hanno almeno un'uscita, nell'ordine di CoreAudio.
+ (NSArray<RTAudioOutput *> *)outputs;
/// Identificativo dell'uscita scelta in Preferenze di Sistema ▸ Suono.
+ (nullable NSString *)defaultOutputUID;
@end

NS_ASSUME_NONNULL_END
