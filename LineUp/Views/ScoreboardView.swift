import SwiftUI

// ── Scoreboard (personal scores) ──────────────────────────────────────────────

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
                            Text("L\(lt.rawValue)  \(lt.isCurve ? "〰️" : "—")")
                                .font(.caption.bold()).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(selectedLevel == lt.rawValue
                                    ? Color(hex: lt.badgeColor) : Color(.secondarySystemBackground))
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
                ContentUnavailableView("No scores yet",
                    systemImage: lt.isCurve ? "scribble.variable" : "pencil.slash",
                    description: Text("Play Level \(selectedLevel) to record a score."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    Section("Best per game — Level \(selectedLevel)") {
                        ForEach(1...settings.gamesPerLevel, id: \.self) { game in
                            let dc = settings.dotCount(forGame: game, levelType: lt)
                            let maxPossible = (dc == 2 ? 1 : dc) * 100
                            let best = scoreStore.bestScore(level: selectedLevel, game: game)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LevelGenerator.shapeName(dotCount: dc, isCurve: lt.isCurve)).font(.subheadline)
                                    Text("\(dc) dots").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let b = best {
                                    Text("\(b)/\(maxPossible)").font(.subheadline.monospacedDigit().bold())
                                        .foregroundStyle(b*100/maxPossible >= 90 ? .green : .orange)
                                } else { Text("—").foregroundStyle(Color(.tertiaryLabel)) }
                            }
                        }
                    }
                    Section("Recent plays") {
                        ForEach(levelResults.prefix(20)) { result in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.shapeName).font(.subheadline)
                                    HStack(spacing: 8) {
                                        Text(result.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                                        Label(result.timeLabel, systemImage: "timer").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(result.totalScore)/\(result.maxPossibleScore)").font(.subheadline.monospacedDigit().bold())
                                    Text("Grade: \(result.grade)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("My Scores").navigationBarTitleDisplayMode(.large)
    }
}

// ── Leaderboard (CloudKit) ─────────────────────────────────────────────────────

struct LeaderboardView: View {
    @EnvironmentObject var settings: GameSettings
    @StateObject private var ck = CloudKitManager.shared
    @State private var selectedLevel = 1
    @State private var selectedGame  = 1
    @State private var isLoading = false

    private var lt: LevelType { LevelType(rawValue: selectedLevel) ?? .linesWithGuide }

    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack(spacing: 12) {
                Picker("Level", selection: $selectedLevel) {
                    ForEach(1...LevelType.totalLevels, id: \.self) { Text("L\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedLevel) { _ in refresh() }

                Picker("Game", selection: $selectedGame) {
                    ForEach(1...settings.gamesPerLevel, id: \.self) {
                        let dc = settings.dotCount(forGame: $0, levelType: lt)
                        Text(LevelGenerator.shapeName(dotCount: dc, isCurve: lt.isCurve)).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedGame) { _ in refresh() }

                Spacer()
                if isLoading { ProgressView().scaleEffect(0.8) }
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))

            if let err = ck.errorMessage {
                ContentUnavailableView("Leaderboard Unavailable",
                    systemImage: "wifi.slash", description: Text(err))
                    .frame(maxHeight: .infinity)
            } else if ck.leaderboardEntries.isEmpty {
                ContentUnavailableView("No Scores Yet",
                    systemImage: "trophy",
                    description: Text("Be the first to complete this game!"))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(ck.leaderboardEntries.prefix(50).enumerated()), id: \.offset) { rank, entry in
                        HStack(spacing: 12) {
                            // Rank badge
                            ZStack {
                                Circle()
                                    .fill(rankColor(rank).opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Text("\(rank+1)")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundStyle(rankColor(rank))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName).font(.headline)
                                Text(entry.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(entry.totalScore)").font(.title3.bold().monospacedDigit())
                                .foregroundStyle(rankColor(rank))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Leaderboard").navigationBarTitleDisplayMode(.large)
        .onAppear { refresh() }
    }

    private func refresh() {
        isLoading = true
        Task {
            await ck.checkAvailability()
            await ck.fetchLeaderboard(level: selectedLevel, game: selectedGame)
            isLoading = false
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank { case 0: return .yellow; case 1: return Color(.systemGray); case 2: return .orange; default: return .blue }
    }
}
