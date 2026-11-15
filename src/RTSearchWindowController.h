// Finestra "Cerca stazioni": ricerca nell'archivio Radio Browser, ascolto di prova e aggiunta ai preferiti.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RTSearchWindowDelegate <NSObject>
- (void)searchWindowPlayStation:(NSString *)name url:(NSString *)url;
- (void)searchWindowAddStation:(NSString *)name url:(NSString *)url;
@end

@interface RTSearchWindowController : NSWindowController
@property (nonatomic, weak, nullable) id<RTSearchWindowDelegate> delegate;
- (void)showAndFocus;
@end

NS_ASSUME_NONNULL_END
