import AppKit
import BTNotifyCore
import Combine
import CoreServices
import SwiftUI

@main
@MainActor
struct BTNotifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        Diagnostics.runAndExitIfRequested()
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?
    private var monitor: AccessoryMonitor?
    private var appleEvents: AccessoryAppleEvents?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Register this exact installed bundle before creating the notification
        // center, so system UI can resolve its current icon after an update/move.
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        NSApp.applicationIconImage = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let monitor = AccessoryMonitor()
        self.monitor = monitor
        monitor.start()
        // Install before initial scripting events are dispatched by AppKit.
        let appleEvents = AccessoryAppleEvents(readings: { monitor.accessories }, refresh: { monitor.refresh() })
        self.appleEvents = appleEvents
        appleEvents.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let monitor else { return }
        statusController = StatusController(monitor: monitor)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appleEvents?.uninstall()
    }
}

/// AppKit owns presentation and sizing; SwiftUI renders the native controls.
@MainActor
final class StatusController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let monitor: AccessoryMonitor
    private var subscriptions: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?
    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let versionItem = NSMenuItem(title: "Version \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BTNotify", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        return menu
    }()

    init(monitor: AccessoryMonitor) {
        self.monitor = monitor
        super.init()
        let host = PanelHostingController(rootView: AccessoryPanel(monitor: monitor))
        host.sizingOptions = []
        host.rootView.onSizeChange = { [weak host] size in
            Task { @MainActor in host?.preferredContentSize = size }
        }
        host.onResizeAnimationChange = { [weak popover] resizing in
            // Disable NSPopover's own resize animation for the whole transition.
            popover?.animates = !resizing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        host.onSizeChange = { [weak popover] size in
            guard size.width > 0, size.height > 0, popover?.contentSize != size else { return }
            popover?.contentSize = size
        }
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let button = statusItem.button {
            button.setAccessibilityLabel("BTNotify")
            button.toolTip = "BTNotify — accessory batteries and connections"
            button.target = self
            button.action = #selector(handleStatusClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor in self?.updateStatusImage() }
            }
        }
        monitor.$isBatteryIndicatorActive
            .removeDuplicates()
            .sink { [weak self] active in self?.updateStatusImage(batteryIsLow: active) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)
            .sink { [weak self] _ in self?.updateStatusImage() }
            .store(in: &subscriptions)
    }

    private func updateStatusImage(batteryIsLow: Bool? = nil) {
        guard let button = statusItem.button else { return }
        let active = batteryIsLow ?? monitor.isBatteryIndicatorActive
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            button.image = Self.makeStatusImage(batteryIsLow: active)
        }
        button.setAccessibilityLabel(active ? "BTNotify, accessory battery low" : "BTNotify")
    }

    /// Original Bluetooth rune and round low-battery badge for the menu bar.
    static func makeStatusImage(batteryIsLow: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            // Fit the artwork's bounds, keeping both marks legible at menu bar size.
            let scale: CGFloat = 18 / 720
            let transform = NSAffineTransform()
            transform.transformStruct = NSAffineTransformStruct(
                m11: scale, m12: 0, m21: 0, m22: -scale,
                tX: 3 - 266 * scale, tY: 19 + 144 * scale)
            transform.concat()

            (batteryIsLow ? NSColor.labelColor : NSColor.black).setStroke()
            let bluetooth = NSBezierPath()
            bluetooth.move(to: NSPoint(x: 302, y: 360))
            bluetooth.line(to: NSPoint(x: 648, y: 668))
            bluetooth.line(to: NSPoint(x: 448, y: 824))
            bluetooth.line(to: NSPoint(x: 448, y: 200))
            bluetooth.line(to: NSPoint(x: 648, y: 356))
            bluetooth.line(to: NSPoint(x: 302, y: 664))
            bluetooth.lineWidth = 72
            bluetooth.lineCapStyle = .round
            bluetooth.lineJoinStyle = .round
            bluetooth.stroke()

            // Match the circular badge in the app icon's vector artwork.
            // Stroke inward from shared outer bounds so both states have the
            // same diameter. A centered outline otherwise adds 40 vector units.
            let outerBounds = NSRect(x: 606, y: 162, width: 248, height: 248)
            let color = batteryIsLow ? NSColor.systemRed : NSColor.black
            color.setStroke()
            color.setFill()
            if batteryIsLow {
                NSBezierPath(ovalIn: outerBounds).fill()
            } else {
                let badge = NSBezierPath(ovalIn: outerBounds.insetBy(dx: 20, dy: 20))
                badge.lineWidth = 40
                badge.stroke()
            }
            return true
        }
        image.isTemplate = !batteryIsLow
        image.accessibilityDescription = batteryIsLow ? "Bluetooth accessory battery low" : "Bluetooth accessories"
        return image
    }

    @objc private func handleStatusClick() {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        let modifiers = event?.modifierFlags ?? []
        // VoiceOver uses Control-Option for activation. Interpret modifiers only
        // on mouse-up events, and keep that chord on the ordinary press path.
        if let event,
           event.type == .rightMouseUp ||
            (event.type == .leftMouseUp && modifiers.contains(.control) && !modifiers.contains(.option)) {
            popover.performClose(nil)
            NSMenu.popUpContextMenu(contextMenu, with: event, for: button)
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            monitor.isDebugModeEnabled = false
            monitor.updateAuthorization()
            monitor.launchAtLogin.refreshStatus()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            monitor.refresh()
        }
    }

}

