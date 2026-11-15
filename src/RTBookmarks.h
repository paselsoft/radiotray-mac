// Preferiti nel formato di Radiotray-NG (bookmarks.json):
// [ { "group": "Nome", "image": "...", "stations": [ { "name", "url", "image", "notifications", "direct" } ] } ]
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
@end

NS_ASSUME_NONNULL_END
