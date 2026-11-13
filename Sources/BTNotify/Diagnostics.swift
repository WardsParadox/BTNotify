import Foundation
import BTNotifyCore
import AppKit
import SwiftUI
import CoreGraphics
import UserNotifications
import ServiceManagement

@MainActor
enum Diagnostics {
    static func runAndExitIfRequested() {
        if CommandLine.arguments.contains("--check-launch-at-login") {
            var systemStatus = SMAppService.Status.notRegistered
            var registrationCount = 0
            var removalCount = 0
            var failRegistration = false
            let login = LaunchAtLogin(readStatus: { systemStatus }, register: {
                registrationCount += 1
                if failRegistration { throw NSError(domain: "LoginCheck", code: 1) }
                systemStatus = .enabled
            }, unregister: {
                removalCount += 1
                systemStatus = .notRegistered
            })
            var failed = false
            func expect(_ condition: Bool, _ name: String) {
                if !condition { failed = true; print("FAIL: \(name)") }
            }
            expect(!login.isRequested && registrationCount == 0, "initialization does not register a login item")
            login.setEnabled(true)
            expect(login.status == .enabled && login.isRequested, "successful registration uses system status")
            systemStatus = .requiresApproval
            login.refreshStatus()
            expect(login.isRequested && login.status == .requiresApproval, "external consent changes require approval")
            login.setEnabled(true)
            expect(registrationCount == 1, "pending approval does not register repeatedly")
            login.setEnabled(false)
            expect(!login.isRequested && removalCount == 1, "pending registration can be removed")
            failRegistration = true
            login.setEnabled(true)
            expect(!login.isRequested && login.errorMessage != nil, "registration failure preserves actual state and shows an error")
            failRegistration = false
            login.setEnabled(true)
            expect(login.isRequested && login.errorMessage == nil, "a successful retry clears the error")
            systemStatus = .notRegistered
            login.refreshStatus()
            expect(!login.isRequested, "external removal is reflected")
            print(failed ? "FAIL: launch at login" : "PASS: login registration, approval, external changes, failure, and retry; no real login items changed")
            exit(failed ? 1 : 0)
        }
        if CommandLine.arguments.contains("--check-apple-events") {
            _ = NSApplication.shared
            var snapshots = [AccessorySnapshot(id: "fixture-keyboard", name: "Keyboard", isConnected: true,
                batteryPercent: 53, isCharging: false, kind: .keyboard),
                AccessorySnapshot(id: "fixture-mouse", name: "Mouse", isConnected: false,
                batteryPercent: nil, isCharging: false, kind: .mouse)]
            var refreshes = 0
            let handler = AccessoryAppleEvents(readings: { snapshots }, refresh: {
                refreshes += 1
                snapshots = [AccessorySnapshot(id: "fixture-keyboard", name: "Keyboard", isConnected: true,
                    batteryPercent: 80, isCharging: true, kind: .keyboard)]
            })
            handler.install()
            defer { handler.uninstall() }
            var failed = false
            func expect(_ condition: Bool, _ name: String) {
                if !condition { failed = true; print("FAIL: \(name)") }
            }
            func dispatch(_ eventID: AEEventID) -> NSAppleEventDescriptor? {
                let event = NSAppleEventDescriptor(eventClass: AccessoryAppleEvents.eventClass, eventID: eventID,
                    targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                let reply = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEAnswer),
                    targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                guard let eventDesc = event.aeDesc, let replyDesc = reply.aeDesc else {
                    expect(false, "event descriptors are available")
                    return nil
                }
                var rawReply = AppleEvent()
                guard AEDuplicateDesc(replyDesc, &rawReply) == noErr else {
                    expect(false, "reply descriptor can be copied")
                    return nil
                }
                var refCon = 0
                let status = withUnsafeMutablePointer(to: &refCon) { pointer in
                    NSAppleEventManager.shared().dispatchRawAppleEvent(eventDesc,
                        withRawReply: &rawReply, handlerRefCon: UnsafeMutableRawPointer(pointer))
                }
                expect(status == noErr, "registered Apple Event dispatch succeeds")
                let result = NSAppleEventDescriptor(aeDescNoCopy: &rawReply)
                return result.paramDescriptor(forKeyword: keyDirectObject)
            }
            let readings = dispatch(AccessoryAppleEvents.statusEvent)
            expect(readings?.numberOfItems == 2 && refreshes == 0, "status returns all readings without a poll")
            let keyboard = readings?.atIndex(1)
            expect(keyboard?.forKeyword(0x49442020)?.stringValue == "fixture-keyboard" &&
                keyboard?.forKeyword(0x706E616D)?.stringValue == "Keyboard" &&
                keyboard?.forKeyword(0x4254636E)?.booleanValue == true &&
                keyboard?.forKeyword(0x4254626C)?.int32Value == 53 &&
                keyboard?.forKeyword(0x42546368)?.booleanValue == false &&
                keyboard?.forKeyword(0x42546B64)?.stringValue == "keyboard", "typed accessory fields survive dispatch")
            expect(readings?.atIndex(2)?.forKeyword(0x4254626C)?.typeCodeValue == AccessoryAppleEvents.missingValueType,
                "unknown battery remains missing value")
            let updated = dispatch(AccessoryAppleEvents.refreshEvent)
            expect(refreshes == 1 && updated?.numberOfItems == 1 &&
                updated?.atIndex(1)?.forKeyword(0x4254626C)?.int32Value == 80 &&
                updated?.atIndex(1)?.forKeyword(0x42546368)?.booleanValue == true,
                "refresh polls once and returns updated readings")
            expect(AccessoryAppleEvents.descriptor(for: []).numberOfItems == 0, "empty inventory remains an empty list")
            expect(Bundle.main.url(forResource: "BTNotify", withExtension: "sdef") != nil,
                "the scripting dictionary is bundled")
            let appPath = Bundle.main.bundlePath.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let source = """
            using terms from application "\(appPath)"
                on verifyTerminology()
                    tell application "\(appPath)"
                        launch
                        set readings to accessory status
                        set refreshedReadings to refresh accessories
                        set batteryValue to battery level of item 1 of readings
                        quit
                    end tell
                end verifyTerminology
            end using terms from
            """
            var compileError: NSDictionary?
            let compiled = NSAppleScript(source: source)?.compileAndReturnError(&compileError) == true
            expect(compiled, "AppleScript terminology compiles without executing commands")
            if let compileError { print("AppleScript compilation: \(compileError)") }
            print(failed ? "FAIL: Apple Events" : "PASS: registered in-process Apple Events, typed readings, missing batteries, refresh, and AppleScript compilation; no live app or accessory changes")
            exit(failed ? 1 : 0)
        }
        if CommandLine.arguments.contains("--check-notification-requests") {
            let first = AccessoryMonitor.notificationRequest(title: "Keyboard battery is low")
            let second = AccessoryMonitor.notificationRequest(title: "Keyboard battery is low")
            let passed = first.identifier != second.identifier &&
                first.content.categoryIdentifier == "accessory-alert" &&
                second.content.categoryIdentifier == first.content.categoryIdentifier &&
                first.content.title == "Keyboard battery is low" && first.content.body.isEmpty &&
                first.trigger == nil && second.trigger == nil
            print(passed ? "PASS: fresh notification identities retain dismissal category and title-only immediate alerts" : "FAIL: new alerts reuse a request identity or lose notification metadata")
            exit(passed ? 0 : 1)
        }
        if CommandLine.arguments.contains("--diagnose-notifications") {
            _ = NSApplication.shared
            Task { @MainActor in
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                let delivered = await center.deliveredNotifications()
                let pending = await center.pendingNotificationRequests()
                let monitor = AccessoryMonitor()
                let session = CGSessionCopyCurrentDictionary() as? [String: Any]
                let authorization: String
                switch settings.authorizationStatus {
                case .authorized: authorization = "authorized"
                case .provisional: authorization = "provisional"
                case .denied: authorization = "denied"
                case .notDetermined: authorization = "not determined"
                @unknown default: authorization = "unknown"
                }
                print("Bundle: \(Bundle.main.bundlePath)")
                print("Authorization: \(authorization); alerts: \(settings.alertSetting.rawValue); style: \(settings.alertStyle.rawValue); notification center: \(settings.notificationCenterSetting.rawValue)")
                print("Delivered: \(delivered.count); pending: \(pending.count)")
                print("Session available: \(session != nil); screen locked: \(String(describing: session?["CGSSessionScreenIsLocked"])); on console: \(String(describing: session?[kCGSessionOnConsoleKey as String])); login complete: \(String(describing: session?[kCGSessionLoginDoneKey as String]))")
                print("App enabled: \(monitor.notificationsEnabled); battery alerts: \(monitor.batteryAlertsEnabled); connection alerts: \(monitor.connectionAlertsEnabled); threshold: \(monitor.lowBatteryThreshold); reminders: \(monitor.nagMeEnabled)")
                exit(0)
            }
            RunLoop.main.run()
            exit(1)
        }
        if CommandLine.arguments.contains("--check-battery-indicator") {
            _ = NSApplication.shared
            let suite = "local.btnotify.indicator-check.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let monitor = AccessoryMonitor(defaults: defaults)
            func reading(_ percent: Int?, id: String = "keyboard", connected: Bool = true,
                         charging: Bool = false) -> AccessorySnapshot {
                AccessorySnapshot(id: id, name: id, isConnected: connected,
                    batteryPercent: percent, isCharging: charging)
            }
            var failed = false
            func expect(_ active: Bool, _ reason: String) {
                if monitor.isBatteryIndicatorActive != active {
                    print("FAIL: \(reason)")
                    failed = true
                }
            }
            expect(false, "starts hollow with no known low battery")
            monitor.notificationsEnabled = false
            monitor.batteryAlertsEnabled = false
            monitor.accessories = [reading(20)]
            expect(true, "threshold reading fills without notification permission or delivery")
            monitor.handleNotificationResponse()
            expect(true, "notification dismissal does not clear a low battery")
            monitor.accessories = [reading(20, charging: true)]
            expect(true, "charging below the threshold stays filled")
            monitor.accessories = [reading(nil, connected: false)]
            expect(true, "unknown and disconnected readings do not establish recovery")
            monitor.accessories = []
            expect(true, "missing readings preserve the last known low battery")
            monitor.accessories = [reading(21, charging: true)]
            expect(false, "one point above the threshold clears without waiting for notification hysteresis")
            monitor.accessories = [reading(19)]
            expect(true, "dropping below the threshold fills again")
            monitor.lowBatteryThreshold = 15
            expect(false, "lowering the threshold immediately clears a now-healthy level")
            monitor.lowBatteryThreshold = 20
            expect(true, "raising the threshold immediately reflects the known battery")
            monitor.accessories = [reading(21), reading(10, id: "mouse")]
            expect(true, "another low accessory keeps the indicator filled")
            monitor.accessories = [reading(21)]
            expect(true, "one recovered accessory does not clear another missing low accessory")
            monitor.accessories = [reading(21, id: "mouse")]
            expect(false, "all known accessories above the threshold clear the indicator")
            monitor.accessories = [reading(80, connected: false)]
            expect(false, "a connection change alone does not fill the indicator")
            print(failed ? "FAIL: battery indicator lifecycle" : "PASS: threshold, charging, dismissal, missing data, multiple accessories, and notification-independent indicator")
            exit(failed ? 1 : 0)
        }
        if CommandLine.arguments.contains("--check-settings-actions") {
            _ = NSApplication.shared
            final class Expansion { var expanded = false }
            let expansion = Expansion()
            let monitor = AccessoryMonitor()
            let panel = AccessoryPanelContent(monitor: monitor, settingsExpanded: Binding(
                get: { expansion.expanded }, set: { expansion.expanded = $0 }))
            var failed = false
            panel.toggleSettings(modifiers: [])
            if !expansion.expanded || monitor.isDebugModeEnabled { failed = true }
            panel.toggleSettings(modifiers: .option)
            if !expansion.expanded || !monitor.isDebugModeEnabled { failed = true }
            panel.toggleSettings(modifiers: [])
            if expansion.expanded { failed = true }
            panel.toggleSettings(modifiers: [.control, .option])
            if !expansion.expanded || monitor.isDebugModeEnabled { failed = true }
            panel.toggleSettings(modifiers: [])
            panel.toggleSettings(modifiers: .option)
            if !expansion.expanded || !monitor.isDebugModeEnabled { failed = true }
            print(failed ? "FAIL: settings activation" : "PASS: normal, Option-click from open/closed, and Control-Option settings actions")
            exit(failed ? 1 : 0)
        }
        if CommandLine.arguments.contains("--check-swiftui-resize") {
            _ = NSApplication.shared
            final class Expansion: ObservableObject { @Published var expanded = false }
            struct Fixture: View {
                @ObservedObject var monitor: AccessoryMonitor
                @ObservedObject var expansion: Expansion
                var onSizeChange: ((NSSize) -> Void)? = nil
                var body: some View {
                    AccessoryPanelContent(monitor: monitor, settingsExpanded: $expansion.expanded, onSizeChange: onSizeChange)
                }
            }
            final class FixtureHost: PanelHostingController<Fixture> {
                var animate = false
                override var shouldAnimateResize: Bool { animate }
            }
            let expansion = Expansion()
            let monitor = AccessoryMonitor()
            monitor.accessories = [AccessorySnapshot(id: "fixture", name: "Accessory", isConnected: true,
                batteryPercent: 54, isCharging: false)]
            let host = FixtureHost(rootView: Fixture(monitor: monitor, expansion: expansion))
            host.sizingOptions = []
            host.rootView.onSizeChange = { [weak host] size in
                Task { @MainActor in host?.preferredContentSize = size }
            }
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 235),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.contentViewController = host
            let popover = NSPopover()
            popover.contentViewController = host
            host.onResizeAnimationChange = { popover.animates = !$0 }
            host.onSizeChange = { popover.contentSize = $0 }
            window.setContentSize(host.view.fittingSize)
            host.preferredContentSize = host.view.fittingSize
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            func settingsInk() -> Int {
                host.view.layoutSubtreeIfNeeded()
                guard let bitmap = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds),
                      host.view.bounds.height > 310 else { return 0 }
                host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
                let scale = CGFloat(bitmap.pixelsHigh) / host.view.bounds.height
                var ink = 0
                for y in Int(265 * scale)..<Int(305 * scale) {
                    for x in Int(35 * scale)..<Int(320 * scale) {
                        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { ink += 1 }
                    }
                }
                return ink
            }
            var failed = false
            for expanded in [true, false] {
                let start = popover.contentSize.height
                let originalInk = expanded ? 0 : settingsInk()
                host.animate = true
                let began = Date()
                withAnimation(.default) { expansion.expanded = expanded }
                var samples: [Double] = []
                var inkSamples: [Int] = []
                for time in [0.02, 0.08, 0.16, 0.25, 0.40] {
                    RunLoop.current.run(until: began.addingTimeInterval(time))
                    host.view.layoutSubtreeIfNeeded()
                    samples.append(popover.contentSize.height)
                    window.setContentSize(popover.contentSize)
                    inkSamples.append(settingsInk())
                }
                let end = samples.last ?? start
                let intermediate = samples.dropLast().filter { abs($0 - start) > 1 && abs($0 - end) > 1 }
                let passed = abs(end - start) > 150 && intermediate.count >= 2
                print("\(passed ? "PASS" : "FAIL"): actual SwiftUI \(expanded ? "expand" : "collapse"), \(Int(start)) → \(samples.map { Int($0) })")
                if !passed { failed = true }
                if !expanded {
                    let contentRetained = originalInk > 0 && (inkSamples.first ?? 0) > originalInk / 2
                    print("\(contentRetained ? "PASS" : "FAIL"): collapse retains settings during easing, ink \(originalInk) → \(inkSamples)")
                    if !contentRetained { failed = true }
                }
            }
            window.close()
            exit(failed ? 1 : 0)
        }
        if CommandLine.arguments.contains("--check-thresholds") {
            _ = NSApplication.shared
            let suite = "local.btnotify.threshold-check.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            var failed = false
            do {
                defer { defaults.removePersistentDomain(forName: suite) }
                defaults.set(90, forKey: "lowBatteryThreshold")
                let monitor = AccessoryMonitor(defaults: defaults)
                if monitor.nagMeEnabled { failed = true }
                if monitor.checkIntervalSeconds != 30 { failed = true }
                if AccessoryMonitor.availableCheckIntervals != [10, 30, 60, 120, 180, 240, 300] { failed = true }
                monitor.checkIntervalSeconds = 120
                monitor.nagMeEnabled = true
                if monitor.lowBatteryThreshold != 90 || !monitor.availableBatteryThresholds.contains(90) { failed = true }
                if monitor.availableBatteryThresholds.contains(85) { failed = true }
                monitor.isDebugModeEnabled = true
                if monitor.availableBatteryThresholds != Array(stride(from: 10, through: 90, by: 5)) { failed = true }
                monitor.lowBatteryThreshold = 85
                let reloaded = AccessoryMonitor(defaults: defaults)
                if !reloaded.nagMeEnabled { failed = true }
                if reloaded.checkIntervalSeconds != 120 { failed = true }
                reloaded.checkIntervalSeconds = 15
                if reloaded.checkIntervalSeconds != 120 { failed = true }
                if reloaded.lowBatteryThreshold != 85 || !reloaded.availableBatteryThresholds.contains(85) { failed = true }
                defaults.set(37, forKey: "lowBatteryThreshold")
                if AccessoryMonitor(defaults: defaults).lowBatteryThreshold != 20 { failed = true }
                defaults.set(15, forKey: "checkIntervalSeconds")
                if AccessoryMonitor(defaults: defaults).checkIntervalSeconds != 30 { failed = true }
            }
            print(failed ? "FAIL: threshold, polling, or reminder preferences" : "PASS: Option thresholds, saved high values, 30-second polling, validated intervals, default-off reminders, and persistence")
            exit(failed ? 1 : 0)
        }
        if CommandLine.arguments.contains("--check-resize") {
            _ = NSApplication.shared
            final class FixtureHost: PanelHostingController<AccessoryPanel> {
                var animate = false
                override var shouldAnimateResize: Bool { animate }
            }
            let host = FixtureHost(rootView: AccessoryPanel(monitor: AccessoryMonitor()))
            host.sizingOptions = []
            let popover = NSPopover()
            popover.contentViewController = host
            popover.animates = false
            host.onResizeAnimationChange = { popover.animates = !$0 }
            var failed = false
            host.onSizeChange = {
                if popover.animates { failed = true }
                popover.contentSize = $0
            }
            for (start, end) in [(300.0, 500.0), (500.0, 300.0)] {
                host.animate = false
                host.preferredContentSize = NSSize(width: 360, height: start)
                host.animate = true
                let began = Date()
                host.preferredContentSize = NSSize(width: 360, height: end)
                var samples: [Double] = []
                for time in [0.0, 0.05, 0.15, 0.25, 0.36] {
                    if time > 0 { RunLoop.current.run(until: began.addingTimeInterval(time)) }
                    samples.append(popover.contentSize.height)
                }
                let progress = samples.map { ($0 - start) / (end - start) }
                let passed = abs(progress[0]) < 0.05 && progress[1] > 0 && progress[1] < 0.18 &&
                    progress[2] > 0.25 && progress[2] < 0.8 &&
                    progress[3] > 0.85 && abs(progress[4] - 1) < 0.01
                print("\(passed ? "PASS" : "FAIL"): resize \(Int(start)) → \(Int(end)), heights \(samples.map { Int($0) })")
                if !passed { failed = true }
            }
            host.preferredContentSize = NSSize(width: 360, height: 500)
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            let interruptedHeight = popover.contentSize.height
            host.preferredContentSize = NSSize(width: 360, height: 300)
            if abs(popover.contentSize.height - interruptedHeight) > 1 { failed = true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.36))
            if abs(popover.contentSize.height - 300) > 1 { failed = true }
            host.animate = false
            host.preferredContentSize = NSSize(width: 360, height: 410)
            if popover.contentSize.height != 410 { failed = true }
            print(failed ? "FAIL: timed popover resizing" : "PASS: eased sizes, smooth reversal, and immediate nonanimated resize")
            exit(failed ? 1 : 0)
        }
        if CommandLine.arguments.contains("--check-disclosure") {
            _ = NSApplication.shared
            let monitor = AccessoryMonitor()
            monitor.accessories = (0..<1).map { index in
                AccessorySnapshot(id: "fixture:\(index)", name: "Accessory \(index + 1)",
                    isConnected: true, batteryPercent: 54, isCharging: false)
            }
            final class Expansion: ObservableObject { @Published var expanded = false }
            struct Fixture: View {
                @ObservedObject var monitor: AccessoryMonitor
                @ObservedObject var expansion: Expansion
                var body: some View {
                    AccessoryPanelContent(monitor: monitor, settingsExpanded: $expansion.expanded)
                }
            }
            let expansion = Expansion()
            let host = NSHostingController(rootView: Fixture(monitor: monitor, expansion: expansion))
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 360, height: 300),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.contentViewController = host
            window.setContentSize(host.view.fittingSize)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            var failed = false
            for _ in 0..<2 {
                var footerSamples: [Int] = []
                withAnimation(.default) { expansion.expanded.toggle() }
                for _ in 0..<25 {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.016))
                    let size = host.view.fittingSize
                    window.setContentSize(size)
                    host.view.layoutSubtreeIfNeeded()
                    guard let bitmap = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else {
                        print("FAIL: cannot render offscreen panel")
                        exit(1)
                    }
                    host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
                    // Both persistent footer controls must remain stable, with
                    // outgoing settings clipped above their shared row.
                    let scale = CGFloat(bitmap.pixelsHigh) / host.view.bounds.height
                    let top = bitmap.pixelsHigh - Int(36 * scale)
                    let bottom = bitmap.pixelsHigh - Int(14 * scale)
                    var ink = 0
                    for y in max(0, top)..<max(0, bottom) {
                        for x in Int(18 * scale)..<Int(342 * scale) {
                            if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { ink += 1 }
                        }
                    }
                    footerSamples.append(ink)
                }
                let settled = footerSamples.last ?? 0
                let tolerance = max(5, settled / 50)
                if settled == 0 || footerSamples.contains(where: { abs($0 - settled) > tolerance }) {
                    print("FAIL: footer moves/fades after resize (\(expansion.expanded ? "expand" : "collapse")): \(footerSamples)")
                    failed = true
                } else {
                    print("PASS: footer stable throughout \(expansion.expanded ? "expansion" : "collapse")")
                }
            }
            window.close()
            exit(failed ? 1 : 0)
        }
        if CommandLine.arguments.contains("--check-ui") {
            _ = NSApplication.shared
            let monitor = AccessoryMonitor()
            var failed = false
            for count in [0, 1, 20] {
                monitor.accessories = (0..<count).map { index in
                    AccessorySnapshot(id: "fixture:\(index)", name: "Accessory \(index + 1)",
                        isConnected: true, batteryPercent: 54, isCharging: false)
                }
                var collapsedHeight: CGFloat = 0
                for expanded in [false, true, false] {
                    let host = NSHostingView(rootView: AccessoryPanelContent(monitor: monitor, settingsExpanded: .constant(expanded)))
                    let size = host.fittingSize
                    print("Panel with \(count) accessories, settings \(expanded ? "expanded" : "collapsed"): \(Int(size.width))×\(Int(size.height))")
                    if size.width != 360 || size.height < 200 || !size.height.isFinite { failed = true }
                    if expanded {
                        if size.height < collapsedHeight + 150 { failed = true }
                    } else if collapsedHeight == 0 {
                        collapsedHeight = size.height
                    } else if abs(size.height - collapsedHeight) > 1 {
                        failed = true
                    }
                }
            }
            for kind in AccessoryKind.allCases {
                if NSImage(systemSymbolName: kind.systemImage, accessibilityDescription: nil) == nil {
                    print("FAIL: unavailable device symbol \(kind.systemImage)")
                    failed = true
                }
            }
            var systemImageCount = 0
            for kind in AccessoryKind.allCases {
                let fixture = AccessorySnapshot(id: "fixture", name: "Fixture", isConnected: true,
                    batteryPercent: nil, isCharging: false, kind: kind)
                if let image = SystemDeviceIcons.image(for: fixture), image.isValid { systemImageCount += 1 }
            }
            let keyboard = AccessorySnapshot(id: "fixture", name: "Custom name", isConnected: true,
                batteryPercent: nil, isCharging: false, appleProductID: 0x029A)
            print("Installed macOS artwork: \(systemImageCount) device types; model-specific keyboard: \(SystemDeviceIcons.image(for: keyboard) != nil)")
            let idle = StatusController.makeStatusImage(batteryIsLow: false)
            let lowBattery = StatusController.makeStatusImage(batteryIsLow: true)
            if !idle.isTemplate || lowBattery.isTemplate { failed = true }
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                func badgeBounds(_ image: NSImage) -> NSRect? {
                    let canvas = NSImage(size: NSSize(width: 176, height: 160))
                    canvas.lockFocus()
                    image.draw(in: NSRect(x: 0, y: 0, width: 176, height: 160))
                    canvas.unlockFocus()
                    guard let data = canvas.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: data) else { return nil }
                    let scale = CGFloat(bitmap.pixelsWide) / 22
                    var bounds = NSRect.null
                    // The right half of the badge excludes the Bluetooth rune.
                    for y in 0..<Int(9 * scale) {
                        for x in Int(13 * scale)..<Int(19 * scale) {
                            if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                                bounds = bounds.union(NSRect(x: x, y: y, width: 1, height: 1))
                            }
                        }
                    }
                    return bounds.isNull ? nil : NSRect(x: bounds.minX / scale, y: bounds.minY / scale,
                        width: bounds.width / scale, height: bounds.height / scale)
                }
                if let emptyBounds = badgeBounds(idle), let filledBounds = badgeBounds(lowBattery),
                   abs(emptyBounds.height - filledBounds.height) <= 0.125,
                   abs(emptyBounds.minY - filledBounds.minY) <= 0.125,
                   abs(emptyBounds.maxX - filledBounds.maxX) <= 0.125 {
                    print("PASS: hollow and filled badge outer bounds match")
                } else {
                    print("FAIL: hollow and filled badge outer bounds differ: \(String(describing: badgeBounds(idle))) / \(String(describing: badgeBounds(lowBattery)))")
                    failed = true
                }
                // Compare rendered semantic colors. HDR system colors can be
                // tone-mapped by NSImage, unlike raw NSColor RGB components.
                let redSwatch = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { bounds in
                    NSColor.systemRed.setFill()
                    NSBezierPath(rect: bounds).fill()
                    return true
                }
                guard let idleData = idle.tiffRepresentation,
                      let lowBatteryData = lowBattery.tiffRepresentation,
                      let swatchData = redSwatch.tiffRepresentation,
                      let idleBitmap = NSBitmapImageRep(data: idleData),
                      let lowBatteryBitmap = NSBitmapImageRep(data: lowBatteryData),
                      let swatchBitmap = NSBitmapImageRep(data: swatchData),
                      let empty = idleBitmap.colorAt(x: 15, y: 4),
                      let filled = lowBatteryBitmap.colorAt(x: 15, y: 4)?.usingColorSpace(.sRGB),
                      let expectedRed = swatchBitmap.colorAt(x: 15, y: 4)?.usingColorSpace(.sRGB) else {
                    failed = true
                    return
                }
                if empty.alphaComponent > 0.1 || filled.alphaComponent < 0.9 ||
                    abs(filled.redComponent - expectedRed.redComponent) > 0.1 ||
                    abs(filled.greenComponent - expectedRed.greenComponent) > 0.1 ||
                    abs(filled.blueComponent - expectedRed.blueComponent) > 0.1 {
                    print("FAIL: badge must be empty when idle and use system red while a battery is low")
                    failed = true
                }
            }
            print(failed ? "FAIL: offscreen UI checks" : "PASS: panel sizing, device symbols, and hollow/red badge rendering")
            exit(failed ? 1 : 0)
        }
        guard CommandLine.arguments.contains("--diagnose") else { return }
        let provider = AccessoryProvider()
        do {
            let snapshot = try provider.read()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            struct Report: Encodable {
                let batteryStatus: String
                let accessories: [AccessorySnapshot]
                let batteryRows: Int
                let inventoryRows: Int
                let limitations: [String]
            }
            let report = Report(batteryStatus: provider.batteryStatus, accessories: snapshot,
                batteryRows: provider.batteryCount, inventoryRows: provider.inventoryCount,
                limitations: ["The accessory power-source API is private and may change with macOS updates.",
                    "Absent devices do not prove disconnection; only explicit state changes trigger alerts.",
                    "Native Bluetooth connection state is sampled every 30 seconds by default; Option-click exposes a 10-second to 5-minute interval. Unknown battery levels remain null."])
            FileHandle.standardOutput.write(try encoder.encode(report))
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Diagnosis failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
