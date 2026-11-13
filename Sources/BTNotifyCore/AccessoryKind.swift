/// Display classifications. A product-name match never establishes accessory eligibility.
public enum AccessoryKind: String, Codable, CaseIterable, Sendable {
    case keyboard, mouse, trackpad, headphones, headset, gameController, stylus
    case airpods, airpodsPro, airpodsMax, unknown

    public var systemImage: String {
        switch self {
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .headphones: "headphones"
        case .headset: "headset"
        case .gameController: "gamecontroller"
        case .stylus: "pencil.tip"
        case .airpods: "airpods"
        case .airpodsPro: "airpodspro"
        case .airpodsMax: "airpodsmax"
        case .unknown: "antenna.radiowaves.left.and.right"
        }
    }

    public static func identify(majorClass: Int = 0, minorClass: Int = 0, name: String, category: String? = nil) -> Self {
        let name = name.lowercased()
        if majorClass == 5 {
            // Peripheral keyboard/pointing flags occupy bits 4–5, independently
            // of the low-nibble subtype (BluetoothAssignedNumbers.h).
            if minorClass & 0x10 != 0 { return .keyboard }
            if minorClass & 0x20 != 0 { return name.contains("trackpad") ? .trackpad : .mouse }
            switch minorClass & 0x0f {
            case 1, 2: return .gameController
            case 7: return .stylus
            default: break
            }
        } else if majorClass == 4 {
            guard [1, 2, 6].contains(minorClass) else { return .unknown }
            if let airpods = airpods(named: name) { return airpods }
            return minorClass == 6 ? .headphones : .headset
        } else if majorClass != 0 {
            return .unknown
        }
        if let category = category?.lowercased() {
            switch category {
            case "keyboard": return .keyboard
            case "mouse": return .mouse
            case "trackpad": return .trackpad
            case "headphones", "earbuds": return airpods(named: name) ?? .headphones
            case "headset": return airpods(named: name) ?? .headset
            case "gamecontroller": return .gameController
            default: break
            }
        }
        // BLE devices often omit a class. Recognizable product names refine
        // their presentation only; an arbitrary name can never admit a device.
        if let airpods = airpods(named: name) { return airpods }
        if name.contains("trackpad") { return .trackpad }
        if name.contains("keyboard") { return .keyboard }
        if name.contains("mouse") { return .mouse }
        if name.contains("headphones") { return .headphones }
        if name.contains("headset") { return .headset }
        return .unknown
    }

    private static func airpods(named name: String) -> Self? {
        guard name.contains("airpods") else { return nil }
        if name.contains("pro") { return .airpodsPro }
        if name.contains("max") { return .airpodsMax }
        return .airpods
    }
}
