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

    @State private var currentLevel: Int
    @State private var currentGame: Int
    @State private var currentLevelType: LevelType

    @State private var phase: DrawPhase = .idle
    @State private var connectionIndex = 0
    @State private var activePath: [CGPoint] = []
    @State private var finishedStrokes: [FinishedStroke] = []
    @State private var lineScores: [Int] = []
    @State private var redoStack: [StrokeRecord] = []
    @State private var totalUndosUsed = 0

    @State private var flashScore: Int? = nil
    @State private var canvasSize: CGSize = CGSize(width: 350, height: 500)
    @State private var showResult = false
    @State private var resultSaved = false
    @State private var pulseOn = false

    // Ideal line / arc highlight
    @State private var showIdeal = false
    @State private var idealOpacity: Double = 0
    @State private var lastScoredConn: (Int, Int)? = nil

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
            dotCount: settings.dotCount(forGame: currentGame),
            in: canvasSize, dotRadius: settings.dotRadius,
            topReserved: topArrowReserved)
    }
    private var dotR: CGFloat { settings.dotRadius }
    private var lineW: CGFloat { settings.lineThickness(for: currentLevelType) }
    private var totalScore: Int { lineScores.reduce(0, +) }
    private var maxScore: Int { config.connections.count * 100 }
    private var currentConn: (Int, Int)? {
        guard connectionIndex < config.connections.count else { return nil }
        return config.connections[connectionIndex]
    }
    private var canUndo: Bool { !lineScores.isEmpty && phase == .idle }
    private var canRedo: Bool { !redoStack.isEmpty && phase == .idle }
    private var currentGameHasHistory: Bool { scoreStore.bestScore(level: currentLevel, game: currentGame) != nil }
    private var hasPrev: Bool { currentGame > 1 || currentLevel > 1 }
    private var hasNext: Bool {
        guard currentGameHasHistory else { return false }
        return currentGame < settings.gamesPerLevel || currentLevel < LevelType.totalLevels
    }
    private var nextLevelType: LevelType {
        LevelType(rawValue: currentLevel) ?? currentLevelType
    }

    // ── Body ───────────────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            scoreHeader
            ZStack { canvasLayer; topArrows }
            footerBar
        }
        .navigationTitle("Lv \(currentLevel) · Game \(currentGame) · \(config.shapeName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Restart") { restartGame() }
                    .disabled(phase == .idle && lineScores.isEmpty && redoStack.isEmpty)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 2) {
                    Button { performUndo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!canUndo)
                    Button { performRedo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!canRedo)
                }
            }
        }
        .sheet(isPresented: $showResult) {
            GameResultView(
                level: currentLevel, game: currentGame, levelType: currentLevelType,
                shapeName: config.shapeName, lineScores: lineScores,
                totalScore: totalScore, maxScore: maxScore,
                undosUsed: totalUndosUsed,
                onPlayAgain: { showResult = false; restartGame() })
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                pulseOn = true
            }
        }
    }

    // ── Score header ───────────────────────────────────────────────────────

    private var scoreHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Score: \(totalScore) / \(maxScore)").font(.headline)
                if let conn = currentConn {
                    Text(currentLevelType.isCurve
                         ? "Trace arc: dot \(conn.0+1) → dot \(conn.1+1)"
                         : "Draw: dot \(conn.0+1) → dot \(conn.1+1)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
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

                // Guide (straight or arc) — only for levels that have guides
                if let conn = currentConn, phase != .complete, currentLevelType.hasGuide {
                    guideShape(conn: conn)
                }

                // Circle outline hint for curve levels (very faint)
                if currentLevelType.isCurve, let center = config.circleCenter,
                   let radius = config.circleRadius {
                    Circle()
                        .stroke(Color.blue.opacity(0.06), lineWidth: 1)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                }

                // Ideal highlight (appears after each scored stroke)
                if showIdeal, let conn = lastScoredConn {
                    idealHighlight(conn: conn).opacity(idealOpacity)
                }

                // Finished strokes
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

    // ── Guide shape — dashed line or dashed arc ────────────────────────────

    @ViewBuilder
    private func guideShape(conn: (Int, Int)) -> some View {
        let a = config.dots[conn.0], b = config.dots[conn.1]
        if currentLevelType.isCurve,
           let center = config.circleCenter, let radius = config.circleRadius {
            // Dashed arc guide
            ArcPath(center: center, radius: radius, from: a, to: b)
                .stroke(Color.blue.opacity(0.18),
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        } else {
            // Dashed straight line guide
            Path { p in p.move(to: a); p.addLine(to: b) }
                .stroke(Color.blue.opacity(0.12),
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        }
    }

    // ── Ideal highlight — solid green line or arc ──────────────────────────

    @ViewBuilder
    private func idealHighlight(conn: (Int, Int)) -> some View {
        let a = config.dots[conn.0], b = config.dots[conn.1]
        if currentLevelType.isCurve,
           let center = config.circleCenter, let radius = config.circleRadius {
            ArcPath(center: center, radius: radius, from: a, to: b)
                .stroke(Color.green,
                        style: StrokeStyle(lineWidth: lineW + 2, lineCap: .round))
                .shadow(color: .green.opacity(0.55), radius: 6)
        } else {
            Path { p in p.move(to: a); p.addLine(to: b) }
                .stroke(Color.green,
                        style: StrokeStyle(lineWidth: lineW + 2, lineCap: .round))
                .shadow(color: .green.opacity(0.55), radius: 6)
        }
    }

    // ── Top corner arrows ──────────────────────────────────────────────────

    @ViewBuilder
    private var topArrows: some View {
        VStack {
            HStack(alignment: .top) {
                Button { navigatePrev() } label: {
                    Image(systemName: "chevron.left.circle.fill").font(.system(size: 36))
                        .foregroundStyle(hasPrev && phase != .drawing && phase != .reviewing
                            ? Color.blue.opacity(0.85) : Color(.systemFill))
                }
                .disabled(!hasPrev || phase == .drawing || phase == .reviewing)
                .padding(.leading, 10).padding(.top, 10)
                Spacer()
                Button { navigateNext() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.right.circle.fill").font(.system(size: 36))
                            .foregroundStyle(hasNext && phase != .drawing && phase != .reviewing
                                ? Color.blue.opacity(0.85) : Color(.systemFill))
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
        let pos     = config.dots[index]
        let isStart = currentConn?.0 == index && phase != .complete
        let isEnd   = currentConn?.1 == index && phase != .complete
        let fill: Color = isStart ? .green : (isEnd ? .orange : Color(.label))
        let scale: CGFloat = isStart ? (pulseOn ? 1.28 : 1.0) : 1.0
        ZStack {
            Circle().fill(fill.opacity(0.2))
                .frame(width: dotR * 3.5, height: dotR * 3.5).opacity(isStart ? 1 : 0)
            Circle().fill(fill)
                .frame(width: dotR * 2, height: dotR * 2)
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                .scaleEffect(scale).animation(.easeInOut(duration: 0.65), value: scale)
            Text("\(index + 1)")
                .font(.system(size: max(dotR * 0.9, 7), weight: .bold)).foregroundStyle(.white)
        }
        .position(pos)
    }

    @ViewBuilder
    private func scoreFlashView(score: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(score)")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(scoreColor(score))
            Text(scoreLabel(score)).font(.headline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    // ── Footer ─────────────────────────────────────────────────────────────

    private var footerBar: some View {
        Group {
            if phase == .complete {
                Button { showResult = true } label: {
                    Label("View Results", systemImage: "chart.bar.fill")
                        .frame(maxWidth: .infinity).padding().background(Color.blue)
                        .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                }
            } else {
                VStack(spacing: 4) {
                    Text(footerHint).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        if canUndo { Label("Undo", systemImage: "arrow.uturn.backward").font(.caption2).foregroundStyle(.blue) }
                        if canRedo { Label("Redo", systemImage: "arrow.uturn.forward").font(.caption2).foregroundStyle(.blue) }
                        if totalUndosUsed > 0 {
                            Text("\(totalUndosUsed) undo\(totalUndosUsed == 1 ? "" : "s") used")
                                .font(.caption2).foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                }
                .multilineTextAlignment(.center).padding(.horizontal)
            }
        }
        .frame(minHeight: 64).frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    private var footerHint: String {
        switch phase {
        case .idle:
            return currentLevelType.isCurve
                ? "Trace the arc from the green dot ●"
                : "Draw from the green dot ●"
        case .drawing:
            return currentLevelType.isCurve
                ? "Follow the curve — release at the orange dot"
                : "Keep steady — release at the orange dot"
        default: return ""
        }
    }

    // ── Drag gesture ───────────────────────────────────────────────────────

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                switch phase {
                case .idle:
                    guard let conn = currentConn else { return }
                    if ScoringEngine.distance(value.location, config.dots[conn.0]) < dotR * 5 {
                        phase = .drawing; activePath = [value.location]; redoStack = []
                    }
                case .drawing: activePath.append(value.location)
                default: break
                }
            }
            .onEnded { value in
                guard phase == .drawing, let conn = currentConn else { return }
                activePath.append(value.location)
                let startDot = config.dots[conn.0], endDot = config.dots[conn.1]

                // Score: arc or line
                let scoreValue: Int
                if currentLevelType.isCurve,
                   let center = config.circleCenter, let radius = config.circleRadius {
                    scoreValue = ScoringEngine.scoreArc(
                        path: activePath, from: startDot, to: endDot,
                        circleCenter: center, circleRadius: radius, dotRadius: dotR)
                } else {
                    scoreValue = ScoringEngine.score(
                        path: activePath, from: startDot, to: endDot, dotRadius: dotR)
                }

                lineScores.append(scoreValue)
                finishedStrokes.append(FinishedStroke(path: activePath, score: scoreValue))
                activePath = []; phase = .reviewing
                lastScoredConn = conn

                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { flashScore = scoreValue }

                // Ideal highlight
                showIdeal = true
                withAnimation(.easeIn(duration: 0.12)) { idealOpacity = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.45)) { idealOpacity = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showIdeal = false }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.25)) { flashScore = nil }
                    let next = connectionIndex + 1
                    if next >= config.connections.count {
                        connectionIndex = next; phase = .complete
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
        let s = finishedStrokes.removeLast(); let sc = lineScores.removeLast()
        redoStack.append(StrokeRecord(stroke: s, score: sc))
        connectionIndex = max(0, connectionIndex - 1)
        totalUndosUsed += 1; phase = .idle
    }

    private func performRedo() {
        guard canRedo else { return }
        let r = redoStack.removeLast()
        finishedStrokes.append(r.stroke); lineScores.append(r.score)
        connectionIndex += 1
        phase = connectionIndex >= config.connections.count ? .complete : .idle
        if phase == .complete && !resultSaved { saveResult() }
    }

    // ── Navigation ─────────────────────────────────────────────────────────

    private func navigateNext() {
        if currentGame < settings.gamesPerLevel {
            currentGame += 1
        } else {
            let nextLevel = currentLevel + 1
            if let lt = LevelType(rawValue: nextLevel) {
                currentLevel = nextLevel; currentLevelType = lt; currentGame = 1
            }
        }
        restartGame()
    }

    private func navigatePrev() {
        if currentGame > 1 {
            currentGame -= 1
        } else {
            let prevLevel = currentLevel - 1
            if let lt = LevelType(rawValue: prevLevel) {
                currentLevel = prevLevel; currentLevelType = lt
                currentGame = settings.gamesPerLevel
            }
        }
        restartGame()
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    private func pipColor(index: Int) -> Color {
        guard index < lineScores.count else {
            return index == connectionIndex ? Color.blue.opacity(0.4) : Color(.systemFill)
        }
        return scoreColor(lineScores[index])
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
        showIdeal = false; idealOpacity = 0; lastScoredConn = nil
    }

    private func saveResult() {
        guard !resultSaved else { return }
        scoreStore.save(result: GameResult(
            id: UUID(), level: currentLevel, levelType: currentLevelType,
            game: currentGame, shapeName: config.shapeName,
            lineScores: lineScores.enumerated().map { LineScore(connectionIndex: $0.offset, score: $0.element) },
            totalScore: totalScore, maxPossibleScore: maxScore,
            undosUsed: totalUndosUsed, date: Date()))
        resultSaved = true
    }
}

// ── Arc path shape ─────────────────────────────────────────────────────────────

struct ArcPath: Shape {
    let center: CGPoint
    let radius: CGFloat
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let startAngle = Angle(radians: Double(atan2(from.y - center.y, from.x - center.x)))
        var endAngle   = Angle(radians: Double(atan2(to.y   - center.y, to.x   - center.x)))
        // Always take the shorter arc
        var delta = endAngle.radians - startAngle.radians
        while delta >  .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        endAngle = Angle(radians: startAngle.radians + delta)
        p.addArc(center: center, radius: radius,
                 startAngle: startAngle, endAngle: endAngle,
                 clockwise: delta < 0)
        return p
    }
}

// ── Supporting types ───────────────────────────────────────────────────────────

private struct FinishedStroke: Identifiable {
    let id = UUID(); let path: [CGPoint]; let score: Int
}

struct StrokePath: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count >= 2 else { return p }
        p.move(to: points[0]); points.dropFirst().forEach { p.addLine(to: $0) }
        return p
    }
}
