// Telecomando dal telefono: la logica, senza rete né interfaccia (testabile).
// Codice di sicurezza, lettura delle richieste HTTP, scelta della risposta, JSON per la pagina,
// controllo che chi chiede sia sulla rete di casa.
#import <Foundation/Foundation.h>
#import "RTBookmarks.h"
#import "RTFavoriteTracks.h"

NS_ASSUME_NONNULL_BEGIN

/// Porta del telecomando.
extern const uint16_t RTRemotePort;

typedef NS_ENUM(NSInteger, RTRemoteRoute) {
    RTRemoteRouteNotFound,
    RTRemoteRouteForbidden,   // codice di sicurezza sbagliato
    RTRemoteRouteRedirect,    // "/t/<codice>" senza la barra finale
    RTRemoteRoutePage,        // la pagina
    RTRemoteRouteIcon,        // icona per la schermata Home
    RTRemoteRouteState,       // brano, stazione, volume (JSON)
    RTRemoteRouteStations,    // gruppi di stazioni (JSON)
    RTRemoteRouteRecent,      // ascoltati di recente (JSON)
    RTRemoteRouteCommand,     // comando (POST)
    RTRemoteRouteCover,       // copertina del brano (o logo della stazione)
    RTRemoteRouteLogo,        // logo di una stazione dell'elenco
};

/// Una richiesta HTTP letta dal telefono.
@interface RTRemoteRequest : NSObject
@property (nonatomic, copy, readonly) NSString *method;
@property (nonatomic, copy, readonly) NSString *path;                         // senza la query, già decodificato
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *query;
/// I dati ricevuti finora: nil se la richiesta non è ancora completa; *invalid = YES se non è HTTP valido
/// o è troppo grande (si chiude la connessione).
+ (nullable instancetype)requestFromData:(NSData *)data invalid:(BOOL *)invalid;
@end

@interface RTRemote : NSObject

/// Codice di sicurezza nuovo: 12 caratteri tra lettere minuscole e cifre (senza 0/o, 1/l).
+ (NSString *)generateToken;
/// Confronto a tempo costante (non si può indovinare il codice un carattere alla volta).
+ (BOOL)token:(nullable NSString *)given matches:(nullable NSString *)expected;
/// Vero per gli indirizzi della rete di casa: 10/8, 172.16/12, 192.168/16, 169.254/16, 127/8,
/// ::1, fe80::/10, fc00::/7 e gli IPv4 scritti come IPv6 (::ffff:a.b.c.d).
+ (BOOL)isLocalAddressString:(NSString *)address;

+ (RTRemoteRoute)routeForRequest:(RTRemoteRequest *)request token:(NSString *)token;
/// Indirizzo da aprire sul telefono: http://host:8765/t/<codice>/
+ (NSString *)addressForHost:(NSString *)host token:(NSString *)token;

/// Comando valido dalla query, oppure nil: @{ @"action": toggle|next|prev|favorite|volume|play|favorite-recent, … }.
/// volume → @"value" (0…100); play → @"group", @"station"; favorite-recent → @"title", @"artist", @"station".
+ (nullable NSDictionary<NSString *, NSString *> *)commandFromRequest:(RTRemoteRequest *)request;

/// Le stazioni per la pagina: "Più ascoltate" (se ce ne sono) e poi i gruppi, quelle senza gruppo in "Stazioni".
+ (NSDictionary *)stationsJSONForBookmarks:(RTBookmarks *)bookmarks mostPlayed:(NSArray<NSArray<NSString *> *> *)top
                              currentGroup:(nullable NSString *)group currentStation:(nullable NSString *)station;
/// Ascoltati di recente, dal più nuovo, con la ★ di quelli già nei preferiti.
+ (NSDictionary *)recentJSONForHistory:(RTFavoriteTracks *)history favorites:(RTFavoriteTracks *)favorites limit:(NSUInteger)limit;

/// Risposta HTTP completa (intestazioni e corpo).
+ (NSData *)responseWithStatus:(NSInteger)status type:(nullable NSString *)type body:(nullable NSData *)body;
+ (NSData *)JSONResponse:(id)object;
+ (NSData *)redirectTo:(NSString *)location;
@end

NS_ASSUME_NONNULL_END
