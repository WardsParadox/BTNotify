import XCTest
@testable import BTNotifyCore

final class BluetoothAddressTests: XCTestCase {
    func testAddressNormalizationRejectsInvalidIdentities() {
        XCTAssertEqual(BluetoothAddress.normalized("AA:bb:CC:dd:EE:ff"), "aabbccddeeff")
        XCTAssertEqual(BluetoothAddress.normalized("AA-BB-CC-DD-EE-FF"), "aabbccddeeff")
        XCTAssertEqual(BluetoothAddress.normalized("aabbccddeeff"), "aabbccddeeff")
        for address in ["", "123", "GG:BB:CC:DD:EE:FF", "AA:BB:CC:DD:EE:FFF", " AA:BB:CC:DD:EE:FF"] {
            XCTAssertNil(BluetoothAddress.normalized(address))
        }
    }
}
