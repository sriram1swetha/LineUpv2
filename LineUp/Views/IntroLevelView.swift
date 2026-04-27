import SwiftUI

// ── Intro Game View ────────────────────────────────────────────────────────────
// Plays through all introGames in sequence. After all 4 are done,
// marks intro complete (which triggers the registration screen).

struct IntroLevelView: View {
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var userSession: UserSession
    @Environment(\.dismiss) private var dismiss

    @State private var currentGameIndex = 0
    @State private var phase: DrawPhase = .idle
    @State private var connectionIndex = 0
    @State private var activePath: [CGPoint] = []
    @State private var finishedStrokes: [FinishedStroke] = []
    @State private var lineScores: [Int] = []
    @State private var flashScore: Int? = nil
    @State private var canvasSize: CGSize = CGSize(width: 350, height: 500)
    @State private var pulseOn = false

    // Blinking path (intro-specific feature)
    @State private var showBlinkHint = false
    @State private var blinkOpacity: Double = 0
    @State private var blinkHintConn: (Int, Int)? = nil

    // Ideal path after score
    @State private var showIdeal = false
    @State private var idealOpacity: Double = 0
    @State private var lastConn: (Int, Int)? = nil

    @State private var introComplete = false

    // ── Derived ────────────────────────────────────────────────────────────

    private var currentIntroGame: IntroGame { introGames[currentGameIndex] }
    private var levelType: LevelType { currentIntroGame.levelType }
    private var dotR: CGFloat { settings.dotRadius }
    private var lineW: CGFloat { settings.lineThickness(for: levelType) }
    private var topReserved: CGFloat { 68 }

    private var config: DotConfiguration {
        LevelGenerator.configuration(
            levelType: levelType,
            dotCount: currentIntroGame.dotCount,
            in: canvasSize, dotRadius: dotR,
            topReserved: topReserved
        )
    }

    private var currentConn: (Int, Int)? {
        guard connectionIndex < config.connections.count else { return nil }
        return config.connections[connectionIndex]
    }

