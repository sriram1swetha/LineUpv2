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
    @EnvironmentObject var navigator: Navigator

    @State private var currentLevel: Int
    @State private var currentGame: Int
    @State private var currentLevelType: LevelType

    @State private var phase: DrawPhase = .idle
    @State private var connectionIndex = 0
    @State private var activePath: [CGPoint] = []
    @State private var finishedStrokes: [FinishedStroke] = []
    @State private var lineScores: [LineScore] = []
    @State private var redoStack: [StrokeRecord] = []
    @State private var undosThisSegment = 0    // resets each new connection
    @State private var totalUndosUsed = 0

    @State private var flashScore: Int? = nil
    @State private var canvasSize: CGSize = CGSize(width: 350, height: 500)
    @State private var resultSaved = false
    @State private var pulseOn = false

    // Timer
    @State private var gameStartTime: Date? = nil
    @State private var segmentStartTime: Date? = nil
    @State private var elapsedSeconds: Double = 0

    // Ideal line / arc highlight
    @State private var showIdeal = false
    @State private var idealOpacity: Double = 0
    @State private var lastScoredConnIndex: Int? = nil

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
            game: currentGame,
            in: canvasSize, dotRadius: settings.dotRadius,
            topReserved: topArrowReserved)
    }
    private var dotR: CGFloat { settings.dotRadius }
    private var lineW: CGFloat { settings.lineThickness(for: currentLevelType) }
    private var totalScore: Int { lineScores.reduce(0) { $0 + $1.timeAdjustedScore } }
    private var maxScore: Int { config.connections.count * 100 }
    private var parTime: Double { Double(config.connections.count) * settings.parSecondsPerConnection }
    private var currentConn: (Int, Int)? {
        guard connectionIndex < config.connections.count else { return nil }
        return config.connections[connectionIndex]
    }
    // Undo allowed: not exceeded per-segment limit (0 = unlimited)
    private var canUndo: Bool {
        guard !lineScores.isEmpty && (phase == .idle || phase == .complete) else { return false }
        let max = settings.maxUndosPerSegment
        return max == 0 || undosThisSegment < max
    }
    private var canRedo: Bool { !redoStack.isEmpty && (phase == .idle || phase == .complete) }
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
        .navigationTitle("Lv \(currentLevel) · \(config.shapeName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { restartGame() } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.title3)
                }
                .disabled(phase == .idle && lineScores.isEmpty && redoStack.isEmpty)

                Button { navigator.goHome() } label: {
                    Image(systemName: "house.circle.fill")
                        .font(.title3)
                }
            }
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
                HStack(spacing: 8) {
                    Text("Score: \(totalScore) / \(maxScore)").font(.headline)
                    if gameStartTime != nil || elapsedSeconds > 0 {
                        Label(String(format: "%.0fs", elapsedSeconds), systemImage: "timer")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
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

                // Guide (straight or arc). Curves ALWAYS show the dashed
                // guide — tracing a partial arc freehand without any visual
                // reference is essentially guesswork. Straight-line levels
                // follow the per-level `hasGuide` flag.
                if let conn = currentConn, phase != .complete,
                   (currentLevelType.hasGuide || currentLevelType.isCurve) {
                    guideShape(conn: conn)
                }

                // Faint circle outline hint for classic full-circle curve games.
                if currentLevelType.isCurve,
                   config.perConnectionArcs == nil,
                   let center = config.circleCenter,
                   let radius = config.circleRadius {
                    Circle()
                        .stroke(Color.blue.opacity(0.06), lineWidth: 1)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                }

                // Maze walls — thick red/brown lines the player must avoid.
                if let walls = config.walls {
                    ForEach(0..<walls.count, id: \.self) { i in
                        Path { p in
                            p.move(to: walls[i].0)
                            p.addLine(to: walls[i].1)
                        }
                        .stroke(Color(hex: "8B4513").opacity(0.85),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                }

                // Ideal highlight (appears after each scored stroke)
                if showIdeal, let idx = lastScoredConnIndex,
                   idx < config.connections.count {
                    idealHighlight(connectionIndex: idx).opacity(idealOpacity)
                }

                // On completion: show ALL ideal paths so the player can
                // compare their drawn lines with the expected paths.
                if phase == .complete {
                    ForEach(0..<config.connections.count, id: \.self) { idx in
                        idealHighlight(connectionIndex: idx).opacity(0.4)
                    }
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
           let arc = config.arcInfo(for: connectionIndex) {
            // Dashed arc guide
            ArcPath(center: arc.center, radius: arc.radius, from: a, to: b)
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
    private func idealHighlight(connectionIndex idx: Int) -> some View {
        let conn = config.connections[idx]
        let a = config.dots[conn.0], b = config.dots[conn.1]
        if currentLevelType.isCurve,
           let arc = config.arcInfo(for: idx) {
            ArcPath(center: arc.center, radius: arc.radius, from: a, to: b)
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
            HStack(alignment: .top, spacing: 0) {

                // ◀ Previous game
                VStack(spacing: 2) {
                    Button { navigatePrev() } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(hasPrev && phase != .drawing && phase != .reviewing
                                ? Color.blue.opacity(0.85) : Color(.systemFill))
                    }
                    .disabled(!hasPrev || phase == .drawing || phase == .reviewing)
                    Text("Prev").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.leading, 10).padding(.top, 8)

                Spacer()

                // ↶ Undo — between the two chevrons, always accessible,
                // including after completion (so the last stroke can be undone).
                VStack(spacing: 2) {
                    Button { performUndo() } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(canUndo ? Color.blue.opacity(0.85) : Color(.systemFill))
                    }
                    .disabled(!canUndo)
                    Text("Undo").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(canUndo ? Color.blue.opacity(0.75) : Color(.tertiaryLabel))
                }
                .padding(.top, 8)

                Spacer().frame(width: 8)

                // ↷ Redo
                VStack(spacing: 2) {
                    Button { performRedo() } label: {
                        Image(systemName: "arrow.uturn.forward.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(canRedo ? Color.blue.opacity(0.85) : Color(.systemFill))
                    }
                    .disabled(!canRedo)
                    Text("Redo").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(canRedo ? Color.blue.opacity(0.75) : Color(.tertiaryLabel))
                }
                .padding(.top, 8)

                Spacer()

                // ▶ Next game
                VStack(spacing: 2) {
                    Button { navigateNext() } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(hasNext && phase != .drawing && phase != .reviewing
                                ? Color.blue.opacity(0.85) : Color(.systemFill))
                    }
                    .disabled(!hasNext || phase == .drawing || phase == .reviewing)
                    Text(currentGameHasHistory ? "Next" : "Play first")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.trailing, 10).padding(.top, 8)
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
            if currentLevelType.showsDotNumbers {
                Text("\(index + 1)")
                    .font(.system(size: max(dotR * 0.9, 7), weight: .bold)).foregroundStyle(.white)
            }
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
        VStack(spacing: 4) {
            if phase == .complete {
                Label("Complete! Score: \(totalScore)/\(maxScore)", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold()).foregroundStyle(.green)
            } else {
                Text(footerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if totalUndosUsed > 0 {
                Text("\(totalUndosUsed) undo\(totalUndosUsed == 1 ? "" : "s") used")
                    .font(.caption2)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(height: 52).frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    private var footerHint: String {
        switch phase {
        case .idle:
            if currentLevelType.isMaze {
                return "Navigate from green dot ● — avoid the walls!"
            }
            return currentLevelType.isCurve
                ? "Trace the arc from the green dot ●"
                : "Draw from the green dot ●"
        case .drawing:
            if currentLevelType.isMaze {
                return settings.continuousDrawing
                    ? "Stay clear of walls — pass through the orange dot ●"
                    : "Stay clear of walls — release at the orange dot"
            }
            if settings.continuousDrawing {
                return currentLevelType.isCurve
                    ? "Follow the curve through the orange dot ●"
                    : "Keep steady — pass through the orange dot ●"
            }
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
                        if gameStartTime == nil { gameStartTime = Date() }
                        if segmentStartTime == nil { segmentStartTime = Date() }
                    }

                case .drawing:
                    activePath.append(value.location)

                    // ── Continuous drawing ─────────────────────────────
                    // Score as soon as the finger reaches the end dot,
                    // then seamlessly start drawing the next connection
                    // without the user having to lift their finger.
                    if settings.continuousDrawing, let conn = currentConn {
                        let endDot   = config.dots[conn.1]
                        let startDot = config.dots[conn.0]
                        let distEnd   = ScoringEngine.distance(value.location, endDot)
                        let distStart = ScoringEngine.distance(value.location, startDot)
                        // Finger must be ON the end dot (≤ 1.5 radii from center)
                        // AND must have moved away from the start dot first.
                        if distEnd < dotR * 1.5 && distStart > dotR * 2.5 {
                            completeCurrentStroke(continuous: true,
                                                  fingerLocation: value.location)
                        }
                    }

                default: break
                }
            }
            .onEnded { value in
                guard phase == .drawing else { return }

                if settings.continuousDrawing {
                    // Continuous mode: if the finger lifts before reaching
                    // the end dot, discard the incomplete stroke silently.
                    activePath = []; phase = .idle
                    return
                }

                // ── Classic (non-continuous) mode ─────────────────────
                activePath.append(value.location)
                completeCurrentStroke(continuous: false, fingerLocation: value.location)
            }
    }

    /// Score the current stroke, record it, advance to the next connection.
    ///
    /// - `continuous`: when `true`, uses a short flash (0.6 s), skips the
    ///   ideal-line overlay, and chains into the next stroke if the next
    ///   connection starts at the same dot the current one ends at.
    /// - `fingerLocation`: where the finger is right now, used to seed the
    ///   next stroke's `activePath` when chaining.
    private func completeCurrentStroke(continuous: Bool,
                                       fingerLocation: CGPoint) {
        guard let conn = currentConn else { return }
        let startDot = config.dots[conn.0], endDot = config.dots[conn.1]

        // Snap the stroke endpoints to the actual dot centers so the
        // rendered line visually touches both dots.
        if !activePath.isEmpty {
            activePath[0] = startDot
            activePath.append(endDot)
        }

        // ── Score ───────────────────────────────────────────────
        let accuracy: Int
        if let walls = config.walls, !walls.isEmpty {
            accuracy = ScoringEngine.scoreMaze(
                path: activePath, from: startDot, to: endDot,
                dotRadius: dotR, walls: walls)
        } else if currentLevelType.isCurve,
           let arc = config.arcInfo(for: connectionIndex) {
            accuracy = ScoringEngine.scoreArc(
                path: activePath, from: startDot, to: endDot,
                circleCenter: arc.center, circleRadius: arc.radius, dotRadius: dotR)
        } else {
            accuracy = ScoringEngine.score(
                path: activePath, from: startDot, to: endDot, dotRadius: dotR)
        }

        // Update elapsed time
        elapsedSeconds = gameStartTime.map { Date().timeIntervalSince($0) } ?? 0

        // Apply time penalty
        let adjusted = ScoringEngine.applyTimePenalty(
            accuracyScore: accuracy, elapsed: elapsedSeconds, par: parTime)

        lineScores.append(LineScore(connectionIndex: connectionIndex,
                                     rawAccuracyScore: accuracy,
                                     timeAdjustedScore: adjusted))
        finishedStrokes.append(FinishedStroke(path: activePath, score: adjusted))
        lastScoredConnIndex = connectionIndex

        // Score flash (both modes)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { flashScore = adjusted }

        let nextIdx = connectionIndex + 1

        if continuous {
            // ── Continuous: short flash, no ideal overlay ────────
            let captured = adjusted
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if flashScore == captured {
                    withAnimation(.easeOut(duration: 0.2)) { flashScore = nil }
                }
            }

            if nextIdx >= config.connections.count {
                connectionIndex = nextIdx; activePath = []; phase = .complete
                if !resultSaved { saveResult() }
            } else {
                connectionIndex = nextIdx; undosThisSegment = 0; segmentStartTime = Date()
                let nextConn = config.connections[nextIdx]
                if nextConn.0 == conn.1 {
                    // Chained — next connection starts where this one ended.
                    // Begin a new activePath immediately at the finger.
                    activePath = [fingerLocation]
                    // phase stays .drawing
                } else {
                    // Not chained — user must lift and re-start from a
                    // different dot.
                    activePath = []; phase = .idle
                }
            }
        } else {
            // ── Classic: ideal highlight + 1.5 s reviewing pause ─
            activePath = []; phase = .reviewing

            showIdeal = true
            withAnimation(.easeIn(duration: 0.12)) { idealOpacity = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.45)) { idealOpacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showIdeal = false }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.25)) { flashScore = nil }
                if nextIdx >= config.connections.count {
                    connectionIndex = nextIdx; phase = .complete
                    if !resultSaved { saveResult() }
                } else {
                    connectionIndex = nextIdx; undosThisSegment = 0
                    segmentStartTime = Date(); phase = .idle
                }
            }
        }
    }

    // ── Undo / Redo ────────────────────────────────────────────────────────

    private func performUndo() {
        guard canUndo else { return }
        let s = finishedStrokes.removeLast(); let sc = lineScores.removeLast()
        redoStack.append(StrokeRecord(stroke: s, score: sc.timeAdjustedScore))
        connectionIndex = max(0, connectionIndex - 1)
        totalUndosUsed += 1; undosThisSegment += 1
        phase = .idle
        resultSaved = false
        showIdeal = false; idealOpacity = 0; flashScore = nil
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
        undosThisSegment = 0
        showIdeal = false; idealOpacity = 0; lastScoredConnIndex = nil
        gameStartTime = nil; segmentStartTime = nil; elapsedSeconds = 0
    }

    private func saveResult() {
        guard !resultSaved else { return }
        scoreStore.save(result: GameResult(
            id: UUID(), level: currentLevel, levelType: currentLevelType,
            game: currentGame, shapeName: config.shapeName,
            lineScores: lineScores,
            totalScore: totalScore, maxPossibleScore: maxScore,
            totalTime: elapsedSeconds, undosUsed: totalUndosUsed, date: Date()))
        resultSaved = true

        // Submit to CloudKit leaderboard
        if UserSession.shared.isGamer {
            CloudKitManager.shared.submitScore(
                displayName: UserSession.shared.displayName,
                level: currentLevel, game: currentGame,
                score: totalScore, totalTime: elapsedSeconds)
        }
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
