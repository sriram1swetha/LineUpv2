import Foundation
import Combine
import CoreGraphics

// ── Level type — the 7 levels ─────────────────────────────────────────────────

enum LevelType: Int, CaseIterable, Codable {
    case linesGuided       = 1   // Level 1: straight lines, thick
    case linesThin         = 2   // Level 2: straight lines, thinner
    case curvesGuided      = 3   // Level 3: arcs along a circle, thick
    case curvesThin        = 4   // Level 4: arcs along a circle, thin
    case shapes            = 5   // Level 5: special line shapes (House, Cube…)
    case curveShapes       = 6   // Level 6: special curve shapes (Oval, Flower…)
    case maze              = 7   // Level 7: maze corridors with walls

    var title: String {
        switch self {
        case .linesGuided:    return "Lines"
        case .linesThin:      return "Lines · Thin"
        case .curvesGuided:   return "Curves"
        case .curvesThin:     return "Curves · Thin"
        case .shapes:         return "Shapes"
        case .curveShapes:    return "Curve Shapes"
        case .maze:           return "Maze"
        }
    }

    var subtitle: String {
        switch self {
        case .linesGuided:    return "Draw straight lines between the dots"
        case .linesThin:      return "Thinner strokes — more precision needed"
        case .curvesGuided:   return "Trace arcs along a circle"
        case .curvesThin:     return "Thin curve strokes — precision required"
        case .shapes:         return "Houses, cubes, arrows & more"
        case .curveShapes:    return "Ovals, flowers & creative curves"
        case .maze:           return "Navigate corridors — don't touch the walls"
        }
    }

    var isCurve: Bool {
        self == .curvesGuided || self == .curvesThin || self == .curveShapes
    }

    var hasGuide: Bool { true }   // all levels now have guides

    var isThin: Bool {
        self == .linesThin || self == .curvesThin
    }

    var isShapeLevel: Bool {
        self == .shapes || self == .curveShapes
    }

    var isMaze: Bool {
        self == .maze
    }

    var showsDotNumbers: Bool { true }

    var badgeColor: String {
        switch self {
        case .linesGuided:    return "2196F3"  // blue
        case .linesThin:      return "03A9F4"  // light blue
        case .curvesGuided:   return "9C27B0"  // purple
        case .curvesThin:     return "E91E63"  // pink
        case .shapes:         return "4CAF50"  // green
        case .curveShapes:    return "00BCD4"  // teal
        case .maze:           return "795548"  // brown
        }
    }

    static let totalLevels = 7
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
