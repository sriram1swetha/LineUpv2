import CoreGraphics
import Foundation

// ── Scoring model ──────────────────────────────────────────────────────────────
//
// LINE accuracy:  score = 100 × exp(−10 × rms_perp / |AB|)         (k=10, was 6)
// ARC accuracy:   score = 100 × exp(−8  × rms_arc  / arc_length)   (k=8,  was 5)
//
// Time penalty (applied after accuracy):
//   overtime    = max(0, elapsed − par)
//   time_factor = exp(−0.018 × overtime)
//   final_score = round(accuracy × time_factor)
//
// With k=10 (line accuracy):
//   0% dev  → 100 | 2% → 82 | 5% → 61 | 10% → 37 | 20% → 14
//
// With time k=0.018:
//   0s over → 1.00 | 10s over → 0.84 | 30s over → 0.58 | 60s over → 0.34

enum ScoringEngine {

    // ── Geometry ───────────────────────────────────────────────────────────

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    static func perpendicularDistance(_ p: CGPoint,
                                      lineStart a: CGPoint,
                                      lineEnd b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0 else { return distance(p, a) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / len
    }

    static func distanceToCircle(_ p: CGPoint,
                                  center: CGPoint,
                                  radius: CGFloat) -> CGFloat {
        abs(distance(p, center) - radius)
    }

    // ── Line scoring ───────────────────────────────────────────────────────

    static func scoreAccuracy(path: [CGPoint],
                               from start: CGPoint,
                               to end: CGPoint,
                               dotRadius: CGFloat) -> Int {
        guard path.count >= 2 else { return 0 }
        let threshold = max(dotRadius * 3.5, 24)
        guard distance(path.first!, start) < threshold,
              distance(path.last!,  end)   < threshold else { return 0 }
        let len = distance(start, end)
        guard len > 1 else { return 100 }
        let sumSq = path.reduce(CGFloat(0)) {
            $0 + pow(perpendicularDistance($1, lineStart: start, lineEnd: end), 2)
        }
        let rms = sqrt(sumSq / CGFloat(path.count))
        return clamp(100.0 * Foundation.exp(-10.0 * Double(rms / len)))
    }

    // ── Arc scoring ────────────────────────────────────────────────────────

    static func scoreArcAccuracy(path: [CGPoint],
                                  from start: CGPoint,
                                  to end: CGPoint,
                                  circleCenter: CGPoint,
                                  circleRadius: CGFloat,
                                  dotRadius: CGFloat) -> Int {
        guard path.count >= 2 else { return 0 }
        let threshold = max(dotRadius * 3.5, 24)
        guard distance(path.first!, start) < threshold,
              distance(path.last!,  end)   < threshold else { return 0 }

        let sa = atan2(start.y - circleCenter.y, start.x - circleCenter.x)
        let ea = atan2(end.y   - circleCenter.y, end.x   - circleCenter.x)
        var delta = ea - sa
        while delta >  .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        let arcLen = abs(delta) * circleRadius
        guard arcLen > 1 else { return 100 }

        let sumSq = path.reduce(CGFloat(0)) {
            $0 + pow(distanceToCircle($1, center: circleCenter, radius: circleRadius), 2)
        }
        let rms = sqrt(sumSq / CGFloat(path.count))
        return clamp(100.0 * Foundation.exp(-8.0 * Double(rms / arcLen)))
    }

    // ── Time penalty ───────────────────────────────────────────────────────

    /// Apply time penalty to an accuracy score.
    /// - elapsed:    actual seconds taken for the full game
    /// - par:        expected seconds (connections × parSecondsPerConn)
    static func applyTimePenalty(accuracyScore: Int,
                                  elapsed: Double,
                                  par: Double) -> Int {
        let overtime = max(0, elapsed - par)
        let factor = Foundation.exp(-0.018 * overtime)
        return clamp(Double(accuracyScore) * factor)
    }

    // ── Helper ─────────────────────────────────────────────────────────────

    private static func clamp(_ v: Double) -> Int {
        max(0, min(100, Int(v.rounded())))
    }
}
