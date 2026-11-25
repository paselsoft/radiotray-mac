// Telecomando dal telefono: avvia il server, serve la pagina, le immagini e i JSON, prepara indirizzo e codice QR.
// Lo stato e i comandi li fornisce l'app (RTRemoteDataSource).
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RTRemoteDataSource <NSObject>
/// Brano, stazione, volume… (JSON per la pagina).
- (NSDictionary *)remoteState;
- (NSDictionary *)remoteStations;
- (NSDictionary *)remoteRecent;
/// Comando già controllato (RTRemote commandFromRequest:).
- (void)remoteCommand:(NSDictionary<NSString *, NSString *> *)command;
- (nullable NSImage *)remoteCoverImage;
- (nullable NSImage *)remoteLogoForGroup:(NSString *)group station:(NSString *)station;
@end

@interface RTRemoteController : NSObject
@property (nonatomic, weak, nullable) id<RTRemoteDataSource> dataSource;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, copy) NSString *token;

/// nil se è partito, altrimenti il problema (per esempio la porta già usata).
- (nullable NSString *)start;
- (void)stop;

/// http://nome-del-mac.local:8765/t/<codice>/
- (NSString *)address;
/// Lo stesso con l'indirizzo IP del Mac (se il telefono non trova il nome .local), o nil.
- (nullable NSString *)ipAddress;
/// Codice QR dell'indirizzo, nitido, del lato indicato (punti).
- (nullable NSImage *)QRCodeForString:(NSString *)text side:(CGFloat)side;
@end

NS_ASSUME_NONNULL_END
