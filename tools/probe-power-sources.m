#import <Foundation/Foundation.h>
#import <IOKit/ps/IOPowerSources.h>
#import <objc/message.h>
#import <dlfcn.h>
static id obj(id target, const char *name) { return ((id(*)(id,SEL))objc_msgSend)(target,sel_registerName(name)); }
static void showDevices(id controller, NSString *label) {
    NSArray *devices = obj(controller, "connectedDevices");
    NSLog(@"%@: %lu devices", label, (unsigned long)devices.count);
    for (id device in devices) {
        for (NSString *key in @[@"name", @"identifier", @"percentCharge", @"isConnected", @"isCharging", @"transportType"])
            if ([device respondsToSelector:NSSelectorFromString(key)]) NSLog(@"  %@ = %@", key, [device valueForKey:key]);
    }
}
@interface Observer : NSObject
@end
@implementation Observer
- (void)connectedDevicesDidChange:(id)devices { NSLog(@"observer callback: %@", devices); }
@end
int main(void) { @autoreleasepool {
    dlopen("/System/Library/PrivateFrameworks/BatteryCenter.framework/BatteryCenter", RTLD_NOW);
    id controller = obj(NSClassFromString(@"BCBatteryDeviceController"), "_sharedPowerSourceController");
    NSLog(@"shared controller class: %@", NSStringFromClass([controller class]));
    Observer *observer = [Observer new];
    ((void(*)(id,SEL,id,id))objc_msgSend)(controller,sel_registerName("addBatteryDeviceObserver:queue:"),observer,dispatch_get_main_queue());
    obj(controller, "_beginPowerSourceObservingIfNecessary");
    obj(controller, "_queryConnectedDevices");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
    showDevices(controller, @"BC shared controller");
    CFTypeRef (*copyWithType)(int) = dlsym(RTLD_DEFAULT, "IOPSCopyPowerSourcesByType");
    NSLog(@"IOPSCopyPowerSourcesByType: %@", copyWithType ? @"available" : @"unavailable");
    for (NSNumber *kind in @[@(-1), @0, @1, @2, @3, @4]) {
        CFTypeRef blob = kind.intValue == -1 ? IOPSCopyPowerSourcesInfo() : (copyWithType ? copyWithType(kind.intValue) : NULL);
        if (!blob) { NSLog(@"IOPS type %@ blob NULL", kind); continue; }
        CFArrayRef sources = IOPSCopyPowerSourcesList(blob);
        NSLog(@"IOPS type %@: %ld sources", kind, sources ? CFArrayGetCount(sources) : 0L);
        for (CFIndex i=0; sources && i<CFArrayGetCount(sources); i++) {
            CFDictionaryRef desc = IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(sources,i));
            NSDictionary *d = (__bridge NSDictionary*)desc;
            NSMutableDictionary *selected = [NSMutableDictionary dictionary];
            for (NSString *key in @[@"Name", @"Type", @"Transport Type", @"Current Capacity", @"Max Capacity", @"Is Present", @"Is Charging", @"Power Source State", @"Accessory Category", @"Part Name", @"Part Type"])
                if (d[key]) selected[key] = d[key];
            NSLog(@"  %@", selected);
            NSLog(@"  keys: %@", [[d allKeys] sortedArrayUsingSelector:@selector(compare:)]);
            if (d[@"Power Source ID"]) NSLog(@"  Power Source ID: %@", d[@"Power Source ID"]);
            if (d[@"Accessory Identifier"]) NSLog(@"  Accessory Identifier: %@", d[@"Accessory Identifier"]);
            NSLog(@"  considers: %d", ((BOOL(*)(id,SEL,id))objc_msgSend)(controller,sel_registerName("_shouldConsiderDeviceWithPowerSourceDescription:"),d));
        }
        if (sources) {
            id ordered = ((id(*)(id,SEL,CFTypeRef,CFArrayRef))objc_msgSend)(controller,sel_registerName("_orderedDevicesFromPowerSourcesBlob:powerSourcesList:"),blob,sources);
            NSLog(@"  BC ordered count: %lu", (unsigned long)[ordered count]);
            CFRelease(sources);
        }
        CFRelease(blob);
    }
} return 0; }
