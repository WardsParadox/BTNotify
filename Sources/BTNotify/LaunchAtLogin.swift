import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?

    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        status = readStatus()
    }

    var isRequested: Bool { status == .enabled || status == .requiresApproval }

    func refreshStatus() {
        status = readStatus()
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        refreshStatus()
        guard enabled != isRequested else { return }
        do {
            if enabled { try register() } else { try unregister() }
        } catch {
            errorMessage = "Couldn’t update launch at login: \(error.localizedDescription)"
        }
        // The system owns this preference, including consent revoked elsewhere.
        refreshStatus()
    }
}

struct LaunchAtLoginSetting: View {
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { launchAtLogin.isRequested }, set: { launchAtLogin.setEnabled($0) }))
            .toggleStyle(.checkbox)
            .help(launchAtLogin.status == .notFound
                ? "Move BTNotify to Applications before enabling launch at login."
                : "Start BTNotify automatically when you log in.")
            .accessibilityHint("Starts BTNotify automatically when you log in to this Mac.")
            .accessibilityIdentifier("launch-at-login")
            .onAppear { launchAtLogin.refreshStatus() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                launchAtLogin.refreshStatus()
            }
    }
}

struct LaunchAtLoginNotice: View {
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        if launchAtLogin.status == .requiresApproval || launchAtLogin.errorMessage != nil {
            VStack(alignment: .leading, spacing: 6) {
                if launchAtLogin.status == .requiresApproval {
                    Text("Allow BTNotify in Login Items to launch automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }

                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .controlSize(.small)
        }
    }
}