    private var totalScore: Int { lineScores.reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            introHeader
            ZStack(alignment: .top) {
                canvasLayer
                progressDots
            }
            footerBar
        }
        .navigationTitle("Intro · \(currentIntroGame.shapeName)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { pulseOn = true }
            triggerBlinkHint()
        }
        .sheet(isPresented: $introComplete) {
            IntroCompleteView(onContinue: {
                userSession.markIntroComplete()
                dismiss()
            })
        }
    }

    // ── Header ─────────────────────────────────────────────────────────────

    private var introHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Intro \(currentGameIndex + 1) of \(introGames.count)")
                    .font(.headline)
                Text(levelType.subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Level type badge
            Text(levelType.isCurve ? "Curves" : "Lines")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(hex: levelType.badgeColor).opacity(0.15))
                .foregroundStyle(Color(hex: levelType.badgeColor))
                .clipShape(Capsule())
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    // ── Canvas ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private var canvasLayer: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(.systemBackground)

                // Faint circle for curve mode
                if levelType.isCurve, let c = config.circleCenter, let r = config.circleRadius {
                    Circle().stroke(Color.blue.opacity(0.06), lineWidth: 1)
                        .frame(width: r * 2, height: r * 2).position(c)
                }

                // Guide
                if let conn = currentConn, phase != .complete, levelType.hasGuide {
                    guideShape(conn: conn)
                }

                // BLINKING HINT — flashes ideal path before player draws
                if showBlinkHint, let conn = blinkHintConn {
                    idealShape(conn: conn, color: .blue)
                        .opacity(blinkOpacity)
                }

                // Ideal path after scoring
                if showIdeal, let conn = lastConn {
                    idealShape(conn: conn, color: .green).opacity(idealOpacity)
                }

                // Drawn strokes
                ForEach(finishedStrokes) { stroke in
                    StrokePath(points: stroke.path)
                        .stroke(scoreColor(stroke.score).opacity(0.75), lineWidth: lineW)
                }

                // Live stroke
                if !activePath.isEmpty {
                    StrokePath(points: activePath).stroke(Color.blue, lineWidth: lineW)
                }

                // Dots
                ForEach(0..<config.dots.count, id: \.self) { i in dotView(index: i) }

                // Score flash
                if let s = flashScore {
                    scoreFlash(score: s)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, topReserved + 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .gesture(drawGesture)
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { canvasSize = $0 }
        }
    }

    // ── Intro progress dots ────────────────────────────────────────────────

    @ViewBuilder
    private var progressDots: some View {
        VStack {
            HStack(spacing: 8) {
                Spacer()
                ForEach(0..<introGames.count, id: \.self) { i in
                    Circle()
                        .fill(i < currentGameIndex ? Color.green :
                              i == currentGameIndex ? Color.blue : Color(.systemFill))
                        .frame(width: 8, height: 8)
                }
                Spacer()
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    // ── Ideal / guide shapes ───────────────────────────────────────────────

    @ViewBuilder
    private func guideShape(conn: (Int, Int)) -> some View {
        let a = config.dots[conn.0], b = config.dots[conn.1]
        if levelType.isCurve, let c = config.circleCenter, let r = config.circleRadius {
            ArcPath(center: c, radius: r, from: a, to: b)
                .stroke(Color.blue.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        } else {
            Path { p in p.move(to: a); p.addLine(to: b) }
                .stroke(Color.blue.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        }
    }

    @ViewBuilder
    private func idealShape(conn: (Int, Int), color: Color) -> some View {
        let a = config.dots[conn.0], b = config.dots[conn.1]
        if levelType.isCurve, let c = config.circleCenter, let r = config.circleRadius {
            ArcPath(center: c, radius: r, from: a, to: b)
                .stroke(color, style: StrokeStyle(lineWidth: lineW + 2, lineCap: .round))
                .shadow(color: color.opacity(0.5), radius: 6)
        } else {
            Path { p in p.move(to: a); p.addLine(to: b) }
                .stroke(color, style: StrokeStyle(lineWidth: lineW + 2, lineCap: .round))
                .shadow(color: color.opacity(0.5), radius: 6)
        }
    }

    // ── Dots ───────────────────────────────────────────────────────────────

    @ViewBuilder
    private func dotView(index: Int) -> some View {
        let pos = config.dots[index]
        let isStart = currentConn?.0 == index && phase != .complete
        let isEnd   = currentConn?.1 == index && phase != .complete
        let fill: Color = isStart ? .green : isEnd ? .orange : Color(.label)
        let scale: CGFloat = isStart ? (pulseOn ? 1.28 : 1.0) : 1.0
        ZStack {
            Circle().fill(fill.opacity(0.2))
                .frame(width: dotR * 3.5, height: dotR * 3.5).opacity(isStart ? 1 : 0)
            Circle().fill(fill).frame(width: dotR * 2, height: dotR * 2)
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                .scaleEffect(scale).animation(.easeInOut(duration: 0.65), value: scale)
            Text("\(index + 1)")
                .font(.system(size: max(dotR * 0.9, 7), weight: .bold)).foregroundStyle(.white)
        }
        .position(pos)
    }

    @ViewBuilder
    private func scoreFlash(score: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(score)").font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(scoreColor(score))
            Text(scoreLabel(score)).font(.headline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // ── Footer ─────────────────────────────────────────────────────────────

    private var footerBar: some View {
        Text(phase == .idle
             ? (levelType.isCurve ? "Trace the arc from the green dot ●" : "Draw from the green dot ●")
             : "Release at the orange dot")
            .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).padding(.horizontal)
            .frame(minHeight: 48).frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
    }

    // ── Blinking hint (fires once per connection) ──────────────────────────

    private func triggerBlinkHint() {
        guard let conn = currentConn else { return }
        blinkHintConn = conn
        showBlinkHint = true
        // Fade in
        withAnimation(.easeIn(duration: 0.25)) { blinkOpacity = 0.85 }
        // Hold → fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.4)) { blinkOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                showBlinkHint = false
            }
        }
    }

    // ── Draw gesture ───────────────────────────────────────────────────────

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                switch phase {
                case .idle:
                    guard let conn = currentConn else { return }
                    if ScoringEngine.distance(value.location, config.dots[conn.0]) < dotR * 5 {
                        phase = .drawing; activePath = [value.location]
                    }
                case .drawing: activePath.append(value.location)
                default: break
                }
            }
            .onEnded { value in
                guard phase == .drawing, let conn = currentConn else { return }
                activePath.append(value.location)
                let s = config.dots[conn.0], e = config.dots[conn.1]
                let scoreValue: Int
                if levelType.isCurve, let c = config.circleCenter, let r = config.circleRadius {
                    scoreValue = ScoringEngine.scoreArcAccuracy(path: activePath, from: s, to: e,
                                                                circleCenter: c, circleRadius: r, dotRadius: dotR)
                } else {
                    scoreValue = ScoringEngine.scoreAccuracy(path: activePath, from: s, to: e, dotRadius: dotR)
                }
                lineScores.append(scoreValue)
                finishedStrokes.append(FinishedStroke(path: activePath, score: scoreValue))
                activePath = []; phase = .reviewing; lastConn = conn

                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { flashScore = scoreValue }
                showIdeal = true
                withAnimation(.easeIn(duration: 0.12)) { idealOpacity = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.45)) { idealOpacity = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showIdeal = false }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { flashScore = nil }
                    let nextConn = connectionIndex + 1
                    if nextConn >= config.connections.count {
                        // Finished this intro game — move to next
                        connectionIndex = nextConn; phase = .complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            advanceIntroGame()
                        }
                    } else {
                        connectionIndex = nextConn; phase = .idle
                        triggerBlinkHint()
                    }
                }
            }
    }

    private func advanceIntroGame() {
        if currentGameIndex + 1 < introGames.count {
            currentGameIndex += 1
            connectionIndex = 0
            finishedStrokes = []
            lineScores = []
            phase = .idle
            triggerBlinkHint()
        } else {
            introComplete = true
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 85...100: return .green; case 65..<85: return .yellow
        case 35..<65: return .orange; default: return .red
        }
    }
    private func scoreLabel(_ s: Int) -> String {
        switch s {
        case 95...100: return "Perfect! 🎯"; case 80..<95: return "Great! ⭐"
        case 60..<80: return "Good 👍"; default: return "Keep Trying 💪"
        }
    }
}

// ── Intro complete sheet ───────────────────────────────────────────────────────

struct IntroCompleteView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72)).foregroundStyle(.green)
            Text("Intro Complete!")
                .font(.system(size: 28, weight: .black, design: .rounded))
            Text("You've got the basics. Create a free account to save your scores, unlock all levels, and compete on global leaderboards.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Button(action: onContinue) {
                Text("Create Account & Continue")
                    .font(.headline).frame(maxWidth: .infinity).padding()
                    .background(LinearGradient(colors: [Color(hex: "e94560"), Color(hex: "c0392b")],
                                               startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
    }
}

// ── Supporting types ───────────────────────────────────────────────────────────

private enum DrawPhase { case idle, drawing, reviewing, complete }
private struct FinishedStroke: Identifiable { let id = UUID(); let path: [CGPoint]; let score: Int }
