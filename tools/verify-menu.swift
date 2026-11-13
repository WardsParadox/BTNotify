import AppKit
import ApplicationServices
import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): return message } }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

func descendants(_ element: AXUIElement) -> [AXUIElement] {
    let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return [element] + children.flatMap(descendants)
}

func role(_ element: AXUIElement) -> String { attribute(element, kAXRoleAttribute) as? String ?? "" }
func identifier(_ element: AXUIElement) -> String { attribute(element, kAXIdentifierAttribute) as? String ?? "" }

func frame(_ element: AXUIElement) -> CGRect {
    var position = CGPoint.zero
    var size = CGSize.zero
    if let value = attribute(element, kAXPositionAttribute) { AXValueGetValue(value as! AXValue, .cgPoint, &position) }
    if let value = attribute(element, kAXSizeAttribute) { AXValueGetValue(value as! AXValue, .cgSize, &size) }
    return CGRect(origin: position, size: size)
}

func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.35)) }

func press(_ element: AXUIElement) throws {
    guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
        throw CheckFailure.failed("Cannot activate native accessibility element: \(role(element))")
    }
    settle()
}

func require(_ value: Bool, _ message: String) throws {
    if !value { throw CheckFailure.failed(message) }
}

do {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "local.btnotify.app").first else {
        throw CheckFailure.failed("BTNotify is not running")
    }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    guard let statusBar = (attribute(root, kAXChildrenAttribute) as? [AXUIElement])?.last(where: { role($0) == kAXMenuBarRole }),
          let statusItem = (attribute(statusBar, kAXChildrenAttribute) as? [AXUIElement])?.first else {
        throw CheckFailure.failed("Cannot inspect status item; check Accessibility permission")
    }
    func panel() -> AXUIElement? { descendants(statusBar).first { role($0) == "AXPopover" } }
    func open(debug: Bool) throws {
        if panel() != nil { try press(statusItem) }
        if debug {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x3A, keyDown: true)
            event?.type = .flagsChanged
            event?.flags = .maskAlternate
            event?.post(tap: .cghidEventTap)
            settle()
        }
        defer {
            if debug {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x3A, keyDown: false)
                event?.type = .flagsChanged
                event?.flags = []
                event?.post(tap: .cghidEventTap)
                settle()
            }
        }
        try press(statusItem)
        try require(panel() != nil, "Status item did not open a popover")
    }
    func assertBounds(expanded: Bool) throws -> CGFloat {
        guard let panel = panel() else { throw CheckFailure.failed("Popover disappeared") }
        let bounds = frame(panel)
        let elements = descendants(panel)
        for id in ["panel-title", "panel-quit"] + (expanded ? ["test-notification"] : []) {
            guard let element = elements.first(where: { identifier($0) == id }) else {
                throw CheckFailure.failed("Missing visible control: \(id)")
            }
            let rect = frame(element)
            try require(rect.minY >= bounds.minY + 5 && rect.maxY <= bounds.maxY - 5,
                "\(id) clipped: control=\(rect), popover=\(bounds)")
            if id == "panel-title" {
                try require(rect.minY - bounds.minY < 45, "Extra whitespace above header")
            }
        }
        return bounds.height
    }
    try open(debug: false)
    if CommandLine.arguments.contains("--point-title"),
       let title = descendants(panel()!).first(where: { identifier($0) == "panel-title" }) {
        let bounds = frame(title)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: bounds.midX, y: bounds.midY), mouseButton: .left)?.post(tap: .cghidEventTap)
        print("Positioned Accessibility Inspector over BTNotify's title")
        exit(0)
    }
    if CommandLine.arguments.contains("--dump") {
        for element in descendants(panel()!) {
            print("\(role(element)) id=\(identifier(element)) frame=\(frame(element)) value=\(attribute(element, kAXValueAttribute) ?? "" as CFString)")
        }
        exit(0)
    }
    for cycle in 1...3 {
        guard let disclosure = descendants(panel()!).first(where: { role($0) == kAXDisclosureTriangleRole }) else {
            throw CheckFailure.failed("Settings disclosure is missing")
        }
        if (attribute(disclosure, kAXValueAttribute) as? NSNumber)?.boolValue == true { try press(disclosure) }
        let collapsed = try assertBounds(expanded: false)
        try press(disclosure)
        let expanded = try assertBounds(expanded: true)
        try require(expanded > collapsed + 20, "Settings did not grow the panel")
        try press(disclosure)
        let restored = try assertBounds(expanded: false)
        print("Measured cycle \(cycle): \(Int(collapsed)) → \(Int(expanded)) → \(Int(restored))")
        try require(abs(collapsed - restored) <= 12, "Collapsed size drifted between cycles")
        print("PASS cycle \(cycle): \(Int(collapsed)) → \(Int(expanded)) → \(Int(restored)); header and footer visible")
    }
    for debug in [false, true, false] {
        try open(debug: debug)
        let elements = descendants(panel()!)
        let sourceVisible = elements.contains { identifier($0) == "provider-status" }
        let counterVisible = elements.contains { (attribute($0, kAXValueAttribute) as? String) == "Updated" }
        try require(sourceVisible == debug && counterVisible == debug,
            "Debug visibility: expected=\(debug), source=\(sourceVisible), counter=\(counterVisible)")
        _ = try assertBounds(expanded: false)
    }
    print("PASS: source label and counter appear only on Option-opening")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
