# Draft: BatteryCenter controller omits a Bluetooth LE accessory visible to power sources

Status: candidate Apple feedback report; not submitted. Incorrect battery percentages have **not** been reproduced.

Environment: macOS 27.2 (26B123), Apple silicon. A connected Bluetooth LE keyboard reports a battery through the accessory power-source list.

Observed:

1. `BCBatteryDeviceController.connectedDevices` and its observer returned an empty list in a standalone process, both inside and outside the agent sandbox.
2. `IOPSCopyPowerSourcesByType(4)` returned the keyboard with current capacity 53 and maximum capacity 100 in the later comparison; earlier investigation recorded 54%.
3. BatteryCenter's private source-to-device conversion accepted the power-source descriptions.
4. The original Objective-C battery reader and its Swift replacement returned the same 53% in the same comparison. The Swift reader calls the same API and applies the same capacity validation.
5. Native `IOBluetoothDevice.pairedDevices()` correctly returned the keyboard's connected state. The application does not obtain battery percentages from Bluetooth.

Expected: clarify whether a standalone BatteryCenter controller is supported and what initialization or entitlement conditions are required to enumerate the same accessory sources.

Limits: BatteryCenter and the accessory power-source entry point are private APIs. An empty result may reflect unsupported standalone use rather than an OS defect. A Bluetooth LE device's lack of a classic Bluetooth class is also not evidence of an incorrect battery percentage. No entitlement cause or wrong-percentage behavior has been established.

Reproduction and retained evidence: [INVESTIGATION.md](INVESTIGATION.md), `tools/probe-power-sources.m`, and the redacted power-source logs. Do not file this as an incorrect-percentage bug without capturing the exact API, returned value, and simultaneous power-source reading that demonstrate the discrepancy.
