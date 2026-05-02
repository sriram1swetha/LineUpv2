import Foundation
import Combine
import CoreGraphics

// ── Level type — the 10 fixed level kinds ─────────────────────────────────────

enum LevelType: Int, CaseIterable, Codable {
    case linesWithGuide       = 1   // Level 1: straight lines + guide, thick
    case linesThinWithGuide   = 2   // Level 2: straight lines, thinner + guide
    case linesNoGuide         = 3   // Level 3: straight lines, no guide, thick
    case linesThinNoGuide     = 4   // Level 4: straight lines, thin, no guide
    case curvesWithGuide      = 5   // Level 5: arc-along-a-circle + guide, thick
    case curvesNoGuide        = 6   // Level 6: arc-along-a-circle + guide, THIN
    case shapesGuided         = 7   // Level 7: special line shapes (House, Cube…)
    case curveShapesGuided    = 8   // Level 8: special curve shapes (Oval, Flower…)
    case mazeGuided           = 9   // Level 9: mazes with numbered dots + guide
    case mazeNoGuide          = 10  // Level 10: mazes without numbers or guide

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
        case .mazeGuided:         return "Maze · Guided"
        case .mazeNoGuide:        return "Maze · No Guide"
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
        case .mazeGuided:         return "Navigate corridors — don't touch the walls"
        case .mazeNoGuide:        return "Maze without guides — memory & precision"
        }
    }

    var isCurve: Bool {
        self == .curvesWithGuide || self == .curvesNoGuide || self == .curveShapesGuided
    }

    var hasGuide: Bool {
        switch self {
        case .linesWithGuide, .linesThinWithGuide,
             .curvesWithGuide, .shapesGuided, .curveShapesGuided,
             .mazeGuided:
            return true
        default:
            return false
        }
    }

    var isThin: Bool {
        self == .linesThinWithGuide || self == .linesThinNoGuide ||
        self == .curvesNoGuide
    }

    var isShapeLevel: Bool {
        self == .shapesGuided || self == .curveShapesGuided
    }

    var isMaze: Bool {
        self == .mazeGuided || self == .mazeNoGuide
    }

    /// Whether to render numbers on dots. Hidden for maze no-guide.
    var showsDotNumbers: Bool {
        self != .mazeNoGuide
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
        case .mazeGuided:         return "795548"  // brown
        case .mazeNoGuide:        return "607D8B"  // blue-grey
        }
    }

    static let totalLevels = 10
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

    // ── Undo limits ────────────────────────────────────────────────────────
    @Published var maxUndosPerSegment: Int {
        didSet { defaults.set(maxUndosPerSegment, forKey: K.maxUndosPerSegment) }
    }

    // ── Timer / par time ───────────────────────────────────────────────────
    @Published var parSecondsPerConnection: Double {
        didSet { defaults.set(parSecondsPerConnection, forKey: K.parSeconds) }
    }

    private enum K {
        static let gamesPerLevel       = "lu_gamesPerLevel"
        static let minGamesPerLevel    = "lu_minGamesPerLevel"
        static let maxGamesPerLevel    = "lu_maxGamesPerLevel"
        static let dotDiameter         = "lu_dotDiameter"
        static let thickStroke         = "lu_thickStroke"
        static let thinStroke          = "lu_thinStroke"
        static let continuousDrawing   = "lu_continuousDrawing"
        static let maxUndosPerSegment  = "lu_maxUndosPerSegment"
        static let parSeconds          = "lu_parSecondsPerConn"
    }

    private init() {
        gamesPerLevel           = defaults.object(forKey: K.gamesPerLevel)      as? Int    ?? 10
        minGamesPerLevel        = defaults.object(forKey: K.minGamesPerLevel)   as? Int    ?? 2
        maxGamesPerLevel        = defaults.object(forKey: K.maxGamesPerLevel)   as? Int    ?? 12
        dotDiameter             = defaults.object(forKey: K.dotDiameter)        as? Double ?? 32.0
        thickStroke             = defaults.object(forKey: K.thickStroke)        as? Double ?? 8.0
        thinStroke              = defaults.object(forKey: K.thinStroke)         as? Double ?? 3.0
        continuousDrawing       = defaults.object(forKey: K.continuousDrawing)  as? Bool   ?? true
        maxUndosPerSegment      = defaults.object(forKey: K.maxUndosPerSegment) as? Int    ?? 1
        parSecondsPerConnection = defaults.object(forKey: K.parSeconds)         as? Double ?? 6.0
    }

    // ── Computed helpers ───────────────────────────────────────────────────

    var dotRadius: CGFloat { CGFloat(dotDiameter / 2) }

    func lineThickness(for levelType: LevelType) -> CGFloat {
        let t = levelType.isThin ? thinStroke : thickStroke
        return CGFloat(min(t, dotDiameter))
    }

    func dotCount(forGame game: Int) -> Int { game + 1 }

    /// Smarter dot-count mapping that skips awkward shapes (7-gon, 5-circle).
    func dotCount(forGame game: Int, levelType: LevelType) -> Int {
        let lineMap  = [2, 3, 4, 5, 6, 8]
        let curveMap = [2, 3, 4, 6, 7, 8]
        let map = levelType.isCurve ? curveMap : lineMap
        let idx = max(0, min(game - 1, map.count - 1))
        return map[idx]
    }

    var levelTypes: [LevelType] { LevelType.allCases }
}
