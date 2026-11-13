#import "PowerSourceReader.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <dlfcn.h>
#import <math.h>

// Private definitions verified against Apple's IOKitUser ps.subproj headers:
// IOPowerSourcesPrivate.h and IOPSKeysPrivate.h. Dynamic loading keeps the app
// able to report an unavailable API on macOS versions that remove the symbol.
typedef CFTypeRef (*BTCopyPowerSourcesByType)(int type);
static const int BTAccessorySourceType = 4; // kIOPSSourceForAccessories

static NSString *BTString(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : nil;
}

static NSNumber *BTNumber(id value) {
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

NSArray<NSDictionary<NSString *, id> *> *BTReadAccessoryPowerSources(NSString **errorMessage) {
    if (errorMessage) *errorMessage = nil;
    BTCopyPowerSourcesByType copySources = (BTCopyPowerSourcesByType)dlsym(RTLD_DEFAULT, "IOPSCopyPowerSourcesByType");
    if (!copySources) {
        if (errorMessage) *errorMessage = @"The accessory power-source API is unavailable on this macOS version.";
        return @[];
    }

    CFTypeRef blob = copySources(BTAccessorySourceType);
    if (!blob) {
        if (errorMessage) *errorMessage = @"macOS could not read accessory power sources.";
        return @[];
    }
    CFArrayRef sources = IOPSCopyPowerSourcesList(blob);
    if (!sources) {
        CFRelease(blob);
        if (errorMessage) *errorMessage = @"macOS could not enumerate accessory power sources.";
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
    for (CFIndex index = 0; index < CFArrayGetCount(sources); index++) {
        CFDictionaryRef description = IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(sources, index));
        if (!description) {
            if (errorMessage) *errorMessage = @"An accessory power-source description was unavailable.";
            continue;
        }
        NSDictionary *source = (__bridge NSDictionary *)description;
        NSString *transport = BTString(source[@kIOPSTransportTypeKey]);
        if (![transport isEqualToString:@"Bluetooth"] && ![transport isEqualToString:@"Bluetooth LE"]) continue;

        NSString *accessoryIdentifier = BTString(source[@"Accessory Identifier"]);
        NSString *partIdentifier = BTString(source[@"Part Identifier"]);
        NSString *partName = BTString(source[@"Part Name"]);
        NSNumber *sourceID = BTNumber(source[@kIOPSPowerSourceIDKey]);
        NSString *name = BTString(source[@kIOPSNameKey]) ?: @"Bluetooth accessory";
        if (partName) name = [NSString stringWithFormat:@"%@ · %@", name, partName];

        // Accessory Identifier may identify each part separately. Part Identifier
        // disambiguates left/right/case when an accessory shares its identifier.
        NSString *identifier;
        if (accessoryIdentifier) {
            identifier = partIdentifier
                ? [NSString stringWithFormat:@"iops:%@:%@", accessoryIdentifier, partIdentifier]
                : [@"iops:" stringByAppendingString:accessoryIdentifier];
        } else if (sourceID) {
            identifier = [NSString stringWithFormat:@"iops:source:%@", sourceID];
        } else {
            if (errorMessage) *errorMessage = @"An accessory power source did not report an identifier.";
            continue;
        }
        if ([identifiers containsObject:identifier]) {
            if (sourceID) identifier = [identifier stringByAppendingFormat:@":source:%@", sourceID];
            else {
                if (errorMessage) *errorMessage = @"Accessory power sources reported an ambiguous identifier.";
                continue;
            }
        }
        [identifiers addObject:identifier];

        NSNumber *present = BTNumber(source[@kIOPSIsPresentKey]);
        // Membership alone does not prove a live Bluetooth connection. Inventory
        // supplies the connection state when the power source omits Is Present.
        NSNumber *charging = BTNumber(source[@kIOPSIsChargingKey]);
        NSMutableDictionary *row = [@{
            @"id": identifier,
            @"name": name,
            @"charging": @(charging ? charging.boolValue : NO)
        } mutableCopy];
        if (present) row[@"connected"] = @(present.boolValue);
        if (accessoryIdentifier) row[@"accessoryIdentifier"] = accessoryIdentifier;

        NSNumber *current = BTNumber(source[@kIOPSCurrentCapacityKey]);
        NSNumber *maximum = BTNumber(source[@kIOPSMaxCapacityKey]);
        if (current && maximum) {
            double capacity = current.doubleValue;
            double maxCapacity = maximum.doubleValue;
            if (isfinite(capacity) && isfinite(maxCapacity) && maxCapacity > 0 && capacity >= 0 && capacity <= maxCapacity)
                row[@"battery"] = @((NSInteger)llround(100.0 * capacity / maxCapacity));
        }
        [rows addObject:row];
    }
    CFRelease(sources);
    CFRelease(blob);
    return rows;
}
