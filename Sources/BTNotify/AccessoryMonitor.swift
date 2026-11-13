import AppKit
import BTNotifyCore
import Combine
import CoreGraphics
import Foundation
import UserNotifications

@MainActor
final class AccessoryMonitor: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    let launchAtLogin = LaunchAtLogin()
    @Published var accessories: [AccessorySnapshot] = [] {
        didSet { updateBatteryIndicator() }
    }
    @Published var status = "Starting accessory monitor…"
    @Published var refreshError: String?
    @Published var lastUpdated: Date?
    @Published var isDebugModeEnabled = false
    @Published private(set) var notificationsAllowed = false
    @Published private(set) var isBatteryIndicatorActive = false
    @Published var notificationStatus = "Use Allow Notifications to enable macOS alerts."
    @Published var notificationsEnabled: Bool { didSet {
        defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        if notificationsEnabled && !oldValue { policy = NotificationPolicy(lowBatteryThreshold: lowBatteryThreshold) }
    } }
    @Published var connectionAlertsEnabled: Bool { didSet { defaults.set(connectionAlertsEnabled, forKey: "connectionAlertsEnabled") } }
    @Published var batteryAlertsEnabled: Bool { didSet {
        defaults.set(batteryAlertsEnabled, forKey: "batteryAlertsEnabled")
        if batteryAlertsEnabled && !oldValue { policy = NotificationPolicy(lowBatteryThreshold: lowBatteryThreshold) }
    } }
    @Published var nagMeEnabled: Bool { didSet {
        defaults.set(nagMeEnabled, forKey: "nagMeEnabled")
        if !nagMeEnabled, pendingAlert?.isReminder == true { pendingAlert = nil }
    } }
    @Published var lowBatteryThreshold: Int {
        didSet {
            defaults.set(lowBatteryThreshold, forKey: "lowBatteryThreshold")
            policy = NotificationPolicy(lowBatteryThreshold: lowBatteryThreshold)
            updateBatteryIndicator()
        }
    }
    static let availableCheckIntervals = [10, 30, 60, 120, 180, 240, 300]
    @Published var checkIntervalSeconds: Int {
        didSet {
            guard Self.availableCheckIntervals.contains(checkIntervalSeconds) else {
                checkIntervalSeconds = oldValue
                return
            }
            defaults.set(checkIntervalSeconds, forKey: "checkIntervalSeconds")
            if started { scheduleChecks() }
        }
    }
    var availableBatteryThresholds: [Int] {
        if isDebugModeEnabled { return Array(stride(from: 10, through: 90, by: 5)) }
        let standard = [10, 15, 20, 25, 30]
        return standard.contains(lowBatteryThreshold) ? standard : (standard + [lowBatteryThreshold]).sorted()
    }

    private let defaults: UserDefaults
    private let provider = AccessoryProvider()
    private var policy: NotificationPolicy
    private var timer: Timer?
    private var started = false
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var deliveryGate = NotificationDeliveryGate(isUnlocked: false)
    private var lastBatteryNotificationAt: Date?
    private var lastNotificationRequestID: String?
    private var lastKnownBatteryLevels: [String: Int] = [:]
    private struct PendingAlert {
        let id = UUID()
        let title: String
        let body: String
        let event: AccessoryEvent?
        let isReminder: Bool
    }
    private var pendingAlert: PendingAlert?
    private static let notificationCategoryID = "accessory-alert"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["notificationsEnabled": true, "connectionAlertsEnabled": true,
            "batteryAlertsEnabled": true, "lowBatteryThreshold": 20, "nagMeEnabled": false,
            "checkIntervalSeconds": 30])
        notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        connectionAlertsEnabled = defaults.bool(forKey: "connectionAlertsEnabled")
        batteryAlertsEnabled = defaults.bool(forKey: "batteryAlertsEnabled")
        nagMeEnabled = defaults.bool(forKey: "nagMeEnabled")
        let interval = defaults.integer(forKey: "checkIntervalSeconds")
        checkIntervalSeconds = Self.availableCheckIntervals.contains(interval) ? interval : 30
        lastBatteryNotificationAt = defaults.object(forKey: "lastBatteryNotificationAt") as? Date
        lastNotificationRequestID = defaults.string(forKey: "lastNotificationRequestID")
        let threshold = defaults.integer(forKey: "lowBatteryThreshold")
        let selectedThreshold = (10...90).contains(threshold) && threshold.isMultiple(of: 5) ? threshold : 20
        lowBatteryThreshold = selectedThreshold
        policy = NotificationPolicy(lowBatteryThreshold: selectedThreshold)
        super.init()
        deliveryGate.updateSession(isUnlocked: Self.sessionIsUnlocked)
        UNUserNotificationCenter.current().delegate = self
    }

    func start() {
        guard !started else { return }
        started = true
        let notifications = UNUserNotificationCenter.current()
        notifications.setNotificationCategories([UNNotificationCategory(
            identifier: Self.notificationCategoryID, actions: [], intentIdentifiers: [], options: [.customDismissAction])])
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(sessionLocked),
            name: Notification.Name("com.apple.screenIsLocked"), object: nil, suspensionBehavior: .deliverImmediately)
        distributed.addObserver(self, selector: #selector(sessionUnlocked),
            name: Notification.Name("com.apple.screenIsUnlocked"), object: nil, suspensionBehavior: .deliverImmediately)
        Task {
            // Migrate old UUID-based stacks to a single outstanding alert.
            let delivered = await notifications.deliveredNotifications()
            if let newest = delivered.max(by: { $0.date < $1.date }), delivered.count > 1 {
                notifications.removeDeliveredNotifications(withIdentifiers:
                    delivered.filter { $0.request.identifier != newest.request.identifier }.map { $0.request.identifier })
            }
        }
        updateAuthorization()
        refresh()
        scheduleChecks()
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.policy.resetBaseline()
            }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.policy.resetBaseline()
                self?.refresh()
            }
        }
    }

    private func scheduleChecks() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(checkIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        deliveryGate.updateSession(isUnlocked: Self.sessionIsUnlocked)
        do {
            let snapshot = try provider.read()
            accessories = snapshot
            lastUpdated = Date()
            status = provider.batteryStatus
            refreshError = provider.batteryError
            let events = policy.process(snapshot)
            for event in events where notificationsEnabled {
                guard event.kind == .lowBattery ? batteryAlertsEnabled : connectionAlertsEnabled else { continue }
                send(event)
            }
            if notificationsEnabled, batteryAlertsEnabled, nagMeEnabled,
               NotificationDeliveryGate.reminderIsDue(lastDelivery: lastBatteryNotificationAt, newestOutstanding: nil),
               let accessory = snapshot.first(where: {
                   $0.isConnected && !$0.isCharging && ($0.batteryPercent.map { $0 <= lowBatteryThreshold } ?? false)
               }) {
                send(AccessoryEvent(accessoryID: accessory.id, name: accessory.name,
                    kind: .lowBattery, batteryPercent: accessory.batteryPercent), isReminder: true)
            }
            deliverPendingAlert()
        } catch {
            policy.resetBaseline()
            refreshError = "Refresh failed: \(error.localizedDescription) Last successful readings may be stale."
            status = refreshError ?? "Refresh failed."
        }
    }

    func requestNotifications() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                if granted {
                    policy = NotificationPolicy(lowBatteryThreshold: lowBatteryThreshold)
                    refresh()
                }
                updateAuthorization()
            } catch { notificationStatus = error.localizedDescription }
        }
    }

    func updateAuthorization() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = [.authorized, .provisional].contains(settings.authorizationStatus)
            switch settings.authorizationStatus {
            case .authorized, .provisional: notificationStatus = "macOS notifications allowed."
            case .denied: notificationStatus = "Notifications denied. Enable BTNotify in System Settings → Notifications."
            case .notDetermined: notificationStatus = "Use Allow Notifications to enable macOS alerts."
            @unknown default: notificationStatus = "Notification permission unavailable."
            }
        }
    }

    private func updateBatteryIndicator() {
        for accessory in accessories {
            if let percent = accessory.batteryPercent {
                lastKnownBatteryLevels[accessory.id] = percent
            }
        }
        // Missing readings, disconnection, and charging alone do not establish
        // recovery. Only a known level above the selected threshold clears it.
        let active = lastKnownBatteryLevels.values.contains { $0 <= lowBatteryThreshold }
        if active != isBatteryIndicatorActive { isBatteryIndicatorActive = active }
    }

    func sendTestNotification() {
        post(title: "BTNotify is ready", body: "Accessory battery and connection alerts will appear here.")
    }

    private func send(_ event: AccessoryEvent, isReminder: Bool = false) {
        switch event.kind {
        case .connected: post(title: "\(event.name) connected", event: event)
        case .disconnected: post(title: "\(event.name) disconnected", event: event)
        case .lowBattery: post(title: "\(event.name) battery is low", event: event, isReminder: isReminder)
        }
    }

    private static var sessionIsUnlocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool != true &&
            session[kCGSessionOnConsoleKey as String] as? Bool != false
    }

    @objc private func sessionLocked() {
        deliveryGate.updateSession(isUnlocked: false)
    }

    @objc private func sessionUnlocked() {
        deliveryGate.updateSession(isUnlocked: Self.sessionIsUnlocked)
        refresh()
    }

    private func post(title: String, body: String = "", event: AccessoryEvent? = nil, isReminder: Bool = false) {
        pendingAlert = PendingAlert(title: title, body: body, event: event, isReminder: isReminder)
        deliverPendingAlert()
    }

    private func isStillRelevant(_ alert: PendingAlert) -> Bool {
        guard let event = alert.event else { return true } // Explicit test notification.
        guard notificationsEnabled,
              let accessory = accessories.first(where: { $0.id == event.accessoryID }) else { return false }
        switch event.kind {
        case .connected: return connectionAlertsEnabled && accessory.isConnected
        case .disconnected: return connectionAlertsEnabled && !accessory.isConnected
        case .lowBattery:
            return batteryAlertsEnabled && accessory.isConnected && !accessory.isCharging &&
                (accessory.batteryPercent.map { $0 <= lowBatteryThreshold } ?? false) &&
                (!alert.isReminder || nagMeEnabled)
        }
    }

    static func notificationRequest(title: String, body: String = "") -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = notificationCategoryID
        // Reusing an identifier can silently update macOS notification history
        // instead of presenting a new banner after the prior alert was cleared.
        return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }

    private func deliverPendingAlert() {
        guard let alert = pendingAlert, deliveryGate.beginDelivery() else { return }
        Task {
            defer { deliveryGate.finishDelivery() }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                updateAuthorization()
                return
            }
            let delivered = await center.deliveredNotifications()
            deliveryGate.reconcileDeliveredNotifications(hasDeliveredNotification: !delivered.isEmpty)
            deliveryGate.updateSession(isUnlocked: Self.sessionIsUnlocked)
            let reminderDue = alert.isReminder && nagMeEnabled &&
                NotificationDeliveryGate.reminderIsDue(lastDelivery: lastBatteryNotificationAt,
                    newestOutstanding: delivered.map(\.date).max())
            guard deliveryGate.canDeliver(hasOutstandingNotification: !delivered.isEmpty,
                                          allowingReplacement: reminderDue) else { return }
            guard !alert.isReminder || reminderDue else { return }
            guard isStillRelevant(alert) else {
                if pendingAlert?.id == alert.id { pendingAlert = nil }
                return
            }
            let request = Self.notificationRequest(title: alert.title, body: alert.body)
            do {
                // The delivery gate has confirmed dismissal or an opted-in due
                // reminder. Retire the previous identity before posting a fresh
                // one, including legacy history the delivered query may omit.
                let previousIDs = Set(delivered.map { $0.request.identifier } +
                    [lastNotificationRequestID ?? Self.notificationCategoryID])
                center.removeDeliveredNotifications(withIdentifiers: Array(previousIDs))
                try await center.add(request)
                deliveryGate.deliveryAccepted()
                lastNotificationRequestID = request.identifier
                defaults.set(request.identifier, forKey: "lastNotificationRequestID")
                if pendingAlert?.id == alert.id { pendingAlert = nil }
                if alert.event?.kind == .lowBattery {
                    lastBatteryNotificationAt = Date()
                    defaults.set(lastBatteryNotificationAt, forKey: "lastBatteryNotificationAt")
                }
            }
            catch { notificationStatus = "Notification failed: \(error.localizedDescription)" }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        await handleNotificationResponse()
    }

    func handleNotificationResponse() {
        deliveryGate.notificationDismissed()
        deliverPendingAlert()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
