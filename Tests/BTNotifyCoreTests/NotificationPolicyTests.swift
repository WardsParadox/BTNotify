import XCTest
@testable import BTNotifyCore

final class NotificationPolicyTests: XCTestCase {
    private func accessory(
        _ id: String = "headphones", connected: Bool = true,
        battery: Int? = 80, charging: Bool = false
    ) -> AccessorySnapshot {
        AccessorySnapshot(
            id: id, name: "Headphones", isConnected: connected,
            batteryPercent: battery, isCharging: charging
        )
    }

    func testConnectionBaselineAndTransitionsAreDeduplicated() {
        var policy = NotificationPolicy()
        XCTAssertEqual(policy.process([accessory()]), [])
        XCTAssertEqual(policy.process([accessory()]), [])
        XCTAssertEqual(policy.process([accessory(connected: false)]).map(\.kind), [.disconnected])
        XCTAssertEqual(policy.process([accessory(connected: false)]), [])
        XCTAssertEqual(policy.process([accessory()]).map(\.kind), [.connected])
    }

    func testFirstSeenConnectedAccessoryAfterBaselineNotifies() {
        var policy = NotificationPolicy()
        _ = policy.process([accessory()])
        XCTAssertEqual(policy.process([accessory("mouse")]).map(\.kind), [.connected])
        XCTAssertEqual(policy.process([accessory("keyboard", connected: false)]), [])
    }

    func testInitialLowBatteryAlertsOnceWithAccessoryIdentity() {
        var policy = NotificationPolicy()
        XCTAssertEqual(policy.process([accessory(battery: 15)]), [
            AccessoryEvent(accessoryID: "headphones", name: "Headphones", kind: .lowBattery, batteryPercent: 15)
        ])
        XCTAssertEqual(policy.process([accessory(battery: 14)]), [])
        XCTAssertEqual(policy.process([accessory(battery: nil)]), [])
        XCTAssertEqual(policy.process([accessory(battery: 13)]), [])
    }

    func testBatteryHysteresisRequiresFivePointRecovery() {
        var policy = NotificationPolicy()
        _ = policy.process([accessory(battery: 20)])
        XCTAssertEqual(policy.process([accessory(battery: 24)]), [])
        XCTAssertEqual(policy.process([accessory(battery: 19)]), [])
        XCTAssertEqual(policy.process([accessory(battery: 25)]), [])
        XCTAssertEqual(policy.process([accessory(battery: 20)]).map(\.kind), [.lowBattery])
    }

    func testChargingSuppressesLowBatteryUntilUnplugged() {
        var policy = NotificationPolicy()
        XCTAssertEqual(policy.process([accessory(battery: 10, charging: true)]), [])
        XCTAssertEqual(policy.process([accessory(battery: 10)]).map(\.kind), [.lowBattery])
        XCTAssertEqual(policy.process([accessory(battery: 11, charging: true)]), [])
        XCTAssertEqual(policy.process([accessory(battery: 11)]), [])
        _ = policy.process([accessory(battery: 80, charging: true)])
        XCTAssertEqual(policy.process([accessory(battery: 10)]).map(\.kind), [.lowBattery])
    }

    func testDisconnectedLowBatteryDoesNotAlertOrRearm() {
        var policy = NotificationPolicy()
        XCTAssertEqual(policy.process([accessory(connected: false, battery: 10)]), [])
        XCTAssertEqual(policy.process([accessory(battery: 10)]).map(\.kind), [.connected, .lowBattery])
        _ = policy.process([accessory(connected: false, battery: 100)])
        XCTAssertEqual(policy.process([accessory(battery: 10)]).map(\.kind), [.connected])
    }

    func testPartialObservationsDoNotInventDisconnects() {
        var policy = NotificationPolicy()
        _ = policy.process([accessory(), accessory("mouse")])
        XCTAssertEqual(policy.process([]), [])
        XCTAssertEqual(policy.process([accessory("mouse")]), [])
        XCTAssertEqual(policy.process([accessory()]), [])
        XCTAssertEqual(policy.process([accessory(connected: false)]).map(\.kind), [.disconnected])
    }

    func testResetBaselineSuppressesConnectionNoiseAndKeepsBatteryLatch() {
        var policy = NotificationPolicy()
        _ = policy.process([accessory(battery: 10)])
        policy.resetBaseline()
        XCTAssertEqual(policy.process([accessory(battery: 9), accessory("mouse")]), [])
        XCTAssertEqual(policy.process([accessory(connected: false)]).map(\.kind), [.disconnected])
    }

    func testCustomThresholdAndInvalidBatteryData() {
        var policy = NotificationPolicy(lowBatteryThreshold: 30)
        XCTAssertEqual(policy.process([accessory(battery: -1)]), [])
        XCTAssertNil(accessory(battery: 101).batteryPercent)
        XCTAssertEqual(policy.process([accessory(battery: 30)]).map(\.kind), [.lowBattery])
        _ = policy.process([accessory(battery: 35)])
        XCTAssertEqual(policy.process([accessory(battery: 29)]).map(\.kind), [.lowBattery])
    }

    func testAccessoryAndEventRoundTripThroughJSON() throws {
        let snapshot = accessory(battery: 10)
        XCTAssertEqual(try JSONDecoder().decode(AccessorySnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        var policy = NotificationPolicy()
        let event = try XCTUnwrap(policy.process([snapshot]).first)
        XCTAssertEqual(try JSONDecoder().decode(AccessoryEvent.self, from: JSONEncoder().encode(event)), event)
    }

    func testMaximumThresholdDoesNotRepeatAnAlertAtFullCharge() {
        var policy = NotificationPolicy(lowBatteryThreshold: 100)
        XCTAssertEqual(policy.process([accessory(battery: 100)]).map(\.kind), [.lowBattery])
        XCTAssertEqual(policy.process([accessory(battery: 100)]), [])
    }
}
