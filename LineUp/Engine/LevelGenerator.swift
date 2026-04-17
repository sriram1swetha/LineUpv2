import CoreGraphics
import Foundation

// ── Data types ─────────────────────────────────────────────────────────────────

struct DotConfiguration {
    let dots: [CGPoint]
    let connections: [(Int, Int)]
    let shapeName: String

    /// Default circle (used by simple full-circle curve games).
    /// nil for straight-line games AND for multi-arc games that use
    /// `perConnectionArcs` instead.
    let circleCenter: CGPoint?
    let circleRadius: CGFloat?

    /// Per-connection arc geometry. When present, parallel to `connections`.
    /// Each entry, if non-nil, supplies (center, radius) for that connection's
    /// arc. nil entries fall back to (`circleCenter`, `circleRadius`).
    /// nil for straight-line games.
    let perConnectionArcs: [(center: CGPoint, radius: CGFloat)?]?

    var isCurveMode: Bool { circleCenter != nil || perConnectionArcs != nil }

    /// Convenience: arc info for a given connection index, or nil if this
    /// connection is a straight line.
    func arcInfo(for connectionIndex: Int) -> (center: CGPoint, radius: CGFloat)? {
        if let perConn = perConnectionArcs,
           connectionIndex >= 0,
           connectionIndex < perConn.count,
           let info = perConn[connectionIndex] {
            return info
        }
        if let c = circleCenter, let r = circleRadius {
            return (center: c, radius: r)
        }
        return nil
    }
}

// ── Generator ──────────────────────────────────────────────────────────────────

enum LevelGenerator {

    private static let regularShapeNames = [
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
        guard idx >= 0, idx < regularShapeNames.count else { return "\(dotCount)-gon" }
        return regularShapeNames[idx]
    }

    /// Lightweight name lookup for UI cards that don't need to build the full
    /// geometry. Matches what `configuration(...)` will produce:
    ///  - Games 1–6 use the regular polygon / full-circle names.
    ///  - Games 7+ use the asymmetric / partial-arc template names.
    static func previewName(levelType: LevelType, dotCount: Int, game: Int) -> String {
        if game <= 6 {
            if levelType.isCurve {
                return dotCount == 2 ? "Arc" : "Circle-\(dotCount)"
            }
            return shapeName(dotCount: dotCount)
        }
        if levelType.isCurve {
            let names = ["Half Arc", "S-Curve", "Wave", "Double Hump", "Bowl", "Quad Wave"]
            let i = ((game - 7) % names.count + names.count) % names.count
            return names[i]
        } else {
            return asymmetricLineTemplate(forIndex: game - 7).name
        }
    }

    /// Build configuration for a given level type and game index.
    static func configuration(levelType: LevelType,
                              dotCount: Int,
                              game: Int,
                              in size: CGSize,
                              dotRadius: CGFloat,
                              topReserved: CGFloat = 68) -> DotConfiguration {
        if levelType.isCurve {
            return curveConfig(dotCount: dotCount, game: game, in: size,
                               dotRadius: dotRadius, topReserved: topReserved)
        } else {
            return lineConfig(dotCount: dotCount, game: game, in: size,
                              dotRadius: dotRadius, topReserved: topReserved)
        }
    }

    // ── Straight line configuration ────────────────────────────────────────

