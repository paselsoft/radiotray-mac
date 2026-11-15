#import "RTFileWatcher.h"
#include <fcntl.h>
#include <unistd.h>

@implementation RTFileWatcher {
    NSString *_path;
    void (^_handler)(void);
    dispatch_source_t _source;
    NSData *_lastContents;
    BOOL _pending;
    BOOL _running;
}

- (instancetype)initWithPath:(NSString *)path changeHandler:(void (^)(void))handler
{
    if ((self = [super init])) {
        _path = [path copy];
        _handler = [handler copy];
    }
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (void)rememberCurrentContents
{
    _lastContents = [NSData dataWithContentsOfFile:_path];
}

- (void)start
{
    _running = YES;
    if (!_lastContents) [self rememberCurrentContents];
    [self arm];
}

- (void)stop
{
    _running = NO;
    [self disarm];
}

- (void)disarm
{
    if (_source) {
        dispatch_source_cancel(_source);
        _source = nil;
    }
}

- (void)arm
{
    [self disarm];
    if (!_running) return;
    int fd = open(_path.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) {
        // il file non c'è (in questo momento): si riprova tra poco
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf arm];
        });
        return;
    }
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME |
        DISPATCH_VNODE_ATTRIB, dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        unsigned long flags = dispatch_source_get_data(source);
        BOOL replaced = (flags & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME)) != 0;
        [strongSelf fileChangedReplaced:replaced];
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
    });
    _source = source;
    dispatch_resume(source);
}

- (void)fileChangedReplaced:(BOOL)replaced
{
    // il salvataggio "sicuro" sostituisce il file: si osserva il nuovo
    if (replaced) {
        [self disarm];
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf arm];
        });
    }
    if (_pending) return;
    _pending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_pending = NO;
        if (!strongSelf->_running) return;
        NSData *contents = [NSData dataWithContentsOfFile:strongSelf->_path];
        if (!contents || [contents isEqualToData:strongSelf->_lastContents ?: [NSData data]]) return;
        strongSelf->_lastContents = contents;
        strongSelf->_handler();
    });
}

@end
