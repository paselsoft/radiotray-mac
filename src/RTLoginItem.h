// Avvio automatico al login con un LaunchAgent dell'utente
// (~/Library/LaunchAgents/io.github.paselsoft.radiotray-mac.plist): funziona su 10.13 e successivi,
// non richiede un'app di supporto e si toglie semplicemente cancellando il file.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTLoginItem : NSObject
+ (NSString *)agentPath;
+ (BOOL)isEnabled;
/// Restituisce nil se riuscito, altrimenti il motivo.
+ (nullable NSString *)setEnabled:(BOOL)enabled appPath:(NSString *)appPath;
/// Se l'app è stata spostata, aggiorna il percorso nel LaunchAgent (da chiamare all'avvio).
+ (void)refreshAppPath:(NSString *)appPath;
/// Contenuto del LaunchAgent (testabile).
+ (NSDictionary *)agentPlistForAppPath:(NSString *)appPath;
@end

NS_ASSUME_NONNULL_END
