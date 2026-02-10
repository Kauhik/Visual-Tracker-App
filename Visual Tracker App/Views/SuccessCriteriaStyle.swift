import SwiftUI

enum SuccessCriteriaStyle {
    static let badgeTextColor: Color = Color.white.opacity(0.97)

    private static let fixedColors: [String: Color] = [
        "A": Color(.sRGB, red: 0.28, green: 0.53, blue: 0.94, opacity: 1.0),
        "B": Color(.sRGB, red: 0.24, green: 0.70, blue: 0.52, opacity: 1.0),
        "C": Color(.sRGB, red: 0.88, green: 0.56, blue: 0.30, opacity: 1.0),
        "D": Color(.sRGB, red: 0.62, green: 0.45, blue: 0.88, opacity: 1.0),
        "E": Color(.sRGB, red: 0.85, green: 0.41, blue: 0.64, opacity: 1.0)
    ]

    private static let palette: [Color] = [
        Color(.sRGB, red: 0.28, green: 0.53, blue: 0.94, opacity: 1.0),
        Color(.sRGB, red: 0.24, green: 0.70, blue: 0.52, opacity: 1.0),
        Color(.sRGB, red: 0.88, green: 0.56, blue: 0.30, opacity: 1.0),
        Color(.sRGB, red: 0.62, green: 0.45, blue: 0.88, opacity: 1.0),
        Color(.sRGB, red: 0.85, green: 0.41, blue: 0.64, opacity: 1.0),
        Color(.sRGB, red: 0.20, green: 0.67, blue: 0.71, opacity: 1.0),
        Color(.sRGB, red: 0.76, green: 0.48, blue: 0.34, opacity: 1.0),
        Color(.sRGB, red: 0.49, green: 0.62, blue: 0.84, opacity: 1.0),
        Color(.sRGB, red: 0.63, green: 0.53, blue: 0.36, opacity: 1.0),
        Color(.sRGB, red: 0.55, green: 0.52, blue: 0.80, opacity: 1.0)
    ]

    static func color(for code: String) -> Color {
        let normalizedCode = normalize(code)
        guard normalizedCode.isEmpty == false else { return palette[0] }

        if let fixed = fixedColors[normalizedCode] {
            return fixed
        }

        let index = Int(stableHash(normalizedCode) % UInt64(palette.count))
        return palette[index]
    }

    static func subtleFill(for code: String, isHovered: Bool = false) -> Color {
        color(for: code).opacity(isHovered ? 0.17 : 0.10)
    }

    static func badgeGradient(for code: String) -> LinearGradient {
        let base = color(for: code)
        return LinearGradient(
            colors: [
                base.opacity(0.94),
                base.opacity(0.74)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for scalar in value.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* 1099511628211
        }
        return hash
    }
}

struct SuccessCriteriaBadge: View {
    let code: String
    var font: Font = .system(.body, design: .rounded)
    var fontWeight: Font.Weight = .bold
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 4
    var cornerRadius: CGFloat = 8
    var minWidth: CGFloat? = nil

    private var displayCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var body: some View {
        Text(displayCode)
            .font(font)
            .fontWeight(fontWeight)
            .foregroundColor(SuccessCriteriaStyle.badgeTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: minWidth, alignment: .center)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(SuccessCriteriaStyle.badgeGradient(for: displayCode))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SuccessCriteriaStyle.color(for: displayCode).opacity(0.60), lineWidth: 1)
            )
    }
}
