// Brani preferiti: titolo, artista, stazione e data, salvati in brani-preferiti.json.
// Ricerca, filtro per stazione, ordinamento ed esportazione CSV. Solo Foundation: testabile.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTFavoriteTrack : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *station;
@property (nonatomic, strong) NSDate *added;
/// "Titolo – Artista" (o solo il titolo)
@property (nonatomic, readonly) NSString *displayText;
/// Testo per una ricerca sul web: "Artista Titolo"
@property (nonatomic, readonly) NSString *searchText;
@end

typedef NS_ENUM(NSInteger, RTTrackSearchSite) {
    RTTrackSearchYouTube,
    RTTrackSearchAppleMusic,
    RTTrackSearchSpotify,
    RTTrackSearchYouTubeMusic,
};

@interface RTFavoriteTracks : NSObject
@property (nonatomic, copy, readonly) NSArray<RTFavoriteTrack *> *tracks;   // in ordine di aggiunta

/// Legge il file (se manca o è vuoto: elenco vuoto). Errore solo se il file esiste ed è illeggibile.
+ (nullable instancetype)tracksWithContentsOfFile:(NSString *)path error:(NSString *_Nullable *_Nullable)error;
+ (nullable instancetype)tracksWithData:(nullable NSData *)data error:(NSString *_Nullable *_Nullable)error;
- (NSData *)dataRepresentation;

- (nullable RTFavoriteTrack *)trackWithTitle:(NSString *)title artist:(NSString *)artist;
/// Aggiunge il brano; se c'è già (stesso titolo e artista, maiuscole ignorate) restituisce quello esistente
/// e *alreadyPresent = YES.
- (RTFavoriteTrack *)addTitle:(NSString *)title artist:(NSString *)artist station:(NSString *)station
                         date:(NSDate *)date alreadyPresent:(BOOL *_Nullable)alreadyPresent;
- (void)removeTracks:(NSArray<RTFavoriteTrack *> *)tracks;
- (void)removeAllTracks;

/// Per la cronologia: il brano va in fondo (se c'era già viene spostato, con stazione e ora nuove)
/// e si tengono solo gli ultimi limit. Restituisce NO se era già l'ultimo (niente da salvare).
- (BOOL)recordTitle:(NSString *)title artist:(NSString *)artist station:(NSString *)station
               date:(NSDate *)date limit:(NSUInteger)limit;

/// Stazioni presenti, in ordine alfabetico.
- (NSArray<NSString *> *)stations;
/// Brani che contengono query (in titolo, artista o stazione; maiuscole e accenti ignorati),
/// della stazione indicata (nil = tutte), ordinati secondo i descrittori (titolo, artist, station, added).
- (NSArray<RTFavoriteTrack *> *)tracksMatching:(nullable NSString *)query station:(nullable NSString *)station
                               sortDescriptors:(NSArray<NSSortDescriptor *> *)sort;

/// CSV per Numbers/Excel (separatore ";", UTF-8 con BOM).
+ (NSData *)csvForTracks:(NSArray<RTFavoriteTrack *> *)tracks;
+ (NSURL *)searchURLForTrack:(RTFavoriteTrack *)track site:(RTTrackSearchSite)site;
@end

NS_ASSUME_NONNULL_END
