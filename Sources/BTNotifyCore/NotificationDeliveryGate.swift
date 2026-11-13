import Foundation

/// Serializes asynchronous delivery and rechecks session/dismissal state just
/// before posting. A delivered notification remains outstanding until removed.
public struct NotificationDeliveryGate: Sendable {
    public private(set) var isUnlocked: Bool
    private var isPosting = false
    private var hasAcceptedNotification = false
    private var hasObservedDelivery = false

    public init(isUnlocked: Bool) { self.isUnlocked = isUnlocked }

    public mutating func updateSession(isUnlocked: Bool) {
        self.isUnlocked = isUnlocked
    }

    public mutating func beginDelivery() -> Bool {
        guard isUnlocked, !isPosting else { return false }
        isPosting = true
        return true
    }

    public func canDeliver(hasOutstandingNotification: Bool, allowingReplacement: Bool = false) -> Bool {
        isPosting && isUnlocked &&
            ((!hasOutstandingNotification && !hasAcceptedNotification) || allowingReplacement)
    }

    public mutating func finishDelivery() { isPosting = false }

    public mutating func deliveryAccepted() {
        hasAcceptedNotification = true
        hasObservedDelivery = false
    }

    public mutating func notificationDismissed() {
        hasAcceptedNotification = false
        hasObservedDelivery = false
    }

    public mutating func reconcileDeliveredNotifications(hasDeliveredNotification: Bool) {
        if hasDeliveredNotification {
            hasAcceptedNotification = true
            hasObservedDelivery = true
        } else if hasObservedDelivery {
            notificationDismissed()
        }
        // An empty read before the first confirmed delivery is not a dismissal.
    }

    public static func reminderIsDue(lastDelivery: Date?, newestOutstanding: Date?, now: Date = Date()) -> Bool {
        (lastDelivery.map { now.timeIntervalSince($0) >= 300 } ?? true) &&
            (newestOutstanding.map { now.timeIntervalSince($0) >= 300 } ?? true)
    }
}
