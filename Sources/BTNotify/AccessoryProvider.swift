import BTNotifyCore
import Foundation
import IOBluetooth
import IOKit.hid
import IOKit.ps

/// Calls the same powerd API as the original battery wrapper. Bluetooth supplies
/// connection state only; it is never the source of battery percentages.
enum AccessoryPowerSources {
    private typealias CopySources = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    static func read() throws -> [BatteryReading] {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOPSCopyPowerSourcesByType") else {
            throw ReadError.unavailable
        }
        let copySources = unsafeBitCast(symbol, to: CopySources.self)
        guard let blob = copySources(4)?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [AnyObject] else {
            throw ReadError.unavailable
        }
        return sources.compactMap { source in
            guard let values = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let transport = values["Transport Type"] as? String,
                  ["Bluetooth", "Bluetooth LE"].contains(transport) else { return nil }
            let accessoryID = values["Accessory Identifier"] as? String
            let sourceID = (values["Power Source ID"] as? NSNumber)?.stringValue
            guard let identity = accessoryID ?? sourceID else { return nil }
            let partID = (values["Part Identifier"] as? String)
                ?? (values["Part Identifier"] as? NSNumber)?.stringValue
            let name = values["Name"] as? String ?? "Bluetooth accessory"
            let partName = values["Part Name"] as? String
            let current = (values["Current Capacity"] as? NSNumber)?.doubleValue
            let maximum = (values["Max Capacity"] as? NSNumber)?.doubleValue
            let vendor = (values["Vendor ID"] as? NSNumber)?.intValue
            let vendorSource = (values["Vendor ID Source"] as? NSNumber)?.intValue
            let isApple = (vendorSource == 1 && vendor == 76) || (vendorSource == 2 && vendor == 1452)
            let product = (values["Product ID"] as? NSNumber)?.intValue
            var percent: Int?
            if let current, let maximum, current.isFinite, maximum.isFinite,
               maximum > 0, current >= 0, current <= maximum {
                percent = Int((100 * current / maximum).rounded())
            }
            return BatteryReading(id: "iops:" + identity + (partID.map { ":" + $0 } ?? ""),
                name: partName.map { name + " · " + $0 } ?? name,
                accessoryIdentifier: accessoryID,
                isConnected: (values["Is Present"] as? NSNumber)?.boolValue,
                batteryPercent: percent,
                isCharging: (values["Is Charging"] as? NSNumber)?.boolValue ?? false,
                kind: .identify(name: name, category: values["Accessory Category"] as? String),
                appleProductID: isApple ? product : nil)
        }
    }

    enum ReadError: LocalizedError {
        case unavailable
        var errorDescription: String? { "macOS accessory battery readings are unavailable." }
    }
}

@MainActor
final class AccessoryProvider {
    private(set) var batteryStatus = "Waiting for accessory batteries."
    private(set) var inventoryCount = 0
    private(set) var batteryCount = 0
    private(set) var batteryError: String?
    private var recognizedIDs: Set<String> = []
    private let defaults: UserDefaults
    private var knownHIDKinds: [String: AccessoryKind]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: "knownBluetoothHIDKinds") as? [String: String] ?? [:]
        knownHIDKinds = saved.reduce(into: [:]) { result, entry in
            guard entry.key.hasPrefix("bt:"),
                  BluetoothAddress.normalized(String(entry.key.dropFirst(3))) != nil,
                  let kind = AccessoryKind(rawValue: entry.value),
                  [.keyboard, .mouse, .trackpad, .gameController, .stylus].contains(kind) else { return }
            result[entry.key] = kind
        }
    }

    private func connectedHIDKinds() -> [String: AccessoryKind] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, nil)
        var result: [String: AccessoryKind] = [:]
        // Enumerate properties only: never open devices or register input callbacks.
        for device in IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [] {
            guard let accessory = BluetoothHIDAccessory(
                address: IOHIDDeviceGetProperty(device, "DeviceAddress" as CFString) as? String,
                transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String,
                usagePage: (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue,
                usage: (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue
            ) else { continue }
            // Composite mice can also expose a keyboard interface. Prefer the
            // pointing-device usage, and preserve an explicit trackpad usage.
            if result[accessory.id] == nil || accessory.kind == .trackpad ||
                (accessory.kind == .mouse && result[accessory.id] == .keyboard) {
                result[accessory.id] = accessory.kind
            }
        }
        return result
    }

    func read() throws -> [AccessorySnapshot] {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let connectedHID = connectedHIDKinds()
        let updatedKinds = knownHIDKinds.merging(connectedHID) { _, new in new }
        if updatedKinds != knownHIDKinds {
            knownHIDKinds = updatedKinds
            defaults.set(knownHIDKinds.mapValues(\.rawValue), forKey: "knownBluetoothHIDKinds")
        }
        recognizedIDs.formUnion(knownHIDKinds.keys)
        inventoryCount = devices.count
        let batteries: [BatteryReading]
        do {
            batteries = try AccessoryPowerSources.read()
            batteryStatus = "Reading Bluetooth accessory batteries from macOS power sources."
            batteryError = nil
        } catch {
            batteries = []
            batteryStatus = error.localizedDescription
            batteryError = error.localizedDescription
        }
        batteryCount = batteries.count
        let inventory = devices.compactMap { device -> AccessorySnapshot? in
            guard let address = device.addressString,
                  let normalized = BluetoothAddress.normalized(address) else { return nil }
            let id = "bt:" + normalized
            // Class 5 is a peripheral; audio minors 1, 2, 6 identify headsets,
            // hands-free devices, and headphones. Media receivers are excluded.
            if device.deviceClassMajor == 5 ||
                (device.deviceClassMajor == 4 && [1, 2, 6].contains(device.deviceClassMinor)) {
                recognizedIDs.insert(id)
            }
            let name = device.nameOrAddress ?? "Accessory"
            let displayKind = AccessoryKind.identify(majorClass: Int(device.deviceClassMajor),
                minorClass: Int(device.deviceClassMinor), name: name)
            return AccessorySnapshot(id: id, name: name,
                isConnected: device.isConnected() || connectedHID[id] != nil, batteryPercent: nil, isCharging: false,
                kind: device.deviceClassMajor == 0 ? (knownHIDKinds[id] ?? displayKind) : displayKind)
        }
        let merged = AccessoryMerger.merge(inventory: inventory, batteries: batteries)
        for accessory in merged where accessory.batteryPercent != nil { recognizedIDs.insert(accessory.id) }
        return merged.filter { recognizedIDs.contains($0.id) }.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
