import SwiftUI

// ── Level Select ───────────────────────────────────────────────────────────────

struct LevelSelectView: View {
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(LevelType.allCases, id: \.rawValue) { lt in
                    let level = lt.rawValue
                    let unlocked = scoreStore.isLevelUnlocked(level: level, gamesPerLevel: settings.gamesPerLevel)
                    if unlocked {
                        NavigationLink(destination: GameSelectionView(level: level, levelType: lt)) {
                            LevelCard(levelType: lt, locked: false)
                        }.buttonStyle(.plain)
                    } else {
                        LevelCard(levelType: lt, locked: true)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Select Level").navigationBarTitleDisplayMode(.large)
    }
}

struct LevelCard: View {
    let levelType: LevelType; let locked: Bool
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore

    private var level: Int { levelType.rawValue }
    private var bestTotal: Int { scoreStore.levelBestTotal(level: level, gamesPerLevel: settings.gamesPerLevel) }
    private var isComplete: Bool { scoreStore.isLevelCompleted(level: level, gamesPerLevel: settings.gamesPerLevel) }
    private var badge: Color { Color(hex: levelType.badgeColor) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(locked ? Color(.systemFill) : badge.opacity(0.18)).frame(width: 56, height: 56)
                if locked { Image(systemName: "lock.fill").font(.title2).foregroundStyle(Color(.tertiaryLabel)) }
                else {
                    VStack(spacing: 2) {
                        Text("\(level)").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(badge)
                        Image(systemName: levelType.isCurve ? "scribble.variable" : "pencil.line")
                            .font(.caption2).foregroundStyle(badge.opacity(0.7))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(levelType.title).font(.headline).foregroundStyle(locked ? Color(.tertiaryLabel) : .primary)
                    if isComplete { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption) }
                }
                Text(locked ? "Complete Level \(level-1) to unlock" : levelType.subtitle)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if !locked {
                    HStack(spacing: 6) {
                        tagView(levelType.isCurve ? "Curves" : levelType.isMaze ? "Maze" : levelType.isShapeLevel ? "Shapes" : "Lines",
                                icon: levelType.isCurve ? "scribble.variable" : levelType.isMaze ? "square.grid.3x3" : levelType.isShapeLevel ? "star" : "minus", color: badge)
                        tagView(levelType.hasGuide ? "Guided" : "No Guide",
                                icon: levelType.hasGuide ? "eye" : "eye.slash",
                                color: levelType.hasGuide ? .green : .orange)
                        if levelType.isThin { tagView("Thin", icon: "line.diagonal", color: .gray) }
                    }
                }
            }
            Spacer()
            if !locked && bestTotal > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(bestTotal)").font(.headline.monospacedDigit()).foregroundStyle(badge)
                    Text("pts").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(locked ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(locked ? Color(.systemFill) : badge.opacity(0.25), lineWidth: 1))
        .opacity(locked ? 0.7 : 1.0)
    }

    @ViewBuilder private func tagView(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(label).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.10)).clipShape(Capsule())
    }
}

// ── Game Selection — shape names only, no "Game N" ────────────────────────────

struct GameSelectionView: View {
    let level: Int; let levelType: LevelType
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            HStack(spacing: 8) {
                Image(systemName: levelType.isCurve ? "scribble.variable" : "pencil.line")
                    .foregroundStyle(Color(hex: levelType.badgeColor))
                Text(levelType.subtitle).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal).padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...settings.gamesPerLevel, id: \.self) { game in
                    let unlocked = scoreStore.isGameUnlocked(level: level, game: game)
                    if unlocked {
                        NavigationLink(destination: GameView(level: level, game: game, levelType: levelType)) {
                            GameCard(level: level, game: game, levelType: levelType, locked: false)
                        }.buttonStyle(.plain)
                    } else {
                        GameCard(level: level, game: game, levelType: levelType, locked: true)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Level \(level) · \(levelType.isCurve ? "Curves" : "Lines")")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GameCard: View {
    let level: Int; let game: Int; let levelType: LevelType; let locked: Bool
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore

    private var dotCount: Int { settings.dotCount(forGame: game, levelType: levelType) }
    // Item 5: Use shape name only — no "Game N"
    private var shapeName: String { LevelGenerator.previewName(levelType: levelType, dotCount: dotCount, game: game) }
    private var best: Int?  { scoreStore.bestScore(level: level, game: game) }
    private var maxScore: Int { LevelGenerator.connectionCount(levelType: levelType, dotCount: dotCount, game: game) * 100 }
    private var badge: Color { Color(hex: levelType.badgeColor) }

    var body: some View {
        VStack(spacing: 8) {
            if locked { Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Color(.tertiaryLabel)) }
            else { Text(emoji).font(.largeTitle) }

            // Shape name only — Item 5
            Text(locked ? "Locked" : shapeName)
                .font(.caption.bold())
                .foregroundStyle(locked ? Color(.tertiaryLabel) : .primary)
                .multilineTextAlignment(.center)

            Text("\(dotCount) dots").font(.caption2).foregroundStyle(.secondary)

            Divider()

            if locked {
                Text("Play \(LevelGenerator.previewName(levelType: levelType, dotCount: settings.dotCount(forGame: game-1, levelType: levelType), game: game-1)) first")
                    .font(.system(size: 9)).foregroundStyle(Color(.tertiaryLabel)).multilineTextAlignment(.center)
            } else if let b = best {
                HStack(spacing: 4) {
                    if scoreStore.isGameCompleted(level: level, game: game) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption2)
                    }
                    Text("\(b)/\(maxScore)").font(.caption2.bold()).foregroundStyle(gradeColor(b, max: maxScore))
                }
            } else { Text("—").font(.caption2).foregroundStyle(Color(.tertiaryLabel)) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 8)
        .background(locked ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(locked ? Color(.systemFill) : badge.opacity(0.2), lineWidth: 1))
        .opacity(locked ? 0.65 : 1.0)
    }

    private var emoji: String {
        if levelType == .shapesGuided { return "🏠" }
        if levelType == .curveShapesGuided { return "🌸" }
        if levelType.isMaze { return "🧩" }
        if levelType.isCurve { return dotCount == 2 ? "〰️" : "⭕" }
        switch dotCount {
        case 2: return "➖"; case 3: return "🔺"; case 4: return "⬜"
        case 5: return "⬠"; case 6: return "⬡"; default: return "🔷"
        }
    }
    private func gradeColor(_ s: Int, max: Int) -> Color {
        let p = Double(s)/Double(max)*100; return p>=90 ? .green : p>=70 ? .yellow : .orange
    }
}

