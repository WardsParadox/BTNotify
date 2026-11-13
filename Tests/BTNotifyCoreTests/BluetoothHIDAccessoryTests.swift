import XCTest
@testable import BTNotifyCore

final class BluetoothHIDAccessoryTests: XCTestCase {
    func testBLEMouseWithoutBluetoothClassHasNativeIdentity() {
        let mouse = BluetoothHIDAccessory(address: "AA:BB:CC:DD:EE:FF",
            transport: "Bluetooth Low Energy", usagePage: 1, usage: 2)
        XCTAssertEqual(mouse?.id, "bt:aabbccddeeff")
        XCTAssertEqual(mouse?.kind, .mouse)
    }

    func testNativeKeyboardAndOtherInputUsages() {
        for (page, usage, kind) in [(1, 6, AccessoryKind.keyboard), (1, 7, .keyboard),
                                   (1, 5, .gameController), (13, 5, .trackpad), (13, 2, .stylus)] {
            XCTAssertEqual(BluetoothHIDAccessory(address: "aa-bb-cc-dd-ee-ff",
                transport: "Bluetooth", usagePage: page, usage: usage)?.kind, kind)
        }
    }

    func testUSBAndVirtualHIDCannotAdmitBluetoothDevices() {
        for transport in ["USB", "SPI", "Virtual", "AirPlay", ""] {
            XCTAssertNil(BluetoothHIDAccessory(address: "AA:BB:CC:DD:EE:FF",
                transport: transport, usagePage: 1, usage: 2))
        }
    }

    func testConsumerControlsAndUnknownUsagesAreExcluded() {
        for (page, usage) in [(12, 1), (1, 0), (0, 0), (0xff00, 1)] {
            XCTAssertNil(BluetoothHIDAccessory(address: "AA:BB:CC:DD:EE:FF",
                transport: "Bluetooth", usagePage: page, usage: usage))
        }
    }

    func testMissingIdentityOrUsageCannotInventAnAccessory() {
        XCTAssertNil(BluetoothHIDAccessory(address: nil, transport: "Bluetooth", usagePage: 1, usage: 2))
        XCTAssertNil(BluetoothHIDAccessory(address: "Not an address", transport: "Bluetooth", usagePage: 1, usage: 2))
        XCTAssertNil(BluetoothHIDAccessory(address: "AA:BB:CC:DD:EE:FF", transport: "Bluetooth", usagePage: nil, usage: 2))
    }
}
