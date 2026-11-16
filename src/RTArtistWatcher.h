// "Avvisami quando passa…": controlla a giro, in sottofondo, i titoli delle stazioni preferite e
// avvisa quando passa un artista (o un brano) della lista. Una stazione alla volta: si legge solo
// l'inizio dello stream (pochi secondi) per avere il titolo, poi si chiude.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class RTArtistWatcher;

@protocol RTArtistWatcherDelegate <NSObject>
/// Stazioni da controllare: [[gruppo, nome, indirizzo], …], esclusa quella in ascolto.
- (NSArray<NSArray<NSString *> *> *)stationsToWatch:(RTArtistWatcher *)watcher;
/// Trovato: artista cercato, titolo letto dalla radio, stazione.
- (void)artistWatcher:(RTArtistWatcher *)watcher found:(NSString *)artist title:(NSString *)title
              station:(NSArray<NSString *> *)station;
@end

@interface RTArtistWatcher : NSObject
@property (nonatomic, weak, nullable) id<RTArtistWatcherDelegate> delegate;
@property (nonatomic, copy) NSArray<NSString *> *artists;
- (void)start;
- (void)stop;
@property (nonatomic, readonly) BOOL running;

/// L'artista (della lista) che compare nel titolo come parola intera, senza badare a maiuscole
/// e accenti; nil se nessuno (testabile).
+ (nullable NSString *)artistIn:(NSString *)title matching:(NSArray<NSString *> *)artists;
@end

NS_ASSUME_NONNULL_END
