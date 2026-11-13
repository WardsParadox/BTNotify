import XCTest
@testable import BTNotifyCore

final class NotificationDeliveryGateTests: XCTestCase {
    func testOnlyOneAsynchronousAttemptCanBeInFlight() {
        var gate = NotificationDeliveryGate(isUnlocked: true)
        XCTAssertTrue(gate.beginDelivery())
        XCTAssertFalse(gate.beginDelivery())
        XCTAssertTrue(gate.canDeliver(hasOutstandingNotification: false))
        gate.finishDelivery()
        XCTAssertTrue(gate.beginDelivery())
    }

    func testOutstandingNotificationBlocksUntilDismissed() {
        var gate = NotificationDeliveryGate(isUnlocked: true)
        XCTAssertTrue(gate.beginDelivery())
        XCTAssertFalse(gate.canDeliver(hasOutstandingNotification: true))
        gate.finishDelivery()
        XCTAssertTrue(gate.beginDelivery())
        XCTAssertTrue(gate.canDeliver(hasOutstandingNotification: false))
    }

    func testLockDuringAnAsynchronousReadBlocksPosting() {
        var gate = NotificationDeliveryGate(isUnlocked: true)
        XCTAssertTrue(gate.beginDelivery())
        gate.updateSession(isUnlocked: false)
        XCTAssertFalse(gate.canDeliver(hasOutstandingNotification: false))
        gate.finishDelivery()
        XCTAssertFalse(gate.beginDelivery())
        gate.updateSession(isUnlocked: true)
        XCTAssertTrue(gate.beginDelivery())
        XCTAssertTrue(gate.canDeliver(hasOutstandingNotification: false))
    }

    func testFailedAttemptReleasesTheDeliveryReservation() {
        var gate = NotificationDeliveryGate(isUnlocked: true)
        XCTAssertTrue(gate.beginDelivery())
        gate.finishDelivery()
        XCTAssertTrue(gate.beginDelivery())
        XCTAssertFalse(gate.canDeliver(hasOutstandingNotification: true))
    }

    func testDueReminderCanReplaceButCannotBypassSessionLock() {
        var gate = NotificationDeliveryGate(isUnlocked: true)
        XCTAssertTrue(gate.beginDelivery())
        XCTAssertTrue(gate.canDeliver(hasOutstandingNotification: true, allowingReplacement: true))
        gate.updateSession(isUnlocked: false)
        XCTAssertFalse(gate.canDeliver(hasOutstandingNotification: true, allowingReplacement: true))
    }

    func testReminderWaitsFiveMinutesIncludingAfterRelaunch() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(NotificationDeliveryGate.reminderIsDue(
            lastDelivery: now.addingTimeInterval(-299), newestOutstanding: nil, now: now))
        XCTAssertTrue(NotificationDeliveryGate.reminderIsDue(
            lastDelivery: now.addingTimeInterval(-300), newestOutstanding: nil, now: now))
        XCTAssertFalse(NotificationDeliveryGate.reminderIsDue(
            lastDelivery: nil, newestOutstanding: now.addingTimeInterval(-299), now: now))
        XCTAssertTrue(NotificationDeliveryGate.reminderIsDue(
            lastDelivery: nil, newestOutstanding: now.addingTimeInterval(-300), now: now))
    }

    func testNewerOutstandingAlertAlsoDelaysAnOptedInReminder() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(NotificationDeliveryGate.reminderIsDue(
            lastDelivery: now.addingTimeInterval(-600), newestOutstanding: now.addingTimeInterval(-20), now: now))
    }

    func testAcceptedRequestCannotBeDuplicatedBeforeDeliveryAppears() {
        var gate = NotificationDeliveryGate(isUnlocked: true)
        XCTAssertTrue(gate.beginDelivery())
        gate.deliveryAccepted()
        gate.finishDelivery()
        XCTAssertTrue(gate.beginDelivery())
        gate.reconcileDeliveredNotifications(hasDeliveredNotification: false)
        XCTAssertFalse(gate.canDeliver(hasOutstandingNotification: false))
    }

    func testRemovalAfterConfirmedDeliveryAllowsTheNextAlert() {
        var gate = NotificationDeliveryGate(isUnlocked: true)
        XCTAssertTrue(gate.beginDelivery())
        gate.deliveryAccepted()
        gate.finishDelivery()
        gate.reconcileDeliveredNotifications(hasDeliveredNotification: true)
        gate.reconcileDeliveredNotifications(hasDeliveredNotification: false)
        XCTAssertTrue(gate.beginDelivery())
        XCTAssertTrue(gate.canDeliver(hasOutstandingNotification: false))
    }

    func testExplicitDismissalCanArriveBeforeTheFirstDeliveredRead() {
        var gate = NotificationDeliveryGate(isUnlocked: true)
        XCTAssertTrue(gate.beginDelivery())
        gate.deliveryAccepted()
        gate.finishDelivery()
        gate.notificationDismissed()
        XCTAssertTrue(gate.beginDelivery())
        XCTAssertTrue(gate.canDeliver(hasOutstandingNotification: false))
    }
}
