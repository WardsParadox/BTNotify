/// Native HID evidence for a Bluetooth input device whose Bluetooth class may
/// be missing. Product names never establish eligibility or battery readings.
public struct BluetoothHIDAccessory: Equatable, Sendable {
    public let id: String
    public let kind: AccessoryKind

    public init?(address: String?, transport: String?, usagePage: Int?, usage: Int?) {
        guard let address, let normalized = BluetoothAddress.normalized(address),
              let transport, ["bluetooth", "bluetooth low energy"].contains(transport.lowercased()),
              let usagePage, let usage else { return nil }
        switch (usagePage, usage) {
        case (0x01, 0x02): kind = .mouse
        case (0x01, 0x06), (0x01, 0x07): kind = .keyboard
        case (0x01, 0x04), (0x01, 0x05): kind = .gameController
        case (0x0d, 0x05): kind = .trackpad
        case (0x0d, 0x02): kind = .stylus
        default: return nil
        }
        id = "bt:" + normalized
    }
}
