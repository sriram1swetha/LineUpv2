import Foundation
import Combine
import CoreGraphics

// ── Level type — the 6 fixed level kinds ──────────────────────────────────────

enum LevelType: Int, CaseIterable, Codable {
    case linesWithGuide       = 1   // Level 1: straight lines + guide
    case linesThinWithGuide   = 2   // Level 2: straight lines, thinner + guide
    case linesNoGuide         = 3   // Level 3: straight lines, no guide
    case linesThinNoGuide     = 4   // Level 4: straight lines, thin, no guide
    case curvesWithGuide      = 5   // Level 5: arcs along a circle + guide arc
    case curvesNoGuide        = 6   // Level 6: arcs along a circle, no guide

    var title: String {
        switch self {
        case .linesWithGuide:     return "Lines · Guided"
        case .linesThinWithGuide: return "Lines · Thin · Guided"
        case .linesNoGuide:       return "Lines · No Guide"
        case .linesThinNoGuide:   return "Lines · Thin · No Guide"
        case .curvesWithGuide:    return "Curves · Guided"
        case .curvesNoGuide:      return "Curves · No Guide"
        }
    }

    var subtitle: String {
        switch self {
        case .linesWithGuide:     return "Draw straight lines with helper guides"
        case .linesThinWithGuide: return "Thinner strokes, guides still shown"
        case .linesNoGuide:       return "No guides — trust your eye"
        case .linesThinNoGuide:   return "Thin strokes, no guides"
        case .curvesWithGuide:    return "Trace arcs along a circle with guides"
        case .curvesNoGuide:      return "Curve freehand — precision required"
        }
    }

    var isCurve: Bool {
        self == .curvesWithGuide || self == .curvesNoGuide
    }

    var hasGuide: Bool {
        self == .linesWithGuide || self == .linesThinWithGuide ||
        self == .curvesWithGuide
    }

    var isThin: Bool {
        self == .linesThinWithGuide || self == .linesThinNoGuide
    }

    var badgeColor: String {
        switch self {
        case .linesWithGuide:     return "2196F3"  // blue
        case .linesThinWithGuide: return "03A9F4"  // light blue
        case .linesNoGuide:       return "FF9800"  // orange
        case .linesThinNoGuide:   return "FF5722"  // deep orange
        case .curvesWithGuide:    return "9C27B0"  // purple
        case .curvesNoGuide:      return "E91E63"  // pink
        }
    }

    static let totalLevels = 6
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

    private enum K {
        static let gamesPerLevel    = "lu_gamesPerLevel"
        static let minGamesPerLevel = "lu_minGamesPerLevel"
        static let maxGamesPerLevel = "lu_maxGamesPerLevel"
        static let dotDiameter      = "lu_dotDiameter"
        static let thickStroke      = "lu_thickStroke"
        static let thinStroke       = "lu_thinStroke"
    }

    private init() {
        gamesPerLevel    = defaults.object(forKey: K.gamesPerLevel)    as? Int    ?? 6
        minGamesPerLevel = defaults.object(forKey: K.minGamesPerLevel) as? Int    ?? 2
        maxGamesPerLevel = defaults.object(forKey: K.maxGamesPerLevel) as? Int    ?? 8
        dotDiameter      = defaults.object(forKey: K.dotDiameter)      as? Double ?? 32.0
        thickStroke      = defaults.object(forKey: K.thickStroke)      as? Double ?? 8.0
        thinStroke       = defaults.object(forKey: K.thinStroke)       as? Double ?? 3.0
    }

    // ── Computed helpers ───────────────────────────────────────────────────

    var dotRadius: CGFloat { CGFloat(dotDiameter / 2) }

    func lineThickness(for levelType: LevelType) -> CGFloat {
        let t = levelType.isThin ? thinStroke : thickStroke
        return CGFloat(min(t, dotDiameter))  // never exceeds dot diameter
    }

    /// Number of dots for game index (1-based). Game 1 → 2 dots, Game 2 → 3, etc.
    func dotCount(forGame game: Int) -> Int { game + 1 }

    /// All 6 level types in fixed order
    var levelTypes: [LevelType] { LevelType.allCases }
}
