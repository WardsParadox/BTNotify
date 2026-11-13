import AppKit
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let panels = windows.filter { ($0[kCGWindowOwnerName as String] as? String) == "BTNotify" }
var visible = false
for panel in panels {
    guard let bounds = panel[kCGWindowBounds as String] as? [String: NSNumber] else { continue }
    let width = bounds["Width"]?.doubleValue ?? 0
    let height = bounds["Height"]?.doubleValue ?? 0
    let layer = panel[kCGWindowLayer as String] as? Int ?? 0
    print("BTNotify window: \(Int(width))×\(Int(height)), layer \(layer)")
    if width >= 300 && height >= 200 { visible = true }
}
if !visible {
    print("FAIL: no visible accessory panel at least 300×200")
    exit(1)
}
print("PASS: accessory panel has usable dimensions")
