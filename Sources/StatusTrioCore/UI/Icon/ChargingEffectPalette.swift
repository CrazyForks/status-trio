import CoreGraphics
import Foundation

enum ChargingEffectPalette {
    static let minimumContrastRatio = 1.8
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpaceCreateDeviceRGB()

    static func automaticHighlight(for fillColor: CGColor) -> CGColor {
        guard let base = components(of: fillColor) else {
            return CGColor(
                colorSpace: sRGBColorSpace,
                components: [1, 1, 1, 1]
            ) ?? CGColor(gray: 1, alpha: 1)
        }

        let white = RGB(red: 1, green: 1, blue: 1)
        if contrastRatio(between: base, and: white) >= minimumContrastRatio {
            return contrastingMix(from: base, toward: white)
        }

        let black = RGB(red: 0, green: 0, blue: 0)
        if contrastRatio(between: base, and: black) >= minimumContrastRatio {
            return contrastingMix(from: base, toward: black)
        }

        let destination = contrastRatio(between: base, and: white)
            >= contrastRatio(between: base, and: black)
            ? white
            : black
        return contrastingMix(from: base, toward: destination)
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double
    }

    private static func components(of color: CGColor) -> RGB? {
        guard let converted = color.converted(
            to: sRGBColorSpace,
            intent: .defaultIntent,
            options: nil
        ), let values = converted.components, values.count >= 3 else {
            return nil
        }
        return RGB(
            red: min(1, max(0, Double(values[0]))),
            green: min(1, max(0, Double(values[1]))),
            blue: min(1, max(0, Double(values[2])))
        )
    }

    private static func contrastingMix(from base: RGB, toward destination: RGB) -> CGColor {
        var low = 0.0
        var high = 1.0
        for _ in 0..<32 {
            let midpoint = (low + high) / 2
            let mixed = mix(base, destination, amount: midpoint)
            if contrastRatio(between: base, and: mixed) >= minimumContrastRatio {
                high = midpoint
            } else {
                low = midpoint
            }
        }
        let result = mix(base, destination, amount: high)
        let values: [CGFloat] = [
            CGFloat(result.red),
            CGFloat(result.green),
            CGFloat(result.blue),
            1
        ]
        return CGColor(colorSpace: sRGBColorSpace, components: values)
            ?? CGColor(gray: 1, alpha: 1)
    }

    private static func mix(_ start: RGB, _ end: RGB, amount: Double) -> RGB {
        RGB(
            red: start.red + (end.red - start.red) * amount,
            green: start.green + (end.green - start.green) * amount,
            blue: start.blue + (end.blue - start.blue) * amount
        )
    }

    private static func contrastRatio(between first: RGB, and second: RGB) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private static func relativeLuminance(_ color: RGB) -> Double {
        func linearize(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(color.red)
            + 0.7152 * linearize(color.green)
            + 0.0722 * linearize(color.blue)
    }
}
