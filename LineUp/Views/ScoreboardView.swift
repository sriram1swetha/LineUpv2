import SwiftUI

// ── Personal scoreboard ────────────────────────────────────────────────────────

struct ScoreboardView: View {
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore
    @State private var selectedLevel = 1

    private var selectedLevelType: LevelType {
        LevelType(rawValue: selectedLevel) ?? .linesGuided
    }
    private var levelResults: [GameResult] {
        scoreStore.results(forLevel: selectedLevel)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Level picker tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LevelType.allCases, id: \.rawValue) { lt in
                        let isSelected = selectedLevel == lt.rawValue
                        let bgColor: Color = isSelected ? Color(hex: lt.badgeColor) : Color(.secondarySystemBackground)
                        let fgColor: Color = isSelected ? .white : .primary
                        Button { selectedLevel = lt.rawValue } label: {
                            Text("L\(lt.rawValue)  \(lt.isCurve ? "〰️" : "—")")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(bgColor)
                                .foregroundStyle(fgColor)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal).padding(.vertical, 10)
            }
            .background(Color(.secondarySystemBackground))

            if levelResults.isEmpty {
                ContentUnavailableView(
                    "No scores yet",
                    systemImage: selectedLevelType.isCurve ? "scribble.variable" : "pencil.slash",
                    description: Text("Play Level \(selectedLevel) to record a score."))
                    .frame(maxHeight: .infinity)
            } else {
                scoreList
            }
        }
        .navigationTitle("My Scores")
        .navigationBarTitleDisplayMode(.large)
    }

    private var scoreList: some View {
        List {
            Section("Best per game — Level \(selectedLevel)") {
                ForEach(1...settings.gamesPerLevel, id: \.self) { game in
                    BestGameRow(game: game, level: selectedLevel,
                                levelType: selectedLevelType,
                                settings: settings, scoreStore: scoreStore)
                }
            }
            Section("Recent plays") {
                ForEach(Array(levelResults.prefix(20)), id: \.id) { result in
                    RecentResultRow(result: result)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// ── Helper row views (keeps body complexity low) ──────────────────────────────

private struct BestGameRow: View {
    let game: Int
    let level: Int
    let levelType: LevelType
    let settings: GameSettings
    let scoreStore: ScoreStore

    var body: some View {
        let dc = settings.dotCount(forGame: game, levelType: levelType)
        let maxPossible = (dc == 2 ? 1 : dc) * 100
        let best = scoreStore.bestScore(level: level, game: game)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(LevelGenerator.shapeName(dotCount: dc, isCurve: levelType.isCurve))
                    .font(.subheadline)
                Text("\(dc) dots").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let b = best {
                let pct = b * 100 / maxPossible
                Text("\(b)/\(maxPossible)")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(pct >= 90 ? Color.green : Color.orange)
            } else {
                Text("—").foregroundStyle(Color(.tertiaryLabel))
            }
        }
    }
}

private struct RecentResultRow: View {
    let result: GameResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.shapeName).font(.subheadline)
                HStack(spacing: 8) {
                    Text(result.date, style: .relative)
                        .font(.caption).foregroundStyle(.secondary)
                    Label(String(format: "%.1fs", result.timeTaken),
                          systemImage: "timer")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(result.totalScore)/\(result.maxPossibleScore)")
                    .font(.subheadline.monospacedDigit().bold())
                Text("Grade: \(result.grade)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// ── CloudKit leaderboard ───────────────────────────────────────────────────────

struct LeaderboardView: View {
    @EnvironmentObject var settings: GameSettings
    @ObservedObject private var ck = CloudKitManager.shared
    @State private var selectedLevel = 1
    @State private var isLoading     = false
    @State private var showThisWeek  = true

    var body: some View {
        VStack(spacing: 0) {
            if !ck.isAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.slash")
                    Text(ck.statusMessage).font(.caption)
                    Spacer()
                    Button("Retry") { ck.retryConnection() }.font(.caption.bold())
                }
                .foregroundStyle(.orange)
                .padding(10).frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.12))
            }

            HStack(spacing: 12) {
                Picker("Level", selection: $selectedLevel) {
                    ForEach(1...LevelType.totalLevels, id: \.self) {
                        let lt = LevelType(rawValue: $0) ?? .linesGuided
                        Text("L\($0) \(lt.title)").tag($0)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedLevel) { _ in refresh() }
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.8) }
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))

            Picker("Period", selection: $showThisWeek) {
                Text("This Week").tag(true)
                Text("All Time").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 6)
            .onChange(of: showThisWeek) { _ in refresh() }

            if !ck.isAvailable {
                ContentUnavailableView("Leaderboard Unavailable", systemImage: "wifi.slash",
                    description: Text(ck.statusMessage)).frame(maxHeight: .infinity)
            } else if ck.leaderboard.isEmpty {
                ContentUnavailableView("No Scores Yet", systemImage: "trophy",
                    description: Text("Be the first to complete this level!")).frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(ck.leaderboard.prefix(10).enumerated()), id: \.offset) { rank, entry in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(rankColor(rank).opacity(0.15)).frame(width: 36, height: 36)
                                Text(rank < 3 ? ["\u{1F947}","\u{1F948}","\u{1F949}"][rank] : "\(rank+1)")
                                    .font(.system(size: rank < 3 ? 18 : 13, weight: .black))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName).font(.headline)
                                Text(entry.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(entry.score)")
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(rankColor(rank))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { refresh() }
    }

    private func refresh() {
        guard ck.isAvailable else { return }
        isLoading = true
        let week = showThisWeek ? CloudKitManager.currentWeekOf : nil
        ck.fetchLeaderboard(level: selectedLevel, weekOf: week)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { isLoading = false }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 0: return .yellow; case 1: return Color(.systemGray)
        case 2: return .orange; default: return .blue
        }
    }
}
