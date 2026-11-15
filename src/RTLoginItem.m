#import "RTLoginItem.h"

static NSString *const RTAgentLabel = @"io.github.paselsoft.radiotray-mac";

@implementation RTLoginItem

+ (NSString *)agentPath
{
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
    return [dir stringByAppendingPathComponent:[RTAgentLabel stringByAppendingString:@".plist"]];
}

+ (BOOL)isEnabled
{
    return [[NSFileManager defaultManager] fileExistsAtPath:[self agentPath]];
}

+ (NSDictionary *)agentPlistForAppPath:(NSString *)appPath
{
    // "open" fa partire l'app come un doppio clic (notifiche, tasti multimediali, una sola copia)
    return @{
        @"Label": RTAgentLabel,
        @"ProgramArguments": @[@"/usr/bin/open", @"-g", appPath],
        @"RunAtLoad": @YES,
        @"LimitLoadToSessionType": @"Aqua",
    };
}

/// L'app gira dal .dmg o da una copia temporanea di Gatekeeper ("App Translocation"):
/// quel percorso sparisce, non va scritto nel LaunchAgent.
+ (BOOL)isTemporaryPath:(NSString *)appPath
{
    return [appPath hasPrefix:@"/Volumes/"] || [appPath rangeOfString:@"/AppTranslocation/"].location != NSNotFound;
}

+ (NSString *)setEnabled:(BOOL)enabled appPath:(NSString *)appPath
{
    NSString *path = [self agentPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!enabled) {
        NSError *error = nil;
        if ([fm fileExistsAtPath:path] && ![fm removeItemAtPath:path error:&error]) {
            return error.localizedDescription ?: @"Impossibile togliere l'avvio automatico";
        }
        return nil;
    }
    if ([self isTemporaryPath:appPath]) {
        return @"RadioTray sta funzionando dal disco scaricato o da una copia temporanea. "
               @"Trascinalo nella cartella Applicazioni, aprilo da lì e riprova.";
    }
    NSError *error = nil;
    if (![fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                        attributes:nil error:&error]) {
        return error.localizedDescription;
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:[self agentPlistForAppPath:appPath]
                                                              format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        return error.localizedDescription ?: @"Impossibile attivare l'avvio automatico";
    }
    return nil;
}

+ (void)refreshAppPath:(NSString *)appPath
{
    if (![self isEnabled] || [self isTemporaryPath:appPath]) return;
    NSDictionary *current = [NSDictionary dictionaryWithContentsOfFile:[self agentPath]];
    NSArray *args = current[@"ProgramArguments"];
    if ([args isKindOfClass:[NSArray class]] && [args.lastObject isEqual:appPath]) return;
    [self setEnabled:YES appPath:appPath];
}

@end
