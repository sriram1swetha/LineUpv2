import Foundation
import Combine
import CoreGraphics

// ── Level type ─────────────────────────────────────────────────────────────────

enum LevelType: Int, CaseIterable, Codable {
    case linesWithGuide       = 1
    case linesThinWithGuide   = 2
    case linesNoGuide         = 3
    case linesThinNoGuide     = 4
    case curvesWithGuide      = 5
    case curvesNoGuide        = 6

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
        case .linesWithGuide:     return "Draw straight lines — guide shown"
        case .linesThinWithGuide: return "Thinner strokes, guides still shown"
        case .linesNoGuide:       return "No guides — trust your eye"
        case .linesThinNoGuide:   return "Thin strokes, no guides"
        case .curvesWithGuide:    return "Trace arcs along a circle — guide shown"
        case .curvesNoGuide:      return "Freehand curves — precision required"
        }
    }

    var isCurve: Bool  { self == .curvesWithGuide || self == .curvesNoGuide }
    var hasGuide: Bool { self == .linesWithGuide || self == .linesThinWithGuide || self == .curvesWithGuide }
    var isThin: Bool   { self == .linesThinWithGuide || self == .linesThinNoGuide }

    var badgeColor: String {
        switch self {
        case .linesWithGuide:     return "2196F3"
        case .linesThinWithGuide: return "03A9F4"
        case .linesNoGuide:       return "FF9800"
        case .linesThinNoGuide:   return "FF5722"
        case .curvesWithGuide:    return "9C27B0"
        case .curvesNoGuide:      return "E91E63"
        }
    }

    static let totalLevels = 6
}

// ── Dot count mapping (Heptagon and Circle-5 removed) ─────────────────────────

/// Returns the dot count for a given 1-based game index.
/// Line levels: [2,3,4,5,6,8]  — Heptagon (7) skipped
/// Curve levels: [2,3,4,6,7,8] — Circle-5 skipped
func dotCountForGame(_ game: Int, isCurve: Bool) -> Int {
    let lineMap  = [2, 3, 4, 5, 6, 8]
    let curveMap = [2, 3, 4, 6, 7, 8]
    let map = isCurve ? curveMap : lineMap
    let idx = max(0, min(game - 1, map.count - 1))
    return map[idx]
}

// ── Settings ───────────────────────────────────────────────────────────────────

class GameSettings: ObservableObject {
    static let shared = GameSettings()

    // Admin-configurable
    @Published var gamesPerLevel: Int       { didSet { save() } }
    @Published var minGamesPerLevel: Int    { didSet { save() } }
    @Published var maxGamesPerLevel: Int    { didSet { save() } }
    @Published var dotDiameter: Double      { didSet { save() } }
    @Published var thickStroke: Double      { didSet { save() } }
    @Published var thinStroke: Double       { didSet { save() } }
    /// Max undos per individual connection segment (admin setting). 0 = unlimited.
    @Published var maxUndosPerSegment: Int  { didSet { save() } }
    /// Par time per connection in seconds (for time-based scoring)
    @Published var parSecondsPerConnection: Double { didSet { save() } }

    private func save() {
        let d = UserDefaults.standard
        d.set(gamesPerLevel,           forKey: K.gamesPerLevel)
        d.set(minGamesPerLevel,        forKey: K.minGamesPerLevel)
        d.set(maxGamesPerLevel,        forKey: K.maxGamesPerLevel)
        d.set(dotDiameter,             forKey: K.dotDiameter)
        d.set(thickStroke,             forKey: K.thickStroke)
        d.set(thinStroke,              forKey: K.thinStroke)
        d.set(maxUndosPerSegment,      forKey: K.maxUndosPerSegment)
        d.set(parSecondsPerConnection, forKey: K.parSeconds)
    }

    private enum K {
        static let gamesPerLevel    = "lu_gamesPerLevel"
        static let minGamesPerLevel = "lu_minGamesPerLevel"
        static let maxGamesPerLevel = "lu_maxGamesPerLevel"
        static let dotDiameter      = "lu_dotDiameter"
        static let thickStroke      = "lu_thickStroke"
        static let thinStroke       = "lu_thinStroke"
        static let maxUndosPerSegment = "lu_maxUndosPerSegment"
        static let parSeconds       = "lu_parSecondsPerConn"
    }

    private init() {
        let d = UserDefaults.standard
        gamesPerLevel           = d.object(forKey: K.gamesPerLevel)    as? Int    ?? 5
        minGamesPerLevel        = d.object(forKey: K.minGamesPerLevel) as? Int    ?? 2
        maxGamesPerLevel        = d.object(forKey: K.maxGamesPerLevel) as? Int    ?? 6
        dotDiameter             = d.object(forKey: K.dotDiameter)      as? Double ?? 32.0
        thickStroke             = d.object(forKey: K.thickStroke)      as? Double ?? 8.0
        thinStroke              = d.object(forKey: K.thinStroke)       as? Double ?? 3.0
        maxUndosPerSegment      = d.object(forKey: K.maxUndosPerSegment) as? Int  ?? 1
        parSecondsPerConnection = d.object(forKey: K.parSeconds)       as? Double ?? 6.0
    }

    // ── Computed ───────────────────────────────────────────────────────────

    var dotRadius: CGFloat { CGFloat(dotDiameter / 2) }

    func lineThickness(for levelType: LevelType) -> CGFloat {
        CGFloat(min(levelType.isThin ? thinStroke : thickStroke, dotDiameter))
    }

    func dotCount(forGame game: Int, levelType: LevelType) -> Int {
        dotCountForGame(game, isCurve: levelType.isCurve)
    }
}
