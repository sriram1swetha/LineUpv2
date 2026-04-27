import CoreGraphics
import Foundation

// ── Dot configuration ──────────────────────────────────────────────────────────

struct DotConfiguration {
    let dots: [CGPoint]
    let connections: [(Int, Int)]
    let shapeName: String
    let circleCenter: CGPoint?
    let circleRadius: CGFloat?
    var isCurveMode: Bool { circleCenter != nil }
}

// ── Shape names ────────────────────────────────────────────────────────────────
// Heptagon (7 dots) and Circle-5 are intentionally excluded.

private let lineShapeNames: [Int: String] = [
    2: "Segment", 3: "Triangle", 4: "Square",
    5: "Pentagon", 6: "Hexagon", 8: "Octagon"
]

private let curveShapeNames: [Int: String] = [
    2: "Arc", 3: "Curve·3", 4: "Curve·4",
    6: "Curve·6", 7: "Curve·7", 8: "Curve·8"
]

// ── Intro level definition ─────────────────────────────────────────────────────

struct IntroGame {
    let levelType: LevelType
    let dotCount: Int
    var shapeName: String {
        levelType.isCurve
            ? (curveShapeNames[dotCount] ?? "Arc")
            : (lineShapeNames[dotCount] ?? "Shape")
    }
}

let introGames: [IntroGame] = [
    IntroGame(levelType: .linesWithGuide,  dotCount: 2),   // Segment + guide
    IntroGame(levelType: .linesWithGuide,  dotCount: 3),   // Triangle + guide
    IntroGame(levelType: .curvesWithGuide, dotCount: 2),   // Arc + guide
    IntroGame(levelType: .curvesNoGuide,   dotCount: 2),   // Arc, no guide
]

// ── Generator ──────────────────────────────────────────────────────────────────

enum LevelGenerator {

    static func shapeName(dotCount: Int, isCurve: Bool) -> String {
        if isCurve { return curveShapeNames[dotCount] ?? "Curve·\(dotCount)" }
        return lineShapeNames[dotCount] ?? "\(dotCount)-gon"
    }

    static func configuration(levelType: LevelType,
                               dotCount: Int,
                               in size: CGSize,
                               dotRadius: CGFloat,
                               topReserved: CGFloat = 68) -> DotConfiguration {
        levelType.isCurve
            ? curveConfig(dotCount: dotCount, in: size, dotRadius: dotRadius, topReserved: topReserved)
            : lineConfig(dotCount: dotCount, in: size, dotRadius: dotRadius, topReserved: topReserved)
    }

    // ── Straight-line layout ───────────────────────────────────────────────

    static func lineConfig(dotCount: Int, in size: CGSize,
                           dotRadius: CGFloat, topReserved: CGFloat) -> DotConfiguration {
        let pad = max(dotRadius * 5, 44)
        let usableH = size.height - topReserved
        let cx = size.width / 2, cy = topReserved + usableH / 2
        let r = min(size.width, usableH) / 2 - pad

        let dots: [CGPoint]
        if dotCount == 2 {
            dots = [CGPoint(x: cx - r * 0.8, y: cy), CGPoint(x: cx + r * 0.8, y: cy)]
        } else {
            dots = (0..<dotCount).map { i in
                let a = CGFloat(i) * 2 * .pi / CGFloat(dotCount) - .pi / 2
                return CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            }
        }
        let conns: [(Int, Int)] = dotCount == 2 ? [(0, 1)]
            : (0..<dotCount).map { ($0, ($0 + 1) % dotCount) }

        return DotConfiguration(dots: dots, connections: conns,
                                shapeName: lineShapeNames[dotCount] ?? "\(dotCount)-gon",
                                circleCenter: nil, circleRadius: nil)
    }

    // ── Arc layout ─────────────────────────────────────────────────────────

    static func curveConfig(dotCount: Int, in size: CGSize,
                            dotRadius: CGFloat, topReserved: CGFloat) -> DotConfiguration {
        let pad = max(dotRadius * 5, 48)
        let usableH = size.height - topReserved
        let cx = size.width / 2, cy = topReserved + usableH / 2
        let r = min(size.width, usableH) / 2 - pad

        let dots = (0..<dotCount).map { i -> CGPoint in
            let a = CGFloat(i) * 2 * .pi / CGFloat(dotCount) - .pi / 2
            return CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
        }
        let conns: [(Int, Int)] = dotCount == 2 ? [(0, 1)]
            : (0..<dotCount).map { ($0, ($0 + 1) % dotCount) }

        return DotConfiguration(dots: dots, connections: conns,
                                shapeName: curveShapeNames[dotCount] ?? "Curve·\(dotCount)",
                                circleCenter: CGPoint(x: cx, y: cy),
                                circleRadius: r)
    }
}
