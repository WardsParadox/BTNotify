import Foundation

public struct AccessorySnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let isConnected: Bool
    public let batteryPercent: Int?
    public let isCharging: Bool
    public let kind: AccessoryKind
    public let appleProductID: Int?

    public init(
        id: String,
        name: String,
        isConnected: Bool,
        batteryPercent: Int?,
        isCharging: Bool,
        kind: AccessoryKind = .unknown,
        appleProductID: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.isConnected = isConnected
        self.batteryPercent = batteryPercent.flatMap { (0...100).contains($0) ? $0 : nil }
        self.isCharging = isCharging
        self.kind = kind
        self.appleProductID = appleProductID
    }
}

public struct AccessoryEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case connected
        case disconnected
        case lowBattery
    }

    public let accessoryID: String
    public let name: String
    public let kind: Kind
    public let batteryPercent: Int?

    public init(accessoryID: String, name: String, kind: Kind, batteryPercent: Int?) {
        self.accessoryID = accessoryID
        self.name = name
        self.kind = kind
        self.batteryPercent = batteryPercent
    }
}