/// Nonblocking NSAnimation invokes progress on the main run loop. Copy only
/// the numeric progress and Sendable callback across its legacy API boundary.
private final class PanelSizeAnimation: NSAnimation {
    private let onProgress: @MainActor @Sendable (CGFloat) -> Void

    init(onProgress: @escaping @MainActor @Sendable (CGFloat) -> Void) {
        self.onProgress = onProgress
        super.init(duration: 0.28, animationCurve: .easeInOut)
        animationBlockingMode = .nonblocking
        frameRate = 60
    }

    required init?(coder: NSCoder) { nil }

    override var currentProgress: NSAnimation.Progress {
        didSet {
            let progress = CGFloat(currentValue)
            let callback = onProgress
            MainActor.assumeIsolated { callback(progress) }
        }
    }
}

@MainActor
class PanelHostingController<Content: View>: NSHostingController<Content> {
    var onSizeChange: ((NSSize) -> Void)?
    var onResizeAnimationChange: ((Bool) -> Void)?
    private var startSize: NSSize = .zero
    private var targetSize: NSSize = .zero
    private lazy var resizeAnimation = PanelSizeAnimation { [weak self] progress in
        guard let self else { return }
        let size = NSSize(
            width: startSize.width + (targetSize.width - startSize.width) * progress,
            height: startSize.height + (targetSize.height - startSize.height) * progress)
        applyPresentedSize(size)
        if progress >= 1 { onResizeAnimationChange?(false) }
    }
    var shouldAnimateResize: Bool {
        viewIfLoaded?.window?.isVisible == true &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    override var preferredContentSize: NSSize {
        get { super.preferredContentSize }
        set {
            guard newValue.width > 0, newValue.height > 0 else { return }
            let animate = shouldAnimateResize
            guard newValue != targetSize || (!animate && preferredContentSize != newValue) else { return }
            resizeAnimation.stop()
            onResizeAnimationChange?(true)
            startSize = preferredContentSize
            targetSize = newValue
            if animate && startSize != .zero && startSize != newValue {
                resizeAnimation.currentProgress = 0
                resizeAnimation.start()
            } else {
                resizeAnimation.currentProgress = 1
            }
        }
    }

    private func applyPresentedSize(_ size: NSSize) {
        // Publish only the interpolated size, preventing an automatic jump to
        // the final preferred size before our content-size callback runs.
        super.preferredContentSize = size
        onSizeChange?(size)
    }
}

@MainActor
struct AccessoryPanel: View {
    @ObservedObject var monitor: AccessoryMonitor
    @State private var settingsExpanded = false
    var onSizeChange: ((NSSize) -> Void)? = nil

    var body: some View {
        AccessoryPanelContent(monitor: monitor, settingsExpanded: $settingsExpanded, onSizeChange: onSizeChange)
    }
}

/// Keep outgoing settings alive while the native panel shrinks. The standard
/// disclosure clips them to zero immediately, hiding the closing resize curve.
private struct AccessoryDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onToggle: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notification-settings")
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, 16)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: configuration.isExpanded)
        .transaction { $0.disablesAnimations = false }
    }
}

