import SwiftUI

// ── Difficulty rating ─────────────────────────────────────────────────────────

enum DifficultyRating: String {
    case easy    = "Easy"
    case medium  = "Medium"
    case hard    = "Hard"
    case hardest = "Hardest"

    var color: Color {
        switch self {
        case .easy:    return .green
        case .medium:  return Color(hex: "F5A623")
        case .hard:    return .orange
        case .hardest: return .red
        }
    }

    var badgeLabel: String {
        switch self {
        case .easy:    return "Easy"
        case .medium:  return "Med"
        case .hard:    return "Hard"
        case .hardest: return "MAX"
        }
    }

    var icon: String {
        switch self {
        case .easy:    return "speedometer"
        case .medium:  return "gauge.medium"
        case .hard:    return "gauge.high"
        case .hardest: return "flame.fill"
        }
    }
}

// ── Calculator ─────────────────────────────────────────────────────────────────

enum DifficultyManager {

    /// Calculates difficulty for a specific game within a level,
    /// weighted by level type, complexity, stroke thickness, par time, and undo limit.
    static func calculate(levelType: LevelType, game: Int,
                          settings: GameSettings) -> DifficultyRating {
        var score = 0

        // Base difficulty from the level type
        switch levelType {
        case .linesGuided:   score += 0
        case .linesThin:     score += 20
        case .curvesGuided:  score += 15
        case .curvesThin:    score += 30
        case .shapes:        score += 10
        case .curveShapes:   score += 25
        case .maze:          score += 40
        case .iconObjects:   score += 15
        case .natureFoods:   score += 22
        case .symbolsFaces:  score += 30
        }

        // Connection/segment complexity
        let dotCount = settings.dotCount(forGame: game, levelType: levelType)
        let connCount = LevelGenerator.connectionCount(
            levelType: levelType, dotCount: dotCount, game: game)
        switch connCount {
        case ..<3:   score += 0
        case 3..<5:  score += 5
        case 5..<8:  score += 12
        default:     score += 22
        }

        // Stroke thinness (harder to be accurate on thin lines)
        let thickness = settings.lineThickness(for: levelType)
        if thickness <= 3      { score += 20 }
        else if thickness <= 5 { score += 10 }

        // Par time tightness (less time per connection = harsher penalty)
        let par = settings.parSecondsPerConnection
        if par <= 4      { score += 20 }
        else if par <= 6 { score += 8  }

        // Undo allowance (fewer undos = harder)
        switch settings.maxUndosPerSegment {
        case 0:    score += 15
        case 1:    score += 5
        default:   score += 0
        }

        switch score {
        case ..<25:   return .easy
        case 25..<50: return .medium
        case 50..<72: return .hard
        default:      return .hardest
        }
    }
}
