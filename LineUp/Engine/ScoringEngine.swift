import CoreGraphics
import Foundation

enum ScoringEngine {

    // ── Geometry ───────────────────────────────────────────────────────────

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Perpendicular distance from point P to the infinite line through A–B.
    static func perpendicularDistance(_ p: CGPoint, lineStart a: CGPoint, lineEnd b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return distance(p, a) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / len
    }

    /// Distance from point P to a circle (nearest point on circumference).
    static func distanceToCircle(_ p: CGPoint, center: CGPoint, radius: CGFloat) -> CGFloat {
        abs(distance(p, center) - radius)
    }

    // ── Straight-line scoring ──────────────────────────────────────────────
    ///
    /// score = 100 × exp(−6 × rms_perp / |AB|)
    /// Returns 0 when the path doesn't reach both dots.

    static func score(path: [CGPoint],
                      from start: CGPoint,
                      to end: CGPoint,
                      dotRadius: CGFloat) -> Int {
        guard path.count >= 2 else { return 0 }
        let threshold = max(dotRadius * 3.5, 24)
        guard distance(path.first!, start) < threshold,
              distance(path.last!,  end)   < threshold else { return 0 }
        let idealLength = distance(start, end)
        guard idealLength > 1 else { return 100 }
        let sumSq = path.reduce(CGFloat(0)) {
            let d = perpendicularDistance($1, lineStart: start, lineEnd: end)
            return $0 + d * d
        }
        let rms = sqrt(sumSq / CGFloat(path.count))
        let normalised = rms / idealLength
        return clamp(100.0 * Foundation.exp(-6.0 * normalised))
    }

    // ── Arc scoring ────────────────────────────────────────────────────────
    ///
    /// The ideal path between two dots on a circle is the shorter arc of that circle.
    /// Deviation for each touch point = |dist(point, center) − radius|.
    /// score = 100 × exp(−5 × rms_deviation / arc_length)
    /// (k=5 is slightly more forgiving than lines since curves are harder)

    static func scoreArc(path: [CGPoint],
                         from start: CGPoint,
                         to end: CGPoint,
                         circleCenter: CGPoint,
                         circleRadius: CGFloat,
                         dotRadius: CGFloat) -> Int {
        guard path.count >= 2 else { return 0 }
        let threshold = max(dotRadius * 3.5, 24)
        guard distance(path.first!, start) < threshold,
              distance(path.last!,  end)   < threshold else { return 0 }

        // Arc length between the two endpoints
        let startAngle = atan2(start.y - circleCenter.y, start.x - circleCenter.x)
        let endAngle   = atan2(end.y   - circleCenter.y, end.x   - circleCenter.x)
        var delta = endAngle - startAngle
        // Normalise to shorter arc
        while delta >  .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        let arcLength = abs(delta) * circleRadius
        guard arcLength > 1 else { return 100 }

        // RMS distance to the circle
        let sumSq = path.reduce(CGFloat(0)) {
            let d = distanceToCircle($1, center: circleCenter, radius: circleRadius)
            return $0 + d * d
        }
        let rms = sqrt(sumSq / CGFloat(path.count))
        let normalised = rms / arcLength
        return clamp(100.0 * Foundation.exp(-5.0 * normalised))
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private static func clamp(_ v: Double) -> Int {
        max(0, min(100, Int(v.rounded())))
    }
}
