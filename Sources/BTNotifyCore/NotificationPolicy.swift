/// Converts complete or partial observations into deduplicated notification events.
/// Absence from a snapshot never proves disconnection: only an explicit state does.
public struct NotificationPolicy: Sendable {
    public let lowBatteryThreshold: Int
    private var connections: [String: Bool] = [:]
    private var lowBatteryNotified: Set<String> = []
    private var needsBaseline = true

    public init(lowBatteryThreshold: Int = 20) {
        self.lowBatteryThreshold = min(100, max(1, lowBatteryThreshold))
    }

    /// Silences connection transitions in the next observation after wake or failure.
    /// Existing battery alerts remain latched to avoid repeating alerts after recovery.
    public mutating func resetBaseline() {
        connections.removeAll()
        needsBaseline = true
    }

    /// Initial connection state is silent. An already-low, connected accessory alerts once.
    public mutating func process(_ accessories: [AccessorySnapshot]) -> [AccessoryEvent] {
        var events: [AccessoryEvent] = []
        for accessory in accessories {
            if !needsBaseline {
                let previous = connections[accessory.id]
                if previous != accessory.isConnected,
                   previous != nil || accessory.isConnected {
                    events.append(event(accessory, accessory.isConnected ? .connected : .disconnected))
                }
            }
            connections[accessory.id] = accessory.isConnected

            guard accessory.isConnected,
                  let percent = accessory.batteryPercent,
                  (0...100).contains(percent) else { continue }

            if percent > lowBatteryThreshold && percent >= min(100, lowBatteryThreshold + 5) {
                lowBatteryNotified.remove(accessory.id)
            }
            if percent <= lowBatteryThreshold,
               !accessory.isCharging,
               lowBatteryNotified.insert(accessory.id).inserted {
                events.append(event(accessory, .lowBattery))
            }
        }
        needsBaseline = false
        return events
    }

    private func event(_ accessory: AccessorySnapshot, _ kind: AccessoryEvent.Kind) -> AccessoryEvent {
        AccessoryEvent(
            accessoryID: accessory.id,
            name: accessory.name,
            kind: kind,
            batteryPercent: accessory.batteryPercent
        )
    }
}
