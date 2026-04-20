import SwiftUI

struct GameSelectionView: View {
    let level: Int
    let levelType: LevelType

    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            // Level type info banner
            HStack(spacing: 10) {
                Image(systemName: levelType.isCurve ? "scribble.variable" : "pencil.line")
                    .foregroundStyle(Color(hex: levelType.badgeColor))
                Text(levelType.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...settings.gamesPerLevel, id: \.self) { game in
                    let unlocked = scoreStore.isGameUnlocked(level: level, game: game)
                    if unlocked {
                        NavigationLink(destination: GameView(level: level, game: game, levelType: levelType)) {
                            GameCard(level: level, game: game, levelType: levelType, locked: false)
                        }
                        .buttonStyle(.plain)
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

// ── Game card ──────────────────────────────────────────────────────────────────

struct GameCard: View {
    let level: Int
    let game: Int
    let levelType: LevelType
    let locked: Bool

    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore

    private var dotCount: Int  { settings.dotCount(forGame: game) }
    private var shapeName: String {
        LevelGenerator.previewName(levelType: levelType, dotCount: dotCount, game: game)
    }
    private var best: Int?     { scoreStore.bestScore(level: level, game: game) }
    private var maxScore: Int  {
        LevelGenerator.connectionCount(levelType: levelType, dotCount: dotCount, game: game) * 100
    }
    private var isComplete: Bool { scoreStore.isGameCompleted(level: level, game: game) }
    private var badgeColor: Color { Color(hex: levelType.badgeColor) }

    var body: some View {
        VStack(spacing: 8) {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.largeTitle).foregroundStyle(Color(.tertiaryLabel))
            } else {
                Text(emoji).font(.largeTitle)
            }

            Text("Game \(game)")
                .font(.caption.bold())
                .foregroundStyle(locked ? Color(.tertiaryLabel) : .primary)

            Text(locked ? "Locked" : shapeName)
                .font(.caption2).foregroundStyle(.secondary)

            Divider()

            if locked {
                Text("Play \(game - 1) first")
                    .font(.system(size: 9)).foregroundStyle(Color(.tertiaryLabel))
                    .multilineTextAlignment(.center)
            } else if let b = best {
                HStack(spacing: 4) {
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption2)
                    }
                    Text("\(b)/\(maxScore)")
                        .font(.caption2.bold())
                        .foregroundStyle(gradeColor(b, max: maxScore))
                }
            } else {
                Text("—").font(.caption2).foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 8)
        .background(locked ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(locked ? Color(.systemFill) : badgeColor.opacity(0.2), lineWidth: 1))
        .opacity(locked ? 0.65 : 1.0)
    }

    private var emoji: String {
        if levelType == .shapesGuided { return "🏠" }
        if levelType == .curveShapesGuided { return "🌸" }
        if levelType.isMaze { return "🧩" }
        if levelType.isCurve {
            return dotCount == 2 ? "〰️" : "⭕"
        }
        switch dotCount {
        case 2: return "➖"; case 3: return "🔺"; case 4: return "⬜"
        case 5: return "⬠"; case 6: return "⬡"; default: return "🔷"
        }
    }

    private func gradeColor(_ s: Int, max: Int) -> Color {
        let p = Double(s) / Double(max) * 100
        return p >= 90 ? .green : p >= 70 ? .yellow : .orange
    }
}
