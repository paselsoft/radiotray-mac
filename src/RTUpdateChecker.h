// Controlla su GitHub se è uscita una versione più recente (al massimo una volta al giorno).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RTUpdateCompletion)(NSString *_Nullable newVersion, NSURL *_Nullable pageURL, NSString *_Nullable error);

@interface RTUpdateChecker : NSObject
/// Chiede l'ultima versione pubblicata; completamento sulla coda principale.
/// newVersion è nil se quella in uso è già la più recente.
+ (void)checkWithCurrentVersion:(NSString *)current completion:(RTUpdateCompletion)completion;

/// "1.10.0" è più recente di "1.9.2"; il prefisso "v" è ignorato (testabile).
+ (BOOL)version:(NSString *)candidate isNewerThan:(NSString *)current;
/// tag_name e html_url dalla risposta JSON di GitHub (testabile).
+ (nullable NSDictionary<NSString *, NSString *> *)releaseFromJSON:(NSData *)data;
@end

NS_ASSUME_NONNULL_END