// ── Game Result ────────────────────────────────────────────────────────────────

struct GameResultView: View {
    let level: Int; let game: Int; let levelType: LevelType
    let shapeName: String; let lineScores: [LineScore]
    let totalScore: Int; let maxScore: Int; let undosUsed: Int
    let timeTaken: Double; let parTime: Double
    let onPlayAgain: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var pct: Double { maxScore > 0 ? Double(totalScore)/Double(maxScore)*100 : 0 }
    private var grade: String {
        switch pct { case 95...: return "S"; case 85..<95: return "A"
        case 70..<85: return "B"; case 50..<70: return "C"; default: return "D" }
    }
    private var gradeColor: Color {
        switch grade { case "S": return .purple; case "A": return .green
        case "B": return .blue; case "C": return .orange; default: return .red }
    }
    private var timeLabel: String {
        let m = Int(timeTaken)/60, s = Int(timeTaken)%60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
    private var parLabel: String {
        let m = Int(parTime)/60, s = Int(parTime)%60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ZStack {
                        Circle().fill(gradeColor.opacity(0.15)).frame(width: 110, height: 110)
                        Text(grade).font(.system(size: 60, weight: .black, design: .rounded)).foregroundStyle(gradeColor)
                    }.padding(.top, 12)

                    VStack(spacing: 6) {
                        Text(gradeLabel).font(.title.bold())
                        Text("Level \(level) · \(shapeName)").font(.subheadline).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        box("Score", "\(totalScore)", "/ \(maxScore)")
                        box("Accuracy", String(format: "%.0f%%", pct), "")
                        box("Time", timeLabel, "par \(parLabel)")
                        box("Undos", "\(undosUsed)", "used")
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Breakdown").font(.headline).padding(.horizontal).padding(.bottom, 8)
                        ForEach(Array(lineScores.enumerated()), id: \.offset) { idx, ls in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(levelType.isCurve ? "Arc \(idx+1)" : "Line \(idx+1)").font(.subheadline)
                                    Text("Accuracy: \(ls.rawAccuracyScore)  Time-adj: \(ls.timeAdjustedScore)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(.systemFill))
                                        Capsule().fill(bar(ls.timeAdjustedScore))
                                            .frame(width: g.size.width * CGFloat(ls.timeAdjustedScore)/100)
                                    }
                                }.frame(width: 70, height: 8)
                                Text("\(ls.timeAdjustedScore)").font(.subheadline.monospacedDigit().bold())
                                    .foregroundStyle(bar(ls.timeAdjustedScore)).frame(width: 30, alignment: .trailing)
                            }
                            .padding(.horizontal).padding(.vertical, 10)
                            if idx < lineScores.count-1 { Divider().padding(.leading) }
                        }
                    }
                    .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal)

                    VStack(spacing: 10) {
                        Button { dismiss(); onPlayAgain() } label: {
                            Label("Play Again", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity).padding().background(Color.blue)
                                .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button { dismiss() } label: {
                            Text("Back").frame(maxWidth: .infinity).padding()
                                .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }.padding(.horizontal).padding(.bottom, 24)
                }
            }
            .navigationTitle("Results").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder private func box(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.bold())
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            if !sub.isEmpty { Text(sub).font(.system(size: 9)).foregroundStyle(Color(.tertiaryLabel)) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func bar(_ s: Int) -> Color {
        switch s { case 85...100: return .green; case 65..<85: return .yellow
        case 35..<65: return .orange; default: return .red }
    }
    private var gradeLabel: String {
        switch grade { case "S": return "Flawless!"; case "A": return "Excellent!"
        case "B": return "Well Done!"; case "C": return "Not Bad!"; default: return "Keep Practicing" }
    }
}
