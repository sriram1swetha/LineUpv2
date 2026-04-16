import SwiftUI

struct LevelSelectView: View {
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(LevelType.allCases, id: \.rawValue) { levelType in
                    let level = levelType.rawValue
                    let unlocked = scoreStore.isLevelUnlocked(level: level,
                                                              gamesPerLevel: settings.gamesPerLevel)
                    if unlocked {
                        NavigationLink(destination: GameSelectionView(level: level, levelType: levelType)) {
                            LevelCard(levelType: levelType, locked: false)
                        }
                        .buttonStyle(.plain)
                    } else {
                        LevelCard(levelType: levelType, locked: true)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Select Level")
        .navigationBarTitleDisplayMode(.large)
    }
}

// ── Level card (full-width row) ────────────────────────────────────────────────

struct LevelCard: View {
    let levelType: LevelType
    let locked: Bool

    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore

    private var level: Int { levelType.rawValue }
    private var bestTotal: Int { scoreStore.levelBestTotal(level: level, gamesPerLevel: settings.gamesPerLevel) }
    private var isComplete: Bool { scoreStore.isLevelCompleted(level: level, gamesPerLevel: settings.gamesPerLevel) }
    private var badgeColor: Color { Color(hex: levelType.badgeColor) }

    var body: some View {
        HStack(spacing: 14) {
            // Level number badge
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(locked ? Color(.systemFill) : badgeColor.opacity(0.18))
                    .frame(width: 56, height: 56)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundStyle(Color(.tertiaryLabel))
                } else {
                    VStack(spacing: 2) {
                        Text("\(level)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(badgeColor)
                        Image(systemName: levelType.isCurve ? "scribble.variable" : "pencil.line")
                            .font(.caption2)
                            .foregroundStyle(badgeColor.opacity(0.7))
                    }
                }
            }

            // Description
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(levelType.title)
                        .font(.headline)
                        .foregroundStyle(locked ? Color(.tertiaryLabel) : .primary)
                    if isComplete {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green).font(.caption)
                    }
                }

                Text(locked
                     ? "Complete Level \(level - 1) to unlock"
                     : levelType.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Tags
                if !locked {
                    HStack(spacing: 6) {
                        tag(levelType.isCurve ? "Curves" : "Lines",
                            icon: levelType.isCurve ? "scribble.variable" : "minus",
                            color: badgeColor)
                        tag(levelType.hasGuide ? "Guided" : "No Guide",
                            icon: levelType.hasGuide ? "eye" : "eye.slash",
                            color: levelType.hasGuide ? .green : .orange)
                        if levelType.isThin {
                            tag("Thin", icon: "line.diagonal", color: .gray)
                        }
                    }
                }
            }

            Spacer()

            // Score
            if !locked && bestTotal > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(bestTotal)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(badgeColor)
                    Text("pts")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(locked ? Color(.tertiarySystemBackground) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(locked ? Color(.systemFill) : badgeColor.opacity(0.25), lineWidth: 1))
        .opacity(locked ? 0.7 : 1.0)
    }

    @ViewBuilder
    private func tag(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(label).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
}