@MainActor
struct AccessoryPanelContent: View {
    @ObservedObject var monitor: AccessoryMonitor
    @Binding var settingsExpanded: Bool
    var onSizeChange: ((NSSize) -> Void)? = nil

    func toggleSettings(modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.option) && !modifiers.contains(.control) {
            monitor.isDebugModeEnabled = true
            settingsExpanded = true
        } else {
            if !settingsExpanded { monitor.isDebugModeEnabled = false }
            settingsExpanded.toggle()
        }
    }

    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("BTNotify")
                            .font(.title2.bold())
                            .accessibilityIdentifier("panel-title")
                            .accessibilityAddTraits(.isHeader)
                        Text("Your accessories, at a glance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: monitor.refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh accessories")
                    .accessibilityLabel("Refresh accessories")
                }

                ViewThatFits(in: .vertical) {
                    accessoryList.fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        accessoryList
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("accessory-scroll")
                }
                .frame(maxHeight: 280)

                if !monitor.isDebugModeEnabled, let error = monitor.refreshError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                DisclosureGroup("Notification settings", isExpanded: $settingsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Notifications", isOn: $monitor.notificationsEnabled)
                        Toggle("Connection changes", isOn: $monitor.connectionAlertsEnabled)
                            .disabled(!monitor.notificationsEnabled)
                        Toggle("Low battery", isOn: $monitor.batteryAlertsEnabled)
                            .disabled(!monitor.notificationsEnabled)
                        Picker("Alert at", selection: $monitor.lowBatteryThreshold) {
                            ForEach(monitor.availableBatteryThresholds, id: \.self) { threshold in
                                Text("\(threshold)%").tag(threshold)
                            }
                        }
                        .accessibilityLabel("Alert at: low-battery percentage")
                        .disabled(!monitor.notificationsEnabled || !monitor.batteryAlertsEnabled)

                        Toggle("Nag me!", isOn: $monitor.nagMeEnabled)
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("Nag me! Repeat low-battery reminders")
                            .accessibilityHint("Sends a reminder every five minutes while an accessory is low and the Mac is unlocked.")
                            .disabled(!monitor.notificationsEnabled || !monitor.batteryAlertsEnabled)
                        Text("Send a notification every 5 minutes while low.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if monitor.isDebugModeEnabled {
                            Picker("Check time", selection: $monitor.checkIntervalSeconds) {
                                ForEach(AccessoryMonitor.availableCheckIntervals, id: \.self) { seconds in
                                    Text(seconds < 60 ? "\(seconds) seconds" : "\(seconds / 60) min")
                                        .tag(seconds)
                                }
                            }
                            .accessibilityHint("How often accessory battery and connection status are checked. Reminders remain every five minutes.")
                            .accessibilityIdentifier("check-time")
                            Text(monitor.notificationStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Test", action: monitor.sendTestNotification)
                                .help("Send a test notification")
                                .accessibilityLabel("Test notification")
                                .accessibilityIdentifier("test-notification")
                        }
                        if !monitor.notificationsAllowed {
                            Button("Allow Notifications", action: monitor.requestNotifications)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .padding(.top, 10)
                }
                .disclosureGroupStyle(AccessoryDisclosureStyle(onToggle: {
                    toggleSettings(modifiers: NSEvent.modifierFlags)
                }))
                .help("Option-click to show advanced settings")
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

                if monitor.isDebugModeEnabled && settingsExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(monitor.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("provider-status")
                        if let date = monitor.lastUpdated {
                            HStack(spacing: 3) {
                                Text("Updated")
                                Text(date, style: .relative)
                                Text("ago")
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                LaunchAtLoginNotice(launchAtLogin: monitor.launchAtLogin)

                // Reserve its native size while the visible footer follows the
                // animated panel bottom instead of jumping to its target edge.
                footer.hidden().accessibilityHidden(true)
            }
            .padding(18)
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
            // Measure natural content once, independently of the animated window
            // bounds. SwiftUI never receives an interpolated height as state.
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
                onSizeChange?(size)
            }
            // Hold the header at the top while AppKit animates the anchored height.
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
            // Keep outgoing settings above the persistent footer controls.
            // The hidden footer supplies its native height without a size loop.
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    footer.hidden()
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                }
            }
            .overlay(alignment: .bottom) {
                footer.padding(18)
            }
            // Limit SwiftUI transitions to the disclosure. AppKit owns the outer
            // resize, and the footer follows the panel bottom without a delay.
            .transaction {
                $0.animation = nil
                $0.disablesAnimations = true
            }
    }

    private var footer: some View {
        HStack {
            LaunchAtLoginSetting(launchAtLogin: monitor.launchAtLogin)
                .fixedSize()
            Spacer(minLength: 12)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("q")
            .accessibilityLabel("Quit BTNotify")
            .accessibilityIdentifier("panel-quit")
        }
        .controlSize(.small)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accessoryList: some View {
        VStack(spacing: 8) {
            if monitor.accessories.isEmpty {
                ContentUnavailableView("No accessories reported", systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Connect an accessory to check its battery."))
            } else {
                ForEach(monitor.accessories) { accessory in
                    AccessoryRow(accessory: accessory)
                }
            }
        }
    }
}

/// Reads installed artwork through Foundation/AppKit only; no framework code is loaded.
@MainActor
enum SystemDeviceIcons {
    private static let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBluetoothUI.framework")
    private static let assets: [String: [String: Any]] = {
        guard let url = bundle?.url(forResource: "AssetPaths", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: [String: Any]] else { return [:] }
        return table
    }()

    static func image(for accessory: AccessorySnapshot) -> NSImage? {
        if let product = accessory.appleProductID, (0...65535).contains(product) {
            var key = String(format: "0x%04X", product)
            var visited: Set<String> = []
            while visited.insert(key).inserted, let asset = assets[key] {
                if let clone = asset["Clone"] as? String { key = clone; continue }
                let source = (asset["Bundle"] as? String).flatMap(Bundle.init(path:)) ?? bundle
                if let name = asset["ImageName"] as? String,
                   let image = source?.image(forResource: NSImage.Name(name)) { return image }
                break
            }
        }
        let resource: String?
        switch accessory.kind {
        case .keyboard: resource = "Generic-Keyboard.icns"
        case .mouse: resource = "Generic-Mouse.icns"
        case .trackpad: resource = "D67-White.icns"
        case .headphones, .headset: resource = "Generic-Headphones.png"
        case .gameController: resource = "Generic-GameController.png"
        case .airpods: resource = "B188-B288.png"
        case .airpodsPro: resource = "B298.png"
        case .airpodsMax: resource = "B515-0-Black.icns"
        case .stylus, .unknown: resource = nil
        }
        return resource.flatMap { bundle?.image(forResource: NSImage.Name($0)) }
    }
}

private struct AccessoryRow: View {
    let accessory: AccessorySnapshot

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = SystemDeviceIcons.image(for: accessory) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .opacity(accessory.isConnected ? 1 : 0.5)
                } else {
                    Image(systemName: accessory.kind.systemImage)
                        .font(.system(size: 26))
                        .foregroundStyle(accessory.isConnected ? Color.accentColor : Color.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(accessory.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(accessory.isConnected ? (accessory.isCharging ? "Connected · Charging" : "Connected") : "Disconnected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if let percent = accessory.batteryPercent, accessory.isConnected {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(percent)%")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: batterySymbol(percent))
                        .foregroundStyle(accessory.isCharging ? Color.green : (percent <= 20 ? Color.orange : Color.secondary))
                        .accessibilityHidden(true)
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Battery unavailable")
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessory.name)
        .accessibilityValue(accessibilityStatus)
    }

    private var accessibilityStatus: String {
        var parts = [accessory.isConnected ? "Connected" : "Disconnected"]
        if accessory.isConnected && accessory.isCharging { parts.append("Charging") }
        if accessory.isConnected, let percent = accessory.batteryPercent {
            parts.append("Battery \(percent) percent")
        } else {
            parts.append("Battery unavailable")
        }
        return parts.joined(separator: ", ")
    }

    private func batterySymbol(_ percent: Int) -> String {
        if accessory.isCharging { return "battery.100percent.bolt" }
        switch percent {
        case 0..<15: return "battery.0percent"
        case 15..<40: return "battery.25percent"
        case 40..<65: return "battery.50percent"
        case 65..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
