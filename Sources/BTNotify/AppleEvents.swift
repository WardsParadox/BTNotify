import AppKit
import BTNotifyCore

/// Native, read-only scripting commands. Standard launch and quit events remain
/// with NSApplication; these handlers never activate or open the accessory panel.
@MainActor
final class AccessoryAppleEvents: NSObject {
    static let eventClass: AEEventClass = 0x42544E74 // BTNt
    static let statusEvent: AEEventID = 0x73746174 // stat
    static let refreshEvent: AEEventID = 0x72667368 // rfsh
    static let missingValueType: OSType = 0x6D736E67 // msng (AppleScript missing value)

    private let readings: () -> [AccessorySnapshot]
    private let refresh: () -> Void

    init(readings: @escaping () -> [AccessorySnapshot], refresh: @escaping () -> Void) {
        self.readings = readings
        self.refresh = refresh
        super.init()
    }

    func install() {
        let manager = NSAppleEventManager.shared()
        for eventID in [Self.statusEvent, Self.refreshEvent] {
            manager.setEventHandler(self, andSelector: #selector(handle(_:withReplyEvent:)),
                forEventClass: Self.eventClass, andEventID: eventID)
        }
    }

    func uninstall() {
        let manager = NSAppleEventManager.shared()
        for eventID in [Self.statusEvent, Self.refreshEvent] {
            manager.removeEventHandler(forEventClass: Self.eventClass, andEventID: eventID)
        }
    }

    @objc func handle(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        if event.eventID == Self.refreshEvent { refresh() }
        guard reply.descriptorType != typeNull else { return }
        reply.setParam(Self.descriptor(for: readings()), forKeyword: keyDirectObject)
    }

    static func descriptor(for accessories: [AccessorySnapshot]) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (index, accessory) in accessories.enumerated() {
            let record = NSAppleEventDescriptor.record()
            record.setDescriptor(NSAppleEventDescriptor(typeCode: 0x42546163), forKeyword: keyAEObjectClass) // BTac
            record.setDescriptor(NSAppleEventDescriptor(string: accessory.id), forKeyword: 0x49442020) // "ID  "
            record.setDescriptor(NSAppleEventDescriptor(string: accessory.name), forKeyword: 0x706E616D) // pnam
            record.setDescriptor(NSAppleEventDescriptor(boolean: accessory.isConnected), forKeyword: 0x4254636E) // BTcn
            record.setDescriptor(accessory.batteryPercent.map { NSAppleEventDescriptor(int32: Int32($0)) }
                ?? NSAppleEventDescriptor(typeCode: missingValueType), forKeyword: 0x4254626C) // BTbl
            record.setDescriptor(NSAppleEventDescriptor(boolean: accessory.isCharging), forKeyword: 0x42546368) // BTch
            record.setDescriptor(NSAppleEventDescriptor(string: accessory.kind.rawValue), forKeyword: 0x42546B64) // BTkd
            list.insert(record, at: index + 1)
        }
        return list
    }
}
