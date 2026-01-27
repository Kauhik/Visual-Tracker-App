import SwiftUI

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6 else { return nil }

        let rString = String(cleaned.prefix(2))
        let gString = String(cleaned.dropFirst(2).prefix(2))
        let bString = String(cleaned.dropFirst(4).prefix(2))

        guard
            let r = UInt8(rString, radix: 16),
            let g = UInt8(gString, radix: 16),
            let b = UInt8(bString, radix: 16)
        else { return nil }

        self = Color(.sRGB, red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0, opacity: 1.0)
    }
}