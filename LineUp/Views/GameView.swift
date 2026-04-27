import SwiftUI

private enum DrawPhase { case idle, drawing, reviewing, complete }
private struct StrokeRecord { let stroke: FinishedStroke; let score: Int }
private let topArrowReserved: CGFloat = 68

struct GameView: View {
    let initialLevel: Int
    let initialGame: Int
    let initialLevelType: LevelType

    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var scoreStore: ScoreStore
    @EnvironmentObject var userManager: UserSession
    @Environment(\.dismiss) private var dismiss

    @State private var currentLevel: Int
    @State private var currentGame: Int
    @State private var currentLevelType: LevelType

    @State private var phase: DrawPhase = .idle
    @State private var connectionIndex = 0
    @State private var activePath: [CGPoint] = []
    @State private var finishedStrokes: [FinishedStroke] = []
    @State private var lineScores: [LineScore] = []

    // Undo/Redo per segment
    @State private var redoStack: [StrokeRecord] = []
    @State private var undosThisSegment = 0   // resets each new connection
    @State private var totalUndosUsed = 0

    // UI
    @State private var flashScore: Int? = nil
    @State private var canvasSize: CGSize = CGSize(width: 350, height: 500)
    @State private var showResult = false
    @State private var resultSaved = false
    @State private var pulseOn = false

    // Ideal overlay
    @State private var showIdeal = false
    @State private var idealOpacity: Double = 0
    @State private var lastConn: (Int, Int)? = nil

    // Show ALL ideal paths after game complete (for comparison)
    @State private var showAllIdealPaths = false

    // Timer
    @State private var gameStartTime: Date? = nil
    @State private var elapsedSeconds: Double = 0

    init(level: Int, game: Int, levelType: LevelType) {
        self.initialLevel = level; self.initialGame = game; self.initialLevelType = levelType
        _currentLevel     = State(initialValue: level)
        _currentGame      = State(initialValue: game)
        _currentLevelType = State(initialValue: levelType)
    }

    // ── Derived ────────────────────────────────────────────────────────────

    private var config: DotConfiguration {
        LevelGenerator.configuration(
            levelType: currentLevelType,
            dotCount: settings.dotCount(forGame: currentGame, levelType: currentLevelType),
            in: canvasSize, dotRadius: settings.dotRadius,
            topReserved: topArrowReserved)
    }
    private var dotR: CGFloat { settings.dotRadius }
    private var lineW: CGFloat { settings.lineThickness(for: currentLevelType) }
    private var totalScore: Int { lineScores.reduce(0) { $0 + $1.timeAdjustedScore } }
    private var maxScore: Int { config.connections.count * 100 }
    private var totalTime: Double { elapsedSeconds }
    private var parTime: Double { Double(config.connections.count) * settings.parSecondsPerConnection }

    private var currentConn: (Int, Int)? {
        guard connectionIndex < config.connections.count else { return nil }
        return config.connections[connectionIndex]
    }

    // Undo allowed: not exceeded per-segment limit (0 = unlimited)
    private var canUndo: Bool {
        guard !lineScores.isEmpty, phase == .idle else { return false }
        let max = settings.maxUndosPerSegment
        return max == 0 || undosThisSegment < max
    }
    private var canRedo: Bool { !redoStack.isEmpty && phase == .idle }

    private var currentGameHasHistory: Bool { scoreStore.bestScore(level: currentLevel, game: currentGame) != nil }
    private var hasPrev: Bool { currentGame > 1 || currentLevel > 1 }
    private var hasNext: Bool {
        guard currentGameHasHistory else { return false }
        return currentGame < settings.gamesPerLevel || currentLevel < LevelType.totalLevels
    }

