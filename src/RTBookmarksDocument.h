// Il file delle stazioni in forma modificabile, per l'editor: gruppi e stazioni si possono
// aggiungere, rinominare, spostare ed eliminare. I campi che l'editor non mostra
// (image, notifications, direct, campi sconosciuti) restano come sono.
// Solo Foundation: testabile senza interfaccia.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class RTDocGroup;

@interface RTDocStation : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, weak, nullable) RTDocGroup *group;
@end

@interface RTDocGroup : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) NSMutableArray<RTDocStation *> *stations;
@property (nonatomic, readonly) BOOL isRoot;   // "root": stazioni senza gruppo
@end

@interface RTBookmarksDocument : NSObject
@property (nonatomic, readonly) NSMutableArray<RTDocGroup *> *groups;

+ (nullable instancetype)documentWithData:(NSData *)data error:(NSString *_Nullable *_Nullable)error;
/// JSON leggibile (rientri, chiavi in ordine, "/" senza barra rovesciata).
- (NSData *)dataRepresentation;

// Tutte le operazioni restituiscono nil se riuscite, altrimenti il motivo (in italiano).
- (nullable NSString *)addGroupNamed:(NSString *)name atIndex:(NSUInteger)index group:(RTDocGroup *_Nullable *_Nullable)created;
- (nullable NSString *)renameGroup:(RTDocGroup *)group to:(NSString *)name;
- (nullable NSString *)removeGroup:(RTDocGroup *)group;
- (nullable NSString *)moveGroup:(RTDocGroup *)group toIndex:(NSUInteger)index;

- (nullable NSString *)addStationNamed:(NSString *)name url:(NSString *)url toGroup:(RTDocGroup *)group
                               atIndex:(NSUInteger)index station:(RTDocStation *_Nullable *_Nullable)created;
- (nullable NSString *)renameStation:(RTDocStation *)station to:(NSString *)name;
- (nullable NSString *)setURL:(NSString *)url forStation:(RTDocStation *)station;
- (nullable NSString *)removeStation:(RTDocStation *)station;
/// Sposta la stazione nel gruppo indicato (anche lo stesso), alla posizione index.
- (nullable NSString *)moveStation:(RTDocStation *)station toGroup:(RTDocGroup *)group atIndex:(NSUInteger)index;

- (nullable RTDocGroup *)groupNamed:(NSString *)name;
/// Gruppo delle stazioni senza gruppo ("root"), creato in fondo se manca.
- (RTDocGroup *)rootGroup;
/// Nome da mostrare: "(senza gruppo)" per il gruppo root.
+ (NSString *)displayNameForGroup:(RTDocGroup *)group;
@end

NS_ASSUME_NONNULL_END
