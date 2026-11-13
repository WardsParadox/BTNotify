/// A battery-source observation. A missing connection state stays unknown.
public struct BatteryReading: Sendable, Equatable {
    public let id: String
    public let name: String
    public let accessoryIdentifier: String?
    public let isConnected: Bool?
    public let batteryPercent: Int?
    public let isCharging: Bool
    public let kind: AccessoryKind
    public let appleProductID: Int?

    public init(
        id: String,
        name: String,
        accessoryIdentifier: String?,
        isConnected: Bool?,
        batteryPercent: Int?,
        isCharging: Bool,
        kind: AccessoryKind = .unknown,
        appleProductID: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.accessoryIdentifier = accessoryIdentifier
        self.isConnected = isConnected
        self.batteryPercent = batteryPercent.flatMap { (0...100).contains($0) ? $0 : nil }
        self.isCharging = isCharging
        self.kind = kind
        self.appleProductID = appleProductID
    }
}

public struct AccessoryMerger {
    /// Enriches inventory rows without replacing their connection state or identity.
    /// Name matches must be unique in both sources; competing component readings
    /// remain separate rather than overwriting a single parent device.
    public static func merge(
        inventory: [AccessorySnapshot],
        batteries: [BatteryReading]
    ) -> [AccessorySnapshot] {
        var rows: [AccessorySnapshot] = []
        var rowIndices: [String: Int] = [:]
        for row in inventory {
            if let index = rowIndices[row.id] {
                if !rows[index].isConnected && row.isConnected { rows[index] = row }
            } else {
                rowIndices[row.id] = rows.count
                rows.append(row)
            }
        }

        var readings: [BatteryReading] = []
        var readingIndices: [String: Int] = [:]
        for reading in batteries where !reading.id.isEmpty {
            if let index = readingIndices[reading.id] {
                if readings[index].batteryPercent == nil && reading.batteryPercent != nil {
                    readings[index] = reading
                }
            } else {
                readingIndices[reading.id] = readings.count
                readings.append(reading)
            }
        }

        var addressIndices: [String: [Int]] = [:]
        var nameIndices: [String: [Int]] = [:]
        for (index, row) in rows.enumerated() {
            if let address = address(row.id) { addressIndices[address, default: []].append(index) }
            nameIndices[row.name, default: []].append(index)
        }
        let readingNameCounts = readings.reduce(into: [String: Int]()) { counts, reading in
            counts[reading.name, default: 0] += 1
        }

        // Resolve exact identities before names so a name match cannot consume an
        // inventory row that has a stronger match elsewhere in the same snapshot.
        let exactTargets: [Int?] = readings.map { reading in
            for identifier in [reading.id, reading.accessoryIdentifier].compactMap({ $0 }) {
                if let address = address(identifier),
                   let matches = addressIndices[address], matches.count == 1 {
                    return matches[0]
                }
            }
            return nil
        }
        var targetCounts: [Int: Int] = [:]
        for target in exactTargets.compactMap({ $0 }) { targetCounts[target, default: 0] += 1 }
        var assignedRows: Set<Int> = []
        var assignments: [Int: Int] = [:]
        for (readingIndex, target) in exactTargets.enumerated() {
            guard let target, targetCounts[target] == 1 else { continue }
            assignments[readingIndex] = target
            assignedRows.insert(target)
        }

        for (readingIndex, reading) in readings.enumerated() {
            guard exactTargets[readingIndex] == nil,
                  readingNameCounts[reading.name] == 1,
                  let matches = nameIndices[reading.name], matches.count == 1,
                  !assignedRows.contains(matches[0]) else { continue }
            assignments[readingIndex] = matches[0]
            assignedRows.insert(matches[0])
        }

        for (index, reading) in readings.enumerated() {
            if let rowIndex = assignments[index] {
                let row = rows[rowIndex]
                rows[rowIndex] = AccessorySnapshot(
                    id: row.id, name: row.name, isConnected: row.isConnected,
                    batteryPercent: reading.batteryPercent ?? row.batteryPercent,
                    isCharging: reading.isCharging,
                    kind: row.kind != .unknown ? row.kind :
                        (reading.kind != .unknown ? reading.kind : .identify(name: reading.name)),
                    appleProductID: row.appleProductID ?? reading.appleProductID
                )
            } else if let connected = reading.isConnected {
                let id = "battery:" + reading.id
                guard rowIndices[id] == nil else { continue }
                rowIndices[id] = rows.count
                rows.append(AccessorySnapshot(
                    id: id, name: reading.name, isConnected: connected,
                    batteryPercent: reading.batteryPercent, isCharging: reading.isCharging,
                    kind: reading.kind != .unknown ? reading.kind : .identify(name: reading.name),
                    appleProductID: reading.appleProductID
                ))
            }
        }
        return rows
    }

    private static func address(_ identifier: String) -> String? {
        let candidate = identifier.hasPrefix("bt:") ? String(identifier.dropFirst(3)) : identifier
        return BluetoothAddress.normalized(candidate)
    }
}
