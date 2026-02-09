import SwiftUI

@Observable
final class ZoomManager {
    var scale: Double {
        didSet {
            UserDefaults.standard.set(scale, forKey: "appZoomScale")
        }
    }

    private let minScale: Double = 0.8
    private let maxScale: Double = 1.4
    private let step: Double = 0.1

    init() {
        let stored = UserDefaults.standard.double(forKey: "appZoomScale")
        self.scale = stored > 0 ? min(1.4, max(0.8, stored)) : 1.0
    }

    func zoomIn() {
        scale = min(maxScale, scale + step)
    }

    func zoomOut() {
        scale = max(minScale, scale - step)
    }

    func reset() {
        scale = 1.0
    }

    /// Scale an explicit CGFloat value (font size, frame dimension, padding, etc.)
    func scaled(_ value: CGFloat) -> CGFloat {
        value * CGFloat(scale)
    }

    /// Map current scale to a DynamicTypeSize for semantic fonts (.body, .headline, .caption, etc.)
    var dynamicTypeSize: DynamicTypeSize {
        switch scale {
        case ..<0.85: return .xSmall
        case ..<0.95: return .small
        case ..<1.05: return .medium
        case ..<1.15: return .large
        case ..<1.25: return .xLarge
        case ..<1.35: return .xxLarge
        default: return .xxxLarge
        }
    }

    /// Convenience: return a scaled system font for hardcoded sizes
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * CGFloat(scale), weight: weight, design: design)
    }
}