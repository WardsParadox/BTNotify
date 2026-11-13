import XCTest
@testable import BTNotifyCore

final class AccessoryMergerTests: XCTestCase {
    private func accessory(
        id: String = "bt:aabbccddeeff", name: String = "Keyboard",
        connected: Bool = true, percent: Int? = nil
    ) -> AccessorySnapshot {
        AccessorySnapshot(id: id, name: name, isConnected: connected, batteryPercent: percent, isCharging: false)
    }

    private func battery(
        id: String = "AA:BB:CC:DD:EE:FF", name: String = "Keyboard",
        accessoryID: String? = nil, connected: Bool? = nil, percent: Int? = 67,
        charging: Bool = false
    ) -> BatteryReading {
        BatteryReading(
            id: id, name: name, accessoryIdentifier: accessoryID,
            isConnected: connected, batteryPercent: percent, isCharging: charging
        )
    }

    func testExactAddressEnrichesStableInventoryIdentity() {
        let result = AccessoryMerger.merge(
            inventory: [accessory()], batteries: [battery(name: "Different system name", charging: true)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "bt:aabbccddeeff")
        XCTAssertEqual(result[0].name, "Keyboard")
        XCTAssertEqual(result[0].batteryPercent, 67)
        XCTAssertTrue(result[0].isCharging)
        XCTAssertTrue(result[0].isConnected)
    }

    func testAccessoryIdentifierCanSupplyExactAddress() {
        let result = AccessoryMerger.merge(
            inventory: [accessory()],
            batteries: [battery(id: "opaque-battery-id", name: "Different", accessoryID: "aa-bb-cc-dd-ee-ff")]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].batteryPercent, 67)
    }

    func testUniqueNameMatchesBLEIdentifier() {
        let result = AccessoryMerger.merge(
            inventory: [accessory()],
            batteries: [battery(id: "52BB8E85-2E80-4613-9AEC-F6F48ADFCB7C")]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, "bt:aabbccddeeff")
        XCTAssertEqual(result[0].batteryPercent, 67)
    }

    func testDuplicateInventoryNamesCannotMatchByName() {
        let result = AccessoryMerger.merge(
            inventory: [accessory(), accessory(id: "bt:112233445566")],
            batteries: [battery(id: "opaque-id")]
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.batteryPercent == nil })
    }

    func testTwoSameNamePartsCannotOverwriteOneParent() {
        let result = AccessoryMerger.merge(
            inventory: [accessory()],
            batteries: [battery(id: "left", percent: 10), battery(id: "right", percent: 90)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].batteryPercent)
    }

    func testCompetingExactPartMatchesStaySeparate() {
        let result = AccessoryMerger.merge(
            inventory: [accessory()],
            batteries: [
                battery(id: "left", name: "Left", accessoryID: "AA:BB:CC:DD:EE:FF", connected: true, percent: 10),
                battery(id: "right", name: "Right", accessoryID: "AA:BB:CC:DD:EE:FF", connected: true, percent: 90),
            ]
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertNil(result[0].batteryPercent)
        XCTAssertEqual(Set(result.map(\.id)), ["bt:aabbccddeeff", "battery:left", "battery:right"])
    }

    func testUnknownUnmatchedStateIsOmitted() {
        XCTAssertEqual(AccessoryMerger.merge(inventory: [], batteries: [battery(id: "unmatched")]), [])
    }

    func testSourceOnlyExplicitConnectionStateIsPreserved() {
        let result = AccessoryMerger.merge(inventory: [], batteries: [
            battery(id: "connected", connected: true), battery(id: "disconnected", connected: false),
        ])
        XCTAssertEqual(result.map(\.id), ["battery:connected", "battery:disconnected"])
        XCTAssertEqual(result.map(\.isConnected), [true, false])
    }

    func testInventoryConnectionOverridesStaleBatteryState() {
        let result = AccessoryMerger.merge(
            inventory: [accessory(connected: false)], batteries: [battery(connected: true)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isConnected)
        XCTAssertEqual(result[0].batteryPercent, 67)
    }

    func testNilBatteryDoesNotClobberKnownInventoryLevel() {
        let result = AccessoryMerger.merge(
            inventory: [accessory(percent: 55)], batteries: [battery(percent: nil)]
        )
        XCTAssertEqual(result[0].batteryPercent, 55)
    }

    func testDuplicateIDsAreDeduplicated() {
        let result = AccessoryMerger.merge(
            inventory: [accessory(), accessory()],
            batteries: [battery(id: "source", connected: true), battery(id: "source", connected: true)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].batteryPercent, 67)
    }

    func testExactMatchTakesPriorityOverNameMatch() {
        let result = AccessoryMerger.merge(
            inventory: [accessory()], batteries: [battery(id: "opaque", percent: 10), battery(name: "Exact", percent: 90)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].batteryPercent, 90)
    }
}
