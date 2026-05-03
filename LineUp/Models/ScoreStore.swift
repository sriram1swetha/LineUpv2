import Foundation
import Combine

struct LineScore: Codable {
    let connectionIndex: Int
    let rawAccuracyScore: Int   // pure accuracy 0-100
    let timeAdjustedScore: Int  // after time penalty
}

struct GameResult: Codable, Identifiable {
    let id: UUID
    let level: Int
    let levelType: LevelType
    let game: Int
    let shapeName: String
    let lineScores: [LineScore]
    let totalScore: Int
    let maxPossibleScore: Int
    let undosUsed: Int
    let timeTaken: Double       // seconds for whole game
    let date: Date

    // Backward-compatible init
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(UUID.self,         forKey: .id)
        level            = try c.decode(Int.self,          forKey: .level)
        levelType        = (try? c.decodeIfPresent(LevelType.self, forKey: .levelType)) ?? .linesGuided
        game             = try c.decode(Int.self,          forKey: .game)
        shapeName        = try c.decode(String.self,       forKey: .shapeName)
        lineScores       = try c.decode([LineScore].self,  forKey: .lineScores)
        totalScore       = try c.decode(Int.self,          forKey: .totalScore)
        maxPossibleScore = try c.decode(Int.self,          forKey: .maxPossibleScore)
        undosUsed        = (try? c.decodeIfPresent(Int.self, forKey: .undosUsed)) ?? 0
        timeTaken        = (try? c.decodeIfPresent(Double.self, forKey: .timeTaken)) ?? 0
        date             = try c.decode(Date.self,         forKey: .date)
    }

    init(id: UUID, level: Int, levelType: LevelType, game: Int, shapeName: String,
         lineScores: [LineScore], totalScore: Int, maxPossibleScore: Int,
         totalTime: Double, undosUsed: Int, date: Date) {
        self.id = id; self.level = level; self.levelType = levelType
        self.game = game; self.shapeName = shapeName; self.lineScores = lineScores
        self.totalScore = totalScore; self.maxPossibleScore = maxPossibleScore
        self.undosUsed = undosUsed; self.timeTaken = totalTime; self.date = date
    }

    var percentage: Double {
        guard maxPossibleScore > 0 else { return 0 }
        return Double(totalScore) / Double(maxPossibleScore) * 100.0
    }

    var grade: String {
        switch percentage {
        case 95...: return "S"
        case 85..<95: return "A"
        case 70..<85: return "B"
        case 50..<70: return "C"
        default: return "D"
        }
    }

    var timeLabel: String {
        let m = Int(timeTaken) / 60, s = Int(timeTaken) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

class ScoreStore: ObservableObject {
    static let shared = ScoreStore()

    @Published private(set) var results: [GameResult] = []
    private let storageKey = "lineup_v2_results"

    private init() { load() }

    func save(result: GameResult) {
        results.append(result)
        persist()
    }

    // ── Unlock / completion ────────────────────────────────────────────────

    func isGameCompleted(level: Int, game: Int) -> Bool {
        bestScore(level: level, game: game) != nil
    }

    func isLevelCompleted(level: Int, gamesPerLevel: Int) -> Bool {
        (1...gamesPerLevel).allSatisfy { isGameCompleted(level: level, game: $0) }
    }

    func isLevelUnlocked(level: Int, gamesPerLevel: Int) -> Bool {
        level == 1 ? true : isLevelCompleted(level: level - 1, gamesPerLevel: gamesPerLevel)
    }

    func isGameUnlocked(level: Int, game: Int) -> Bool {
        game == 1 ? true : isGameCompleted(level: level, game: game - 1)
    }

    // ── Queries ────────────────────────────────────────────────────────────

    func results(forLevel level: Int) -> [GameResult] {
        results.filter { $0.level == level }.sorted { $0.date > $1.date }
    }

    func bestScore(level: Int, game: Int) -> Int? {
        results.filter { $0.level == level && $0.game == game }.map { $0.totalScore }.max()
    }

    func levelBestTotal(level: Int, gamesPerLevel: Int) -> Int {
        (1...gamesPerLevel).compactMap { bestScore(level: level, game: $0) }.reduce(0, +)
    }

    func clearAll() {
        results = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(results) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([GameResult].self, from: data)
        else { return }
        results = decoded
    }
}
