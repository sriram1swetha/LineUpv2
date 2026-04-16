import SwiftUI

struct ScoreboardView: View {
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore
    @State private var selectedLevel = 1

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LevelType.allCases, id: \.rawValue) { lt in
                        Button { selectedLevel = lt.rawValue } label: {
                            Text("L\(lt.rawValue)")
                                .font(.caption.bold())
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(selectedLevel == lt.rawValue
                                    ? Color(hex: lt.badgeColor)
                                    : Color(.secondarySystemBackground))
                                .foregroundStyle(selectedLevel == lt.rawValue ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal).padding(.vertical, 10)
            }
            .background(Color(.secondarySystemBackground))

            let levelResults = scoreStore.results(forLevel: selectedLevel)
            let lt = LevelType(rawValue: selectedLevel) ?? .linesWithGuide

            if levelResults.isEmpty {
                ContentUnavailableView(
                    "No scores yet",
                    systemImage: lt.isCurve ? "scribble.variable" : "pencil.slash",
                    description: Text("Play Level \(selectedLevel) to record a score."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    Section("Best Scores — Level \(selectedLevel)") {
                        ForEach(1...settings.gamesPerLevel, id: \.self) { game in
                            let best = scoreStore.bestScore(level: selectedLevel, game: game)
                            let dotCount = settings.dotCount(forGame: game)
                            let maxPossible = (dotCount == 2 ? 1 : dotCount) * 100
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Game \(game) · \(lt.isCurve ? "Arc/Circle" : LevelGenerator.shapeName(dotCount: dotCount))")
                                        .font(.subheadline)
                                    Text("\(dotCount) dots")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let b = best {
                                    Text("\(b)/\(maxPossible)")
                                        .font(.subheadline.monospacedDigit().bold())
                                        .foregroundStyle(b * 100 / maxPossible >= 90 ? .green : .orange)
                                } else {
                                    Text("—").foregroundStyle(Color(.tertiaryLabel))
                                }
                            }
                        }
                    }
                    Section("Recent Plays") {
                        ForEach(levelResults.prefix(20)) { result in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Game \(result.game) · \(result.shapeName)").font(.subheadline)
                                    Text(result.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(result.totalScore)/\(result.maxPossibleScore)")
                                        .font(.subheadline.monospacedDigit().bold())
                                    Text("Grade: \(result.grade)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Scoreboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) { scoreStore.clearAll() } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}
