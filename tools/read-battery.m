#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
@interface NSObject (BatteryInspection)
- (NSArray *)connectedDevices;
- (void)addBatteryDeviceObserver:(id)observer queue:(dispatch_queue_t)queue;
@end
@interface BatteryObserver : NSObject
@end
@implementation BatteryObserver
- (void)connectedDevicesDidChange:(id)devices { NSLog(@"Connected devices callback: %@", devices); }
- (BOOL)respondsToSelector:(SEL)selector {
    NSLog(@"Observer selector: %@", NSStringFromSelector(selector));
    return [super respondsToSelector:selector];
}
@end
int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/BatteryCenter.framework/BatteryCenter", RTLD_NOW)) return 1;
        id controller = [[NSClassFromString(@"BCBatteryDeviceController") alloc] init];
        BatteryObserver *observer = [BatteryObserver new];
        [controller addBatteryDeviceObserver:observer queue:dispatch_get_main_queue()];
        NSDate *end = [NSDate dateWithTimeIntervalSinceNow:5];
        while ([end timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        NSArray *devices = [controller connectedDevices];
        printf("BatteryCenter returned %lu device(s)\n", (unsigned long)devices.count);
        for (id device in devices) {
            NSLog(@"%@", device);
        }
    }
}
