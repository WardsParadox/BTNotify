import Foundation
import IOBluetooth

for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
    print("\(device.nameOrAddress ?? "Accessory"): connected=\(device.isConnected()), major=\(device.deviceClassMajor), minor=\(device.deviceClassMinor)")
}
