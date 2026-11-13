#import <Foundation/Foundation.h>
#import "PowerSourceReader.h"
int main(void) { @autoreleasepool {
    NSString *error = nil;
    NSArray *rows = BTReadAccessoryPowerSources(&error);
    if (error) { fprintf(stderr, "%s\n", error.UTF8String); return 1; }
    printf("Bluetooth accessory power sources: %lu\n", (unsigned long)rows.count);
    for (NSDictionary *row in rows) printf("%s: %s%%; connection=%s\n", [row[@"name"] UTF8String], [[row[@"battery"] description] UTF8String] ?: "unknown", row[@"connected"] ? ([row[@"connected"] boolValue] ? "connected" : "disconnected") : "not reported");
} return 0; }
