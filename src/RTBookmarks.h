// Preferiti nel formato di Radiotray-NG (bookmarks.json):
// [ { "group": "Nome", "image": "...", "stations": [ { "name", "url", "image", "notifications", "direct", "mirrors" } ] } ]
// "mirrors" (estensione di RadioTray per Mac): altri server dello stesso stream, provati se il primo cade.
// Il gruppo "root" non diventa un sottomenu: le sue stazioni vanno direttamente nel menu.
// Solo Foundation: testabile senza interfaccia.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const RTRootGroupName;

@interface RTStation : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy, nullable) NSString *image;
@property (nonatomic) BOOL notifications;   // predefinito YES
@property (nonatomic) BOOL direct;          // predefinito NO: YES = non è una playlist
@property (nonatomic, copy) NSArray<NSString *> *mirrors;   // server di riserva (stream diretti), può essere vuoto
@end

@interface RTGroup : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *image;
@property (nonatomic, copy) NSArray<RTStation *> *stations;
@property (nonatomic, readonly) BOOL isRoot;
@end

@interface RTBookmarks : NSObject
@property (nonatomic, copy, readonly) NSArray<RTGroup *> *groups;

/// Legge il JSON. In caso di errore restituisce nil e un messaggio in italiano in *error.
+ (nullable instancetype)bookmarksWithData:(NSData *)data error:(NSString *_Nullable *_Nullable)error;
+ (nullable instancetype)bookmarksWithContentsOfFile:(NSString *)path error:(NSString *_Nullable *_Nullable)error;

- (nullable RTGroup *)groupNamed:(NSString *)name;
- (nullable RTStation *)stationNamed:(NSString *)name inGroup:(NSString *)group;
- (NSUInteger)stationCount;

/// Aggiunge una stazione al JSON dei preferiti e restituisce il nuovo contenuto del file.
/// Il gruppo viene creato in fondo se non esiste; le altre voci (anche i campi sconosciuti)
/// restano come sono. Errore (in italiano) se il JSON non è valido o il nome esiste già nel gruppo.
+ (nullable NSData *)dataByAddingStation:(NSString *)name url:(NSString *)url toGroup:(NSString *)group
                                  inData:(NSData *)data error:(NSString *_Nullable *_Nullable)error;

/// Aggiunge al JSON dei preferiti le stazioni di extra che non ci sono già (stesso indirizzo in
/// qualsiasi gruppo, o stesso nome nello stesso gruppo). In *added il numero di stazioni aggiunte.
+ (nullable NSData *)dataByMergingStations:(RTBookmarks *)extra intoData:(NSData *)data
                                     added:(NSUInteger *_Nullable)added error:(NSString *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
