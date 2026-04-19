import Foundation
import Combine
import CoreGraphics

// ── Level type — the 8 fixed level kinds ──────────────────────────────────────

enum LevelType: Int, CaseIterable, Codable {
    case linesWithGuide       = 1   // Level 1: straight lines + guide, thick
    case linesThinWithGuide   = 2   // Level 2: straight lines, thinner + guide
    case linesNoGuide         = 3   // Level 3: straight lines, no guide, thick
    case linesThinNoGuide     = 4   // Level 4: straight lines, thin, no guide
    case curvesWithGuide      = 5   // Level 5: arc-along-a-circle + guide, thick
    case curvesNoGuide        = 6   // Level 6: arc-along-a-circle + guide, THIN
    case shapesGuided         = 7   // Level 7: special line shapes (House, Cube…)
    case curveShapesGuided    = 8   // Level 8: special curve shapes (Oval, Flower…)

    var title: String {
        switch self {
        case .linesWithGuide:     return "Lines · Guided"
        case .linesThinWithGuide: return "Lines · Thin · Guided"
        case .linesNoGuide:       return "Lines · No Guide"
        case .linesThinNoGuide:   return "Lines · Thin · No Guide"
        case .curvesWithGuide:    return "Curves · Guided"
        case .curvesNoGuide:      return "Curves · Thin · Guided"
        case .shapesGuided:       return "Shapes · Guided"
        case .curveShapesGuided:  return "Curve Shapes · Guided"
        }
    }

    var subtitle: String {
        switch self {
        case .linesWithGuide:     return "Draw straight lines with helper guides"
        case .linesThinWithGuide: return "Thinner strokes, guides still shown"
        case .linesNoGuide:       return "No guides — trust your eye"
        case .linesThinNoGuide:   return "Thin strokes, no guides"
        case .curvesWithGuide:    return "Trace arcs along a circle with guides"
        case .curvesNoGuide:      return "Thin curve strokes — precision required"
        case .shapesGuided:       return "Houses, cubes, arrows & more"
        case .curveShapesGuided:  return "Ovals, flowers & creative curves"
        }
    }

    var isCurve: Bool {
        self == .curvesWithGuide || self == .curvesNoGuide || self == .curveShapesGuided
    }

    /// Curves always render a guide regardless of this flag — tracing a
    /// partial arc without any reference is basically guessing. This flag
    /// still controls whether straight-line levels get a dashed guide.
    var hasGuide: Bool {
        switch self {
        case .linesWithGuide, .linesThinWithGuide,
             .curvesWithGuide, .shapesGuided, .curveShapesGuided:
            return true
        default:
            return false
        }
    }

    var isThin: Bool {
        self == .linesThinWithGuide || self == .linesThinNoGuide ||
        self == .curvesNoGuide
    }

    /// Shape levels use a fixed set of templates — every game maps directly
    /// to a template instead of the polygon/circle progression.
    var isShapeLevel: Bool {
        self == .shapesGuided || self == .curveShapesGuided
    }

    var badgeColor: String {
        switch self {
        case .linesWithGuide:     return "2196F3"  // blue
        case .linesThinWithGuide: return "03A9F4"  // light blue
        case .linesNoGuide:       return "FF9800"  // orange
        case .linesThinNoGuide:   return "FF5722"  // deep orange
        case .curvesWithGuide:    return "9C27B0"  // purple
        case .curvesNoGuide:      return "E91E63"  // pink
        case .shapesGuided:       return "4CAF50"  // green
        case .curveShapesGuided:  return "00BCD4"  // teal
        }
    }

    static let totalLevels = 8
}

// ── Settings ───────────────────────────────────────────────────────────────────

class GameSettings: ObservableObject {
    static let shared = GameSettings()

    private let defaults = UserDefaults.standard

    // ── Games per level (determines dot count: game N → N+1 dots) ──────────
    @Published var gamesPerLevel: Int {
        didSet { defaults.set(gamesPerLevel, forKey: K.gamesPerLevel) }
    }
    @Published var minGamesPerLevel: Int {
        didSet { defaults.set(minGamesPerLevel, forKey: K.minGamesPerLevel) }
    }
    @Published var maxGamesPerLevel: Int {
        didSet { defaults.set(maxGamesPerLevel, forKey: K.maxGamesPerLevel) }
    }

    // ── Dot diameter ────────────────────────────────────────────────────────
    @Published var dotDiameter: Double {
        didSet { defaults.set(dotDiameter, forKey: K.dotDiameter) }
    }

    // ── Stroke thicknesses ──────────────────────────────────────────────────
    @Published var thickStroke: Double {
        didSet { defaults.set(thickStroke, forKey: K.thickStroke) }
    }
    @Published var thinStroke: Double {
        didSet { defaults.set(thinStroke, forKey: K.thinStroke) }
    }

    // ── Continuous drawing ─────────────────────────────────────────────────
    /// When true, the player can draw dot-1 → dot-2 → dot-3 → … in a single
    /// uninterrupted gesture. Each sub-stroke is scored the moment the finger
    /// reaches the next end dot and the stroke color/target flips immediately
    /// (no 1.5s pause, no required lift-and-re-tap for chained connections).
    /// When false, each connection requires a separate touch-and-release.
    @Published var continuousDrawing: Bool {
        didSet { defaults.set(continuousDrawing, forKey: K.continuousDrawing) }
    }

    private enum K {
        static let gamesPerLevel    = "lu_gamesPerLevel"
        static let minGamesPerLevel = "lu_minGamesPerLevel"
        static let maxGamesPerLevel = "lu_maxGamesPerLevel"
        static let dotDiameter      = "lu_dotDiameter"
        static let thickStroke      = "lu_thickStroke"
        static let thinStroke       = "lu_thinStroke"
        static let continuousDrawing = "lu_continuousDrawing"
    }

    private init() {
        gamesPerLevel    = defaults.object(forKey: K.gamesPerLevel)    as? Int    ?? 10
        minGamesPerLevel = defaults.object(forKey: K.minGamesPerLevel) as? Int    ?? 2
        maxGamesPerLevel = defaults.object(forKey: K.maxGamesPerLevel) as? Int    ?? 12
        dotDiameter      = defaults.object(forKey: K.dotDiameter)      as? Double ?? 32.0
        thickStroke      = defaults.object(forKey: K.thickStroke)      as? Double ?? 8.0
        thinStroke       = defaults.object(forKey: K.thinStroke)       as? Double ?? 3.0
        continuousDrawing = defaults.object(forKey: K.continuousDrawing) as? Bool ?? true
    }

    // ── Computed helpers ───────────────────────────────────────────────────

    var dotRadius: CGFloat { CGFloat(dotDiameter / 2) }

    func lineThickness(for levelType: LevelType) -> CGFloat {
        let t = levelType.isThin ? thinStroke : thickStroke
        return CGFloat(min(t, dotDiameter))  // never exceeds dot diameter
    }

    /// Number of dots for game index (1-based). Game 1 → 2 dots, Game 2 → 3, etc.
    func dotCount(forGame game: Int) -> Int { game + 1 }

    /// All 8 level types in fixed order
    var levelTypes: [LevelType] { LevelType.allCases }
}
