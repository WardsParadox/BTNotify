#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads the powerd accessory source list. An empty array with no error is valid.
/// `connected` is included only when the source explicitly reports Is Present.
/// Bluetooth inventory should supply connection state when that key is absent.
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, id> *> *BTReadAccessoryPowerSources(
    NSString * _Nullable * _Nullable errorMessage
);

NS_ASSUME_NONNULL_END
