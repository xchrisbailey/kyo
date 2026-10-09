import UIKit

/// A color as red, green, blue and alpha, for measuring contrast the way WCAG defines it.
struct RGBA {
    var red: Double, green: Double, blue: Double, alpha: Double

    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        (red, green, blue, alpha) = (r, g, b, a)
    }

    /// This color drawn at `alpha` of its own strength.
    func applying(alpha factor: Double) -> RGBA {
        var result = self
        result.alpha *= factor
        return result
    }

    /// The opaque color this one makes when drawn over `back`.
    func blended(over back: RGBA) -> RGBA {
        var result = self
        result.red = back.red + (red - back.red) * alpha
        result.green = back.green + (green - back.green) * alpha
        result.blue = back.blue + (blue - back.blue) * alpha
        result.alpha = 1
        return result
    }

    /// WCAG relative luminance of an opaque color.
    var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two opaque colors.
    static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let (high, low) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (high + 0.05) / (low + 0.05)
    }
}