    static func lineConfig(dotCount: Int,
                           game: Int,
                           in size: CGSize,
                           dotRadius: CGFloat,
                           topReserved: CGFloat) -> DotConfiguration {
        let padding = max(dotRadius * 5, 44)
        let usableTop    = topReserved
        let usableHeight = size.height - topReserved
        let cx = size.width / 2
        let cy = usableTop + usableHeight / 2
        let polyRadius = min(size.width, usableHeight) / 2 - padding

        // For games 1...6 keep the original regular-polygon behaviour. For
        // games 7+ we cycle through asymmetric / concave templates.
        if game <= 6 {
            var dots: [CGPoint]
            if dotCount == 2 {
                let offset = polyRadius * 0.80
                dots = [CGPoint(x: cx - offset, y: cy),
                        CGPoint(x: cx + offset, y: cy)]
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

            return DotConfiguration(dots: dots,
                                    connections: connections,
                                    shapeName: shapeName(dotCount: dotCount),
                                    circleCenter: nil,
                                    circleRadius: nil,
                                    perConnectionArcs: nil)
        }

        // Asymmetric templates. Index = game - 7.
        let template = asymmetricLineTemplate(forIndex: game - 7)
        let dots = template.unitDots.map { p in
            CGPoint(x: cx + p.x * polyRadius,
                    y: cy + p.y * polyRadius)
        }
        let connections = template.connections
            ?? (0..<dots.count).map { ($0, ($0 + 1) % dots.count) }

        return DotConfiguration(dots: dots,
                                connections: connections,
                                shapeName: template.name,
                                circleCenter: nil,
                                circleRadius: nil,
                                perConnectionArcs: nil)
    }

    // ── Asymmetric line templates ──────────────────────────────────────────
    //
    // Coordinates are in unit space (-1...1, -1...1) where +y is DOWN
    // (matches SwiftUI). They get scaled by the layout's polyRadius.

    private struct AsymTemplate {
        let name: String
        let unitDots: [CGPoint]
        /// nil = chain in order (0→1→2→…→0). Use explicit list to pick a
        /// different draw order.
        let connections: [(Int, Int)]?
    }

    private static let asymmetricLineTemplates: [AsymTemplate] = [
        // 3 dots — scalene triangle
        AsymTemplate(name: "Scalene Triangle",
                     unitDots: [
                        CGPoint(x: -0.85, y:  0.45),
                        CGPoint(x:  0.75, y:  0.65),
                        CGPoint(x:  0.10, y: -0.80)
                     ], connections: nil),

        // 4 dots — irregular kite
        AsymTemplate(name: "Kite",
                     unitDots: [
                        CGPoint(x:  0.00, y: -0.85),
                        CGPoint(x:  0.65, y:  0.05),
                        CGPoint(x:  0.00, y:  0.80),
                        CGPoint(x: -0.65, y:  0.05)
                     ], connections: nil),

        // 4 dots — trapezoid
        AsymTemplate(name: "Trapezoid",
                     unitDots: [
                        CGPoint(x: -0.45, y: -0.55),
                        CGPoint(x:  0.45, y: -0.55),
                        CGPoint(x:  0.85, y:  0.55),
                        CGPoint(x: -0.85, y:  0.55)
                     ], connections: nil),

        // 5 dots — arrowhead (concave)
        AsymTemplate(name: "Arrowhead",
                     unitDots: [
                        CGPoint(x: -0.75, y: -0.65),
                        CGPoint(x:  0.85, y:  0.00),
                        CGPoint(x: -0.75, y:  0.65),
                        CGPoint(x: -0.30, y:  0.00),
                        CGPoint(x: -0.75, y: -0.20)
                     ],
                     connections: [(0,1),(1,2),(2,3),(3,0)] // 4-edge concave outline
                    ),

        // 5 dots — house (pentagon-ish, asymmetric)
        AsymTemplate(name: "House",
                     unitDots: [
                        CGPoint(x: -0.70, y:  0.70),
                        CGPoint(x:  0.70, y:  0.70),
                        CGPoint(x:  0.70, y: -0.20),
                        CGPoint(x:  0.00, y: -0.85),
                        CGPoint(x: -0.70, y: -0.20)
                     ], connections: nil),

        // 6 dots — L-shape (concave)
        AsymTemplate(name: "L-Shape",
                     unitDots: [
                        CGPoint(x: -0.75, y: -0.75),
                        CGPoint(x: -0.10, y: -0.75),
                        CGPoint(x: -0.10, y:  0.10),
                        CGPoint(x:  0.75, y:  0.10),
                        CGPoint(x:  0.75, y:  0.75),
                        CGPoint(x: -0.75, y:  0.75)
                     ], connections: nil),

        // 6 dots — zig-zag chevron
        AsymTemplate(name: "Zig-Zag",
                     unitDots: [
                        CGPoint(x: -0.85, y:  0.40),
                        CGPoint(x: -0.50, y: -0.45),
                        CGPoint(x: -0.15, y:  0.40),
                        CGPoint(x:  0.20, y: -0.45),
                        CGPoint(x:  0.55, y:  0.40),
                        CGPoint(x:  0.85, y: -0.20)
                     ],
                     connections: [(0,1),(1,2),(2,3),(3,4),(4,5)] // open path
                    ),

        // 7 dots — irregular heptagon
        AsymTemplate(name: "Irregular Heptagon",
                     unitDots: [
                        CGPoint(x:  0.00, y: -0.85),
                        CGPoint(x:  0.80, y: -0.40),
                        CGPoint(x:  0.55, y:  0.55),
                        CGPoint(x:  0.10, y:  0.80),
                        CGPoint(x: -0.40, y:  0.65),
                        CGPoint(x: -0.85, y:  0.10),
                        CGPoint(x: -0.45, y: -0.55)
                     ], connections: nil),

        // 8 dots — star/crown (concave)
        AsymTemplate(name: "Crown",
                     unitDots: [
                        CGPoint(x: -0.85, y:  0.65),
                        CGPoint(x: -0.85, y: -0.10),
                        CGPoint(x: -0.55, y: -0.55),
                        CGPoint(x: -0.20, y: -0.10),
                        CGPoint(x:  0.20, y: -0.55),
                        CGPoint(x:  0.55, y: -0.10),
                        CGPoint(x:  0.85, y: -0.55),
                        CGPoint(x:  0.85, y:  0.65)
                     ], connections: nil),
    ]

    private static func asymmetricLineTemplate(forIndex idx: Int) -> AsymTemplate {
        let n = asymmetricLineTemplates.count
        let i = ((idx % n) + n) % n
        return asymmetricLineTemplates[i]
    }

    // ── Curve (arc) configuration ──────────────────────────────────────────
    //
    // Games 1...6  → original behaviour: dots evenly spaced on one circle,
    //                each connection is the arc between adjacent dots.
    // Games 7+     → "partial arc" templates: a few large arcs that don't
    //                form a full circle. Each connection has its own arc
    //                center and radius via `perConnectionArcs`.

    static func curveConfig(dotCount: Int,
                            game: Int,
                            in size: CGSize,
                            dotRadius: CGFloat,
                            topReserved: CGFloat) -> DotConfiguration {
        let padding = max(dotRadius * 5, 48)
        let usableTop    = topReserved
        let usableHeight = size.height - topReserved
        let cx = size.width / 2
        let cy = usableTop + usableHeight / 2
        let radius = min(size.width, usableHeight) / 2 - padding

        if game <= 6 {
            let startAngle: CGFloat = -.pi / 2
            let dots = (0..<dotCount).map { i -> CGPoint in
                let angle = startAngle + CGFloat(i) * 2 * .pi / CGFloat(dotCount)
                return CGPoint(x: cx + radius * cos(angle),
                               y: cy + radius * sin(angle))
            }
            let connections: [(Int, Int)] = dotCount == 2
                ? [(0, 1)]
                : (0..<dotCount).map { ($0, ($0 + 1) % dotCount) }
            let arcLabel = dotCount == 2 ? "Arc" : "Circle-\(dotCount)"
            return DotConfiguration(dots: dots,
                                    connections: connections,
                                    shapeName: arcLabel,
                                    circleCenter: CGPoint(x: cx, y: cy),
                                    circleRadius: radius,
                                    perConnectionArcs: nil)
        }

        // Partial-arc templates — index = game - 7.
        return partialArcTemplate(forIndex: game - 7,
                                  cx: cx, cy: cy,
                                  size: size,
                                  usableTop: usableTop,
                                  usableHeight: usableHeight,
                                  radius: radius)
    }

    // Each template returns the dots, connections and per-connection arcs.
    private static func partialArcTemplate(forIndex idx: Int,
                                           cx: CGFloat, cy: CGFloat,
                                           size: CGSize,
                                           usableTop: CGFloat,
                                           usableHeight: CGFloat,
                                           radius: CGFloat) -> DotConfiguration {
        // Note: templates intentionally use arcs ≤180°. The existing
        // ArcPath / ScoringEngine always pick the SHORTER arc between two
        // points, so anything bigger (e.g. a 270° sweep or a big "C") would
        // render as the small leftover arc instead of the intended curve.
        let templates: [(CGFloat, CGFloat, CGFloat, CGSize, CGFloat, CGFloat) -> DotConfiguration] = [
            halfCircleArc,
            sCurveTwoArcs,
            waveThreeArcs,
            doubleHumpArcs,
            bigBowlArc,
            quadWaveArcs
        ]
        let n = templates.count
        let i = ((idx % n) + n) % n
        return templates[i](cx, cy, radius, size, usableTop, usableHeight)
    }

    // MARK: Individual partial-arc templates

    /// Half-circle (180°) — a single big arc, 2 dots on the same horizontal line.
    private static func halfCircleArc(cx: CGFloat, cy: CGFloat,
                                      radius r: CGFloat,
                                      size: CGSize,
                                      usableTop: CGFloat,
                                      usableHeight: CGFloat) -> DotConfiguration {
        let arcR = r * 0.95
        let a = CGPoint(x: cx - arcR, y: cy)
        let b = CGPoint(x: cx + arcR, y: cy)
        return DotConfiguration(
            dots: [a, b],
            connections: [(0, 1)],
            shapeName: "Half Arc",
            circleCenter: nil, circleRadius: nil,
            perConnectionArcs: [(center: CGPoint(x: cx, y: cy), radius: arcR)]
        )
    }

    /// S-curve from two arcs of opposite curvature, 3 dots.
    private static func sCurveTwoArcs(cx: CGFloat, cy: CGFloat,
                                      radius r: CGFloat,
                                      size: CGSize,
                                      usableTop: CGFloat,
                                      usableHeight: CGFloat) -> DotConfiguration {
        let arcR = r * 0.55
        let dy = arcR * 1.6
        let a = CGPoint(x: cx, y: cy - dy)
        let b = CGPoint(x: cx, y: cy)
        let c = CGPoint(x: cx, y: cy + dy)
        // First arc bulges to the right, second to the left.
        let center1 = CGPoint(x: cx + arcR, y: cy - dy / 2)
        let center2 = CGPoint(x: cx - arcR, y: cy + dy / 2)
        let arcR1 = sqrt(pow(a.x - center1.x, 2) + pow(a.y - center1.y, 2))
        let arcR2 = sqrt(pow(b.x - center2.x, 2) + pow(b.y - center2.y, 2))
        return DotConfiguration(
            dots: [a, b, c],
            connections: [(0, 1), (1, 2)],
            shapeName: "S-Curve",
            circleCenter: nil, circleRadius: nil,
            perConnectionArcs: [
                (center: center1, radius: arcR1),
                (center: center2, radius: arcR2)
            ]
        )
    }

    /// Three-arc horizontal wave, 4 dots.
    private static func waveThreeArcs(cx: CGFloat, cy: CGFloat,
                                      radius r: CGFloat,
                                      size: CGSize,
                                      usableTop: CGFloat,
                                      usableHeight: CGFloat) -> DotConfiguration {
        let arcR = r * 0.45
        let dx = arcR * 1.6
        let dots = [
            CGPoint(x: cx - 1.5 * dx, y: cy),
            CGPoint(x: cx - 0.5 * dx, y: cy),
            CGPoint(x: cx + 0.5 * dx, y: cy),
            CGPoint(x: cx + 1.5 * dx, y: cy)
        ]
        // Alternate up/down: arcs bulge up, then down, then up.
        let centers = [
            CGPoint(x: cx - dx, y: cy + arcR),  // bulges up
            CGPoint(x: cx,      y: cy - arcR),  // bulges down
            CGPoint(x: cx + dx, y: cy + arcR)   // bulges up
        ]
        let arcs: [(center: CGPoint, radius: CGFloat)?] = centers.enumerated().map { (i, c) in
            let p = dots[i]
            let rr = sqrt(pow(p.x - c.x, 2) + pow(p.y - c.y, 2))
            return (center: c, radius: rr)
        }
        return DotConfiguration(
            dots: dots,
            connections: [(0, 1), (1, 2), (2, 3)],
            shapeName: "Wave",
            circleCenter: nil, circleRadius: nil,
            perConnectionArcs: arcs
        )
    }

    /// Two large humps side by side (∩∩), 3 dots.
    private static func doubleHumpArcs(cx: CGFloat, cy: CGFloat,
                                       radius r: CGFloat,
                                       size: CGSize,
                                       usableTop: CGFloat,
                                       usableHeight: CGFloat) -> DotConfiguration {
        let arcR = r * 0.55
        let dots = [
            CGPoint(x: cx - 2 * arcR, y: cy),
            CGPoint(x: cx,             y: cy),
            CGPoint(x: cx + 2 * arcR,  y: cy)
        ]
        // Both arcs bulge upward (centers below the dots in screen coords
        // because +y is down → a center BELOW the chord makes an arc bulging
        // UP… SwiftUI's "shorter arc" picks the right side automatically).
        let centers = [
            CGPoint(x: cx - arcR, y: cy + arcR * 0.1),
            CGPoint(x: cx + arcR, y: cy + arcR * 0.1)
        ]
        let arcs: [(center: CGPoint, radius: CGFloat)?] = centers.enumerated().map { (i, c) in
            let p = dots[i]
            let rr = sqrt(pow(p.x - c.x, 2) + pow(p.y - c.y, 2))
            return (center: c, radius: rr)
        }
        return DotConfiguration(
            dots: dots,
            connections: [(0, 1), (1, 2)],
            shapeName: "Double Hump",
            circleCenter: nil, circleRadius: nil,
            perConnectionArcs: arcs
        )
    }

    /// One big shallow bowl arc (200°-ish), 2 dots far apart.
    private static func bigBowlArc(cx: CGFloat, cy: CGFloat,
                                   radius r: CGFloat,
                                   size: CGSize,
                                   usableTop: CGFloat,
                                   usableHeight: CGFloat) -> DotConfiguration {
        let arcR = r * 1.05
        // Endpoints on a horizontal line above the center; the big arc dips
        // downward forming a bowl shape.
        let dx = arcR * 0.85
        let a = CGPoint(x: cx - dx, y: cy - arcR * 0.3)
        let b = CGPoint(x: cx + dx, y: cy - arcR * 0.3)
        let center = CGPoint(x: cx, y: cy - arcR * 1.1) // center far above so arc dips low
        let rr = sqrt(pow(a.x - center.x, 2) + pow(a.y - center.y, 2))
        return DotConfiguration(
            dots: [a, b],
            connections: [(0, 1)],
            shapeName: "Bowl",
            circleCenter: nil, circleRadius: nil,
            perConnectionArcs: [(center: center, radius: rr)]
        )
    }

    /// Four-arc wave, 5 dots.
    private static func quadWaveArcs(cx: CGFloat, cy: CGFloat,
                                     radius r: CGFloat,
                                     size: CGSize,
                                     usableTop: CGFloat,
                                     usableHeight: CGFloat) -> DotConfiguration {
        let arcR = r * 0.40
        let dx = arcR * 1.6
        let dots = (0..<5).map { i in
            CGPoint(x: cx + CGFloat(i - 2) * dx, y: cy)
        }
        // Alternating bulge directions.
        let arcs: [(center: CGPoint, radius: CGFloat)?] = (0..<4).map { i in
            let bulgeUp = (i % 2 == 0)
            let mid = CGPoint(x: (dots[i].x + dots[i + 1].x) / 2,
                              y: cy + (bulgeUp ? arcR : -arcR))
            let rr = sqrt(pow(dots[i].x - mid.x, 2) + pow(dots[i].y - mid.y, 2))
            return (center: mid, radius: rr)
        }
        let connections: [(Int, Int)] = (0..<4).map { ($0, $0 + 1) }
        return DotConfiguration(
            dots: dots,
            connections: connections,
            shapeName: "Quad Wave",
            circleCenter: nil, circleRadius: nil,
            perConnectionArcs: arcs
        )
    }
}
