import XCTest
@testable import BTNotifyCore

final class AccessoryKindTests: XCTestCase {
    func testPeripheralFlagsAreIndependentOfSubtypeAndName() {
        XCTAssertEqual(AccessoryKind.identify(majorClass: 5, minorClass: 0x15, name: "Custom"), .keyboard)
        XCTAssertEqual(AccessoryKind.identify(majorClass: 5, minorClass: 0x20, name: "Custom"), .mouse)
        XCTAssertEqual(AccessoryKind.identify(majorClass: 5, minorClass: 0x30, name: "Custom"), .keyboard)
        XCTAssertEqual(AccessoryKind.identify(majorClass: 5, minorClass: 0x10, name: "AirPods"), .keyboard)
    }

    func testPointingDevicesAndControllersUseTheirOwnKinds() {
        XCTAssertEqual(AccessoryKind.identify(majorClass: 5, minorClass: 0x20, name: "Magic Trackpad"), .trackpad)
        XCTAssertEqual(AccessoryKind.identify(majorClass: 5, minorClass: 2, name: "Custom"), .gameController)
        XCTAssertEqual(AccessoryKind.identify(majorClass: 5, minorClass: 7, name: "Custom"), .stylus)
    }

    func testAudioClassAndProductVariants() {
        XCTAssertEqual(AccessoryKind.identify(majorClass: 4, minorClass: 1, name: "Custom"), .headset)
        XCTAssertEqual(AccessoryKind.identify(majorClass: 4, minorClass: 6, name: "Custom"), .headphones)
        XCTAssertEqual(AccessoryKind.identify(majorClass: 4, minorClass: 6, name: "AirPods Pro"), .airpodsPro)
        XCTAssertEqual(AccessoryKind.identify(majorClass: 4, minorClass: 6, name: "AirPods Max"), .airpodsMax)
        XCTAssertEqual(AccessoryKind.identify(majorClass: 4, minorClass: 9, name: "AirPods"), .unknown)
    }

    func testUnclassifiedBLEDevicesHaveConservativeDisplayFallbacks() {
        XCTAssertEqual(AccessoryKind.identify(name: "Magic Keyboard"), .keyboard)
        XCTAssertEqual(AccessoryKind.identify(name: "Magic Mouse"), .mouse)
        XCTAssertEqual(AccessoryKind.identify(name: "Magic Trackpad"), .trackpad)
        XCTAssertEqual(AccessoryKind.identify(name: "AirPods · Left"), .airpods)
        XCTAssertEqual(AccessoryKind.identify(name: "Custom accessory"), .unknown)
    }

    func testBatteryEnrichmentKeepsAuthoritativeDeviceType() {
        let keyboard = AccessorySnapshot(id: "bt:aabbccddeeff", name: "Custom",
            isConnected: true, batteryPercent: nil, isCharging: false, kind: .keyboard)
        let reading = BatteryReading(id: "AA:BB:CC:DD:EE:FF", name: "Headphones",
            accessoryIdentifier: nil, isConnected: true, batteryPercent: 60, isCharging: false)
        let rows = AccessoryMerger.merge(inventory: [keyboard], batteries: [reading])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .keyboard)
        XCTAssertEqual(rows[0].batteryPercent, 60)
    }

    func testBatteryOnlyPartsRetainProductType() {
        let reading = BatteryReading(id: "left", name: "AirPods Pro · Left",
            accessoryIdentifier: nil, isConnected: true, batteryPercent: 30, isCharging: false)
        let rows = AccessoryMerger.merge(inventory: [], batteries: [reading])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .airpodsPro)
    }

    func testPowerSourceCategoryOverridesAUserAssignedName() {
        XCTAssertEqual(AccessoryKind.identify(name: "My accessory", category: "Keyboard"), .keyboard)
        XCTAssertEqual(AccessoryKind.identify(name: "AirPods", category: "Trackpad"), .trackpad)
    }

    func testPowerSourceModelAndTypeSurviveIdentityMatching() {
        let row = AccessorySnapshot(id: "bt:aabbccddeeff", name: "Custom name",
            isConnected: true, batteryPercent: nil, isCharging: false)
        let reading = BatteryReading(id: "AA:BB:CC:DD:EE:FF", name: "Custom name",
            accessoryIdentifier: nil, isConnected: true, batteryPercent: 60, isCharging: false,
            kind: .keyboard, appleProductID: 0x029A)
        let rows = AccessoryMerger.merge(inventory: [row], batteries: [reading])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .keyboard)
        XCTAssertEqual(rows[0].appleProductID, 0x029A)
    }
}
