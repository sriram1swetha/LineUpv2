import SwiftUI

struct GameResultView: View {
    let level: Int
    let game: Int
    let levelType: LevelType
    let shapeName: String
    let lineScores: [Int]
    let totalScore: Int
    let maxScore: Int
    let undosUsed: Int
    let onPlayAgain: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var percentage: Double {
        guard maxScore > 0 else { return 0 }
        return Double(totalScore) / Double(maxScore) * 100
    }
    private var grade: String {
        switch percentage {
        case 95...: return "S"; case 85..<95: return "A"
        case 70..<85: return "B"; case 50..<70: return "C"; default: return "D"
        }
    }
    private var gradeColor: Color {
        switch grade {
        case "S": return .purple; case "A": return .green
        case "B": return .blue; case "C": return .orange; default: return .red
        }
    }
    private var headline: String {
        switch grade {
        case "S": return "Flawless!"; case "A": return "Excellent!"
        case "B": return "Well Done!"; case "C": return "Not Bad!"; default: return "Keep Practicing"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Grade badge
                    ZStack {
                        Circle().fill(gradeColor.opacity(0.15)).frame(width: 110, height: 110)
                        Text(grade)
                            .font(.system(size: 60, weight: .black, design: .rounded))
                            .foregroundStyle(gradeColor)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text(headline).font(.title.bold())
                        Text("Level \(level) · \(levelType.isCurve ? "Curves" : "Lines") · \(shapeName)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        scoreBox(title: "Score",    value: "\(totalScore)", sub: "/ \(maxScore)")
                        scoreBox(title: "Accuracy", value: String(format: "%.0f%%", percentage), sub: "")
                        scoreBox(title: "Undos",    value: "\(undosUsed)",  sub: "used")
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Breakdown").font(.headline).padding(.horizontal).padding(.bottom, 8)
                        ForEach(Array(lineScores.enumerated()), id: \.offset) { idx, s in
                            lineRow(index: idx, score: s)
                            if idx < lineScores.count - 1 { Divider().padding(.leading) }
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal)

                    VStack(spacing: 12) {
                        Button { dismiss(); onPlayAgain() } label: {
                            Label("Play Again", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity).padding().background(Color.blue)
                                .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        Button { dismiss() } label: {
                            Text("Back to Games").frame(maxWidth: .infinity).padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 24)
                }
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder private func scoreBox(title: String, value: String, sub: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
            if !sub.isEmpty { Text(sub).font(.caption2).foregroundStyle(Color(.tertiaryLabel)) }
        }
        .frame(maxWidth: .infinity).padding()
        .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func lineRow(index: Int, score: Int) -> some View {
        HStack {
            Text(levelType.isCurve ? "Arc \(index + 1)" : "Line \(index + 1)").font(.subheadline)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill))
                    Capsule().fill(barColor(score)).frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(width: 80, height: 8)
            Text("\(score)").font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(barColor(score)).frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private func barColor(_ s: Int) -> Color {
        switch s {
        case 85...100: return .green; case 65..<85: return .yellow
        case 35..<65: return .orange; default: return .red
        }
    }
}
