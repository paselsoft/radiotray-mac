#import <Cocoa/Cocoa.h>
#import "RTAppDelegate.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        static RTAppDelegate *delegate;   // NSApp.delegate è un riferimento debole
        delegate = [RTAppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