    // ── Body ───────────────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            scoreHeader
            ZStack { canvasLayer; topArrows }
            // FIX: footer is always fixed height, no content shift
            fixedFooter
        }
        .navigationTitle("\(config.shapeName) · Lv\(currentLevel)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Right: Home + Restart as icons
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "house.fill")
                }
                Button { restartGame() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(phase == .idle && lineScores.isEmpty && redoStack.isEmpty)
            }
            // Left: Undo + Redo
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button { performUndo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!canUndo)
                Button { performRedo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!canRedo)
            }
        }
        .sheet(isPresented: $showResult) {
            GameResultView(
                level: currentLevel, game: currentGame, levelType: currentLevelType,
                shapeName: config.shapeName, lineScores: lineScores,
                totalScore: totalScore, maxScore: maxScore,
                undosUsed: totalUndosUsed,
                timeTaken: elapsedSeconds, parTime: parTime,
                onPlayAgain: { showResult = false; restartGame() }
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { pulseOn = true }
        }
    }

    // ── Score header ───────────────────────────────────────────────────────

    private var scoreHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Score: \(totalScore) / \(maxScore)").font(.headline)
                if let conn = currentConn {
                    Text(currentLevelType.isCurve
                         ? "Trace arc: dot \(conn.0+1) → \(conn.1+1)"
                         : "Draw: dot \(conn.0+1) → \(conn.1+1)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Timer
            if gameStartTime != nil || elapsedSeconds > 0 {
                Label(String(format: "%.0fs", elapsedSeconds), systemImage: "timer")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }
            HStack(spacing: 5) {
                ForEach(0..<config.connections.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(pipColor(index: i))
                        .frame(width: 18, height: 8)
                }
            }
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

                // Faint circle for curve levels
                if currentLevelType.isCurve, let c = config.circleCenter, let r = config.circleRadius {
                    Circle().stroke(Color.blue.opacity(0.06), lineWidth: 1)
                        .frame(width: r * 2, height: r * 2).position(c)
                }

                // Guide
                if let conn = currentConn, phase != .complete, currentLevelType.hasGuide {
                    guideShape(conn: conn)
                }

                // ALL ideal paths shown after game complete (comparison)
                if showAllIdealPaths {
                    ForEach(0..<config.connections.count, id: \.self) { i in
                        let conn = config.connections[i]
                        idealShape(conn: conn, color: .green.opacity(0.5))
                    }
                }

                // Per-stroke ideal highlight
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

                // Score flash — upper middle
                if let s = flashScore {
                    scoreFlashView(score: s)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, topArrowReserved + 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .gesture(drawGesture)
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { canvasSize = $0 }
        }
    }

    // ── FIX: Fixed-height footer — no layout shift ─────────────────────────
    // The "View Results" button is now in the toolbar. Footer ONLY shows hints.

    private var fixedFooter: some View {
        VStack(spacing: 4) {
            Text(footerHint).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                if canUndo {
                    Label("Undo", systemImage: "arrow.uturn.backward").font(.caption2).foregroundStyle(.blue)
                }
                if canRedo {
                    Label("Redo", systemImage: "arrow.uturn.forward").font(.caption2).foregroundStyle(.blue)
                }
                if totalUndosUsed > 0 {
                    Text("\(totalUndosUsed) undo\(totalUndosUsed == 1 ? "" : "s") used")
                        .font(.caption2).foregroundStyle(Color(.tertiaryLabel))
                }
                if phase == .complete {
                    Button { if !resultSaved { saveResult() }; showResult = true } label: {
                        Label("View Results", systemImage: "chart.bar.fill")
                            .font(.caption.bold()).foregroundStyle(.blue)
                    }
                }
            }
        }
        .multilineTextAlignment(.center).padding(.horizontal)
        .frame(height: 56)   // FIXED height — never changes
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    private var footerHint: String {
        switch phase {
        case .idle:
            return currentLevelType.isCurve ? "Trace arc from green dot ●" : "Draw from green dot ●"
        case .drawing:
            return "Release at the orange dot"
        case .complete:
            return "Green = ideal path  ·  Colored = your stroke"
        default: return ""
        }
    }

    // ── Top arrows ─────────────────────────────────────────────────────────

    @ViewBuilder
    private var topArrows: some View {
        VStack {
            HStack(alignment: .top) {
                Button { navigatePrev() } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.system(size: 36))
                        .foregroundStyle(hasPrev && phase != .drawing && phase != .reviewing
                            ? Color.blue.opacity(0.85) : Color(.systemFill))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
                .disabled(!hasPrev || phase == .drawing || phase == .reviewing)
                .padding(.leading, 10).padding(.top, 10)
                Spacer()
                Button { navigateNext() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.right.circle.fill").font(.system(size: 36))
                            .foregroundStyle(hasNext && phase != .drawing && phase != .reviewing
                                ? Color.blue.opacity(0.85) : Color(.systemFill))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        if !currentGameHasHistory {
                            Text("Play first").font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                }
                .disabled(!hasNext || phase == .drawing || phase == .reviewing)
                .padding(.trailing, 10).padding(.top, 10)
            }
            Spacer()
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
    private func guideShape(conn: (Int, Int)) -> some View {
        let a = config.dots[conn.0], b = config.dots[conn.1]
        if currentLevelType.isCurve, let c = config.circleCenter, let r = config.circleRadius {
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
        if currentLevelType.isCurve, let c = config.circleCenter, let r = config.circleRadius {
            ArcPath(center: c, radius: r, from: a, to: b)
                .stroke(color, style: StrokeStyle(lineWidth: lineW + 2, lineCap: .round))
                .shadow(color: color.opacity(0.4), radius: 5)
        } else {
            Path { p in p.move(to: a); p.addLine(to: b) }
                .stroke(color, style: StrokeStyle(lineWidth: lineW + 2, lineCap: .round))
                .shadow(color: color.opacity(0.4), radius: 5)
        }
    }

    @ViewBuilder
    private func scoreFlashView(score: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(score)").font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(scoreColor(score))
            Text(scoreLabel(score)).font(.headline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    // ── Draw gesture ───────────────────────────────────────────────────────

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                switch phase {
                case .idle:
                    guard let conn = currentConn else { return }
                    if ScoringEngine.distance(value.location, config.dots[conn.0]) < dotR * 5 {
                        if gameStartTime == nil { gameStartTime = Date() }
                        phase = .drawing; activePath = [value.location]; redoStack = []
                    }
                case .drawing: activePath.append(value.location)
                default: break
                }
            }
            .onEnded { value in
                guard phase == .drawing, let conn = currentConn else { return }
                activePath.append(value.location)
                elapsedSeconds = gameStartTime.map { Date().timeIntervalSince($0) } ?? 0

                let s = config.dots[conn.0], e = config.dots[conn.1]
                let accuracy: Int
                if currentLevelType.isCurve, let c = config.circleCenter, let r = config.circleRadius {
                    accuracy = ScoringEngine.scoreArcAccuracy(path: activePath, from: s, to: e,
                                                              circleCenter: c, circleRadius: r, dotRadius: dotR)
                } else {
                    accuracy = ScoringEngine.scoreAccuracy(path: activePath, from: s, to: e, dotRadius: dotR)
                }

                // Time-adjusted score uses rolling elapsed time
                let timeAdj = ScoringEngine.applyTimePenalty(
                    accuracyScore: accuracy, elapsed: elapsedSeconds, par: parTime)

                lineScores.append(LineScore(connectionIndex: connectionIndex,
                                            rawAccuracyScore: accuracy,
                                            timeAdjustedScore: timeAdj))
                finishedStrokes.append(FinishedStroke(path: activePath, score: timeAdj))
                activePath = []; phase = .reviewing; lastConn = conn
                undosThisSegment = 0   // reset undo counter for next segment

                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { flashScore = timeAdj }

                showIdeal = true
                withAnimation(.easeIn(duration: 0.12)) { idealOpacity = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.45)) { idealOpacity = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showIdeal = false }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { flashScore = nil }
                    let next = connectionIndex + 1
                    if next >= config.connections.count {
                        connectionIndex = next; phase = .complete
                        showAllIdealPaths = true   // show comparison overlay
                        if !resultSaved { saveResult() }
                    } else {
                        connectionIndex = next; phase = .idle
                    }
                }
            }
    }

    // ── Undo / Redo ────────────────────────────────────────────────────────

    private func performUndo() {
        guard canUndo else { return }
        let ls = lineScores.removeLast()
        let fs = finishedStrokes.removeLast()
        redoStack.append(StrokeRecord(stroke: fs, score: ls.timeAdjustedScore))
        connectionIndex = max(0, connectionIndex - 1)
        undosThisSegment += 1; totalUndosUsed += 1; phase = .idle
    }

    private func performRedo() {
        guard canRedo else { return }
        let r = redoStack.removeLast()
        finishedStrokes.append(r.stroke)
        // Rebuild a synthetic LineScore for redo
        lineScores.append(LineScore(connectionIndex: connectionIndex,
                                    rawAccuracyScore: r.score,
                                    timeAdjustedScore: r.score))
        connectionIndex += 1
        phase = connectionIndex >= config.connections.count ? .complete : .idle
        if phase == .complete { showAllIdealPaths = true; if !resultSaved { saveResult() } }
    }

    // ── Navigation ─────────────────────────────────────────────────────────

    private func navigateNext() {
        if currentGame < settings.gamesPerLevel { currentGame += 1 }
        else if let lt = LevelType(rawValue: currentLevel + 1) {
            currentLevel += 1; currentLevelType = lt; currentGame = 1
        }
        restartGame()
    }

    private func navigatePrev() {
        if currentGame > 1 { currentGame -= 1 }
        else if let lt = LevelType(rawValue: currentLevel - 1) {
            currentLevel -= 1; currentLevelType = lt; currentGame = settings.gamesPerLevel
        }
        restartGame()
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private func pipColor(index: Int) -> Color {
        guard index < lineScores.count else {
            return index == connectionIndex ? Color.blue.opacity(0.4) : Color(.systemFill)
        }
        return scoreColor(lineScores[index].timeAdjustedScore)
    }

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 85...100: return .green; case 65..<85: return .yellow
        case 35..<65: return .orange; default: return .red
        }
    }

    private func scoreLabel(_ s: Int) -> String {
        switch s {
        case 95...100: return "Perfect! 🎯"; case 80..<95: return "Great! ⭐"
        case 60..<80: return "Good 👍"; case 20..<60: return "Keep Trying 💪"
        default: return "Missed! ❌"
        }
    }

    private func restartGame() {
        phase = .idle; connectionIndex = 0; activePath = []
        finishedStrokes = []; lineScores = []; flashScore = nil
        resultSaved = false; redoStack = []; totalUndosUsed = 0
        undosThisSegment = 0; showIdeal = false; idealOpacity = 0
        lastConn = nil; showAllIdealPaths = false
        gameStartTime = nil; elapsedSeconds = 0
    }

    private func saveResult() {
        guard !resultSaved else { return }
        let result = GameResult(
            id: UUID(), level: currentLevel, levelType: currentLevelType,
            game: currentGame, shapeName: config.shapeName,
            lineScores: lineScores,
            totalScore: totalScore, maxPossibleScore: maxScore,
            totalTime: elapsedSeconds, undosUsed: totalUndosUsed, date: Date()
        )
        scoreStore.save(result: result)
        CloudKitManager.shared.submitScore(
            displayName: userManager.displayName,
            level: currentLevel, game: currentGame,
            score: totalScore, totalTime: elapsedSeconds)
        resultSaved = true
    }
}

// ── Supporting types ───────────────────────────────────────────────────────────

private struct FinishedStroke: Identifiable { let id = UUID(); let path: [CGPoint]; let score: Int }

struct StrokePath: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count >= 2 else { return p }
        p.move(to: points[0]); points.dropFirst().forEach { p.addLine(to: $0) }
        return p
    }
}

struct ArcPath: Shape {
    let center: CGPoint; let radius: CGFloat; let from: CGPoint; let to: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let sa = Angle(radians: Double(atan2(from.y - center.y, from.x - center.x)))
        var delta = atan2(to.y - center.y, to.x - center.x) - atan2(from.y - center.y, from.x - center.x)
        while delta >  .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        let ea = Angle(radians: sa.radians + Double(delta))
        p.addArc(center: center, radius: radius, startAngle: sa, endAngle: ea, clockwise: delta < 0)
        return p
    }
}
