import CoreGraphics
import Foundation

// ── Data types ─────────────────────────────────────────────────────────────────

struct DotConfiguration {
    let dots: [CGPoint]
    let connections: [(Int, Int)]
    let shapeName: String
    // Curve mode geometry (nil for straight-line levels)
    let circleCenter: CGPoint?
    let circleRadius: CGFloat?
    var isCurveMode: Bool { circleCenter != nil }
}

// ── Generator ──────────────────────────────────────────────────────────────────

enum LevelGenerator {

    private static let shapeNames = [
        "Segment",  // 2 dots
        "Triangle", // 3
        "Square",   // 4
        "Pentagon", // 5
        "Hexagon",  // 6
        "Heptagon", // 7
        "Octagon",  // 8
        "Nonagon",  // 9
        "Decagon",  // 10
    ]

    static func shapeName(dotCount: Int) -> String {
        let idx = dotCount - 2
        guard idx >= 0, idx < shapeNames.count else { return "\(dotCount)-gon" }
        return shapeNames[idx]
    }

    /// Build configuration for a given level type and game index.
    static func configuration(levelType: LevelType,
                              dotCount: Int,
                              in size: CGSize,
                              dotRadius: CGFloat,
                              topReserved: CGFloat = 68) -> DotConfiguration {
        if levelType.isCurve {
            return curveConfig(dotCount: dotCount, in: size,
                               dotRadius: dotRadius, topReserved: topReserved)
        } else {
            return lineConfig(dotCount: dotCount, in: size,
                              dotRadius: dotRadius, topReserved: topReserved)
        }
    }

    // ── Straight line configuration ────────────────────────────────────────

    static func lineConfig(dotCount: Int,
                           in size: CGSize,
                           dotRadius: CGFloat,
                           topReserved: CGFloat) -> DotConfiguration {
        let padding = max(dotRadius * 5, 44)
        let usableTop    = topReserved
        let usableHeight = size.height - topReserved
        let cx = size.width / 2
        let cy = usableTop + usableHeight / 2
        let polyRadius = min(size.width, usableHeight) / 2 - padding

        var dots: [CGPoint]
        if dotCount == 2 {
            let offset = polyRadius * 0.80
            dots = [CGPoint(x: cx - offset, y: cy), CGPoint(x: cx + offset, y: cy)]
        } else {
            let startAngle: CGFloat = -.pi / 2
            dots = (0..<dotCount).map { i in
                let angle = startAngle + CGFloat(i) * 2 * .pi / CGFloat(dotCount)
                return CGPoint(x: cx + polyRadius * cos(angle),
                               y: cy + polyRadius * sin(angle))
            }
        }

        let connections: [(Int, Int)] = dotCount == 2
            ? [(0, 1)]
            : (0..<dotCount).map { ($0, ($0 + 1) % dotCount) }

        return DotConfiguration(dots: dots, connections: connections,
                                shapeName: shapeName(dotCount: dotCount),
                                circleCenter: nil, circleRadius: nil)
    }

    // ── Curve (arc) configuration ──────────────────────────────────────────
    // Dots are evenly spaced on a circle. Each connection is the arc between
    // two adjacent dots. The player must trace that arc freehand.

    static func curveConfig(dotCount: Int,
                            in size: CGSize,
                            dotRadius: CGFloat,
                            topReserved: CGFloat) -> DotConfiguration {
        let padding = max(dotRadius * 5, 48)
        let usableTop    = topReserved
        let usableHeight = size.height - topReserved
        let cx = size.width / 2
        let cy = usableTop + usableHeight / 2
        let radius = min(size.width, usableHeight) / 2 - padding

        let startAngle: CGFloat = -.pi / 2
        let dots = (0..<dotCount).map { i -> CGPoint in
            let angle = startAngle + CGFloat(i) * 2 * .pi / CGFloat(dotCount)
            return CGPoint(x: cx + radius * cos(angle),
                           y: cy + radius * sin(angle))
        }

        // For 2-dot curve: just one arc (not closing back)
        let connections: [(Int, Int)] = dotCount == 2
            ? [(0, 1)]
            : (0..<dotCount).map { ($0, ($0 + 1) % dotCount) }

        let arcLabel = dotCount == 2 ? "Arc" : "Circle-\(dotCount)"

        return DotConfiguration(dots: dots, connections: connections,
                                shapeName: arcLabel,
                                circleCenter: CGPoint(x: cx, y: cy),
                                circleRadius: radius)
    }
}
