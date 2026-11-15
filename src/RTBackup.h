// Backup in un solo file JSON: stazioni, brani preferiti, ascoltati di recente e impostazioni.
// Copia automatica giornaliera in iCloud Drive (cartella "RadioTray"), se iCloud Drive è attivo.
// Solo Foundation: testabile.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTBackupContents : NSObject
@property (nonatomic, strong, nullable) NSData *bookmarks;   // contenuto di bookmarks.json
@property (nonatomic, strong, nullable) NSData *favorites;   // brani-preferiti.json
@property (nonatomic, strong, nullable) NSData *history;     // ascoltati-di-recente.json
@property (nonatomic, copy) NSDictionary<NSString *, id> *settings;
@property (nonatomic, copy, nullable) NSString *appVersion;
@property (nonatomic, strong, nullable) NSDate *created;
@end

@interface RTBackup : NSObject
/// File di backup (JSON leggibile).
+ (NSData *)dataForContents:(RTBackupContents *)contents;
/// Legge un file di backup; errore in italiano se non è un backup di RadioTray valido.
+ (nullable RTBackupContents *)contentsFromData:(NSData *)data error:(NSString *_Nullable *_Nullable)error;

/// Impostazioni da salvare: solo valori JSON (testo, numeri, sì/no, elenchi, dizionari),
/// senza dati di sistema (posizioni delle finestre, data dell'ultimo controllo).
+ (NSDictionary<NSString *, id> *)exportableSettings:(NSDictionary<NSString *, id> *)defaults;

/// ~/Library/Mobile Documents/com~apple~CloudDocs/RadioTray, o nil se iCloud Drive non è attivo.
+ (nullable NSString *)iCloudFolder;
/// Scrive "RadioTray-backup.json" e una copia datata (si tengono le ultime keep) in folder.
+ (nullable NSString *)writeBackup:(NSData *)data toFolder:(NSString *)folder keep:(NSUInteger)keep date:(NSDate *)date;
@end

NS_ASSUME_NONNULL_END
