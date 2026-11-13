import Foundation

public enum BluetoothAddress {
    /// Twelve lowercase hexadecimal digits, independent of separator style.
    public static func normalized(_ address: String) -> String? {
        let normalized = address.lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard normalized.utf8.count == 12,
              normalized.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return normalized
    }
}
