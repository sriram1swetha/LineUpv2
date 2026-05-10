import SwiftUI
import AudioToolbox

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

    // Guide flash — briefly highlights the expected path as a solid line
    // before fading to the dashed guide.
    @State private var guideFlashOpacity: Double = 0

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
    // Undo: first undo per segment is free, additional cost 1 silver each
    private var hasUndoableStrokes: Bool {
        !lineScores.isEmpty && (phase == .idle || phase == .complete)
    }
    private var isFreeUndo: Bool { undosThisSegment < 1 }
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

    // ── Coin animation state ────────────────────────────────────────────────
    @State private var showCopperAnim = false
    @State private var showSilverAnim = false
    @State private var showGoldAnim   = false
    @State private var copperAwarded  = 0
    @State private var silverAwarded  = 0
    @State private var goldAwarded    = 0
    @State private var showGuestRegisterPrompt = false
    @State private var showPaidUndoAlert = false
    @State private var showRetryCostAlert = false

    // ── Body ───────────────────────────────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            ZStack { canvasLayer; topArrows; flyingCoinOverlay }
            footerBar
        }
        .navigationTitle("Lv \(currentLevel) · \(config.shapeName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { handleRestartTap() } label: {
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
        .alert("Ready for more?", isPresented: $showGuestRegisterPrompt) {
            Button("Register Now") {
                UserSession.shared.hasCompletedIntro = true
            }
            Button("Keep Playing", role: .cancel) { }
        } message: {
            Text("Sign in to unlock all levels, save scores to the leaderboard, and earn coins across sessions!")
        }
        .alert("Extra Undo", isPresented: $showPaidUndoAlert) {
            Button("Spend 1 Silver Coin") {
                if UserSession.shared.silverCoins >= 1 {
                    UserSession.shared.silverCoins -= 1
                    performUndo()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("First undo is free. Each extra undo costs 1 Silver coin.\n\nYou have \(UserSession.shared.silverCoins) Silver coins.")
        }
        .alert("Retry Game", isPresented: $showRetryCostAlert) {
            Button("Spend 1 Gold Coin") {
                if UserSession.shared.goldCoins >= 1 {
                    UserSession.shared.goldCoins -= 1
                    restartGame()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Full retry costs 1 Gold coin.\n\nYou have \(UserSession.shared.goldCoins) Gold coins.")
        }
    }

    // ── Top strip: Chest + connection hint + pips ──────────────────────────

    private var topStrip: some View {
        HStack(spacing: 10) {
            // Chest icon with coin counts
            HStack(spacing: 4) {
                Image(systemName: "shippingbox.fill")
                    .font(.title3).foregroundStyle(Color(hex: "f5a623"))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Circle().fill(Color(hex: "CD7F32")).frame(width: 8, height: 8)
                        Text("\(UserSession.shared.copperCoins)").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: "CD7F32"))
                    }
                    HStack(spacing: 3) {
                        Circle().fill(Color(.systemGray)).frame(width: 8, height: 8)
                        Text("\(UserSession.shared.silverCoins)").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 3) {
                        Circle().fill(Color(hex: "FFD700")).frame(width: 8, height: 8)
                        Text("\(UserSession.shared.goldCoins)").font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: "FFD700"))
                    }
                }
            }

            Spacer()

            // Connection hint
            if phase == .complete {
                Text("All connections drawn ✓")
                    .font(.caption).foregroundStyle(.green)
            } else if let conn = currentConn {
                Text("dot \(conn.0+1) → dot \(conn.1+1)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            // Score pips
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

                // Guide (straight or arc) — always shown for every level.
                if let conn = currentConn, phase != .complete {
                    // Solid "preview flash" — briefly highlights the expected
                    // path so the gamer sees exactly what to draw.
                    idealHighlight(connectionIndex: connectionIndex)
                        .opacity(guideFlashOpacity)

                    // Permanent dashed guide line
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
            .onAppear {
                canvasSize = geo.size
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { flashGuide() }
            }
            .onChange(of: geo.size) { canvasSize = $0 }
        }
    }

    // ── Guide shape — dashed line or dashed arc ────────────────────────────

    @ViewBuilder
    private func guideShape(conn: (Int, Int)) -> some View {
        let a = config.dots[conn.0], b = config.dots[conn.1]
        if currentLevelType.isCurve,
           let arc = config.arcInfo(for: connectionIndex) {
            ArcPath(center: arc.center, radius: arc.radius, from: a, to: b)
                .stroke(Color.blue.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        } else {
            Path { p in p.move(to: a); p.addLine(to: b) }
                .stroke(Color.blue.opacity(0.20),
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

                // ↶ Undo — first per segment is free, extras cost 1 silver
                VStack(spacing: 2) {
                    Button { handleUndoTap() } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(hasUndoableStrokes ? Color.blue.opacity(0.85) : Color(.systemFill))
                    }
                    .disabled(!hasUndoableStrokes)
                    Text(isFreeUndo ? "Undo" : "Undo 🪙")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(hasUndoableStrokes ? Color.blue.opacity(0.75) : Color(.tertiaryLabel))
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
            // Coin animation overlays
            if showCopperAnim || showSilverAnim || showGoldAnim {
                coinAnimationBanner
            }

            HStack(spacing: 12) {
                // Score
                VStack(spacing: 1) {
                    Text("Score").font(.system(size: 9)).foregroundStyle(.secondary)
                    Text("\(totalScore)/\(maxScore)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }

                // Percentage
                VStack(spacing: 1) {
                    Text("Accuracy").font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(maxScore > 0 ? "\(totalScore * 100 / maxScore)%" : "—")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(scoreColor(maxScore > 0 ? totalScore * 100 / maxScore : 0))
                }

                // Time
                VStack(spacing: 1) {
                    Text("Time").font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(elapsedSeconds > 0 ? String(format: "%.1fs", elapsedSeconds) : "—")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }

                Spacer()

                // Status + hint
                if phase == .complete {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.green)
                } else {
                    Text(footerHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if totalUndosUsed > 0 {
                Text("\(totalUndosUsed) undo\(totalUndosUsed == 1 ? "" : "s") used")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 56).frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    // ── Coin animation banner ─────────────────────────────────────────────

    private var coinAnimationBanner: some View {
        // Summary text showing what was awarded (appears in footer)
        HStack(spacing: 16) {
            if showCopperAnim && copperAwarded > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill").font(.system(size: 10))
                        .foregroundStyle(Color(hex: "CD7F32"))
                    Text("+\(copperAwarded)").font(.caption.bold()).foregroundStyle(Color(hex: "CD7F32"))
                }
                .transition(.scale.combined(with: .opacity))
            }
            if showSilverAnim && silverAwarded > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill").font(.system(size: 10))
                        .foregroundStyle(Color(.systemGray3))
                    Text("+\(silverAwarded)").font(.caption.bold()).foregroundStyle(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
            }
            if showGoldAnim && goldAwarded > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill").font(.system(size: 10))
                        .foregroundStyle(Color(hex: "FFD700"))
                    Text("+\(goldAwarded)").font(.caption.bold()).foregroundStyle(Color(hex: "FFD700"))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
    }

    // ── Flying coin overlay (single burst per type) ─────────────────────

    @State private var flyingCoins: [FlyingCoin] = []

    private var flyingCoinOverlay: some View {
        GeometryReader { geo in
            ForEach(flyingCoins) { coin in
                CoinBurstView(coin: coin, containerSize: geo.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func spawnCoinBurst(type: CoinType, count: Int, delay: Double) {
        let coin = FlyingCoin(type: type, count: count, delay: delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            flyingCoins.append(coin)
            CoinSoundPlayer.playClink()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                CoinSoundPlayer.playLand()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.6) {
            flyingCoins.removeAll { $0.id == coin.id }
        }
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
                flashGuide()
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
                    flashGuide()
                }
            }
        }
    }

    // ── Undo / Redo ────────────────────────────────────────────────────────

    // ── Undo / Retry handlers ────────────────────────────────────────────

    private func handleUndoTap() {
        guard hasUndoableStrokes else { return }
        if isFreeUndo {
            performUndo()
        } else {
            // Paid undo — show confirmation
            if UserSession.shared.silverCoins >= 1 {
                showPaidUndoAlert = true
            } else {
                showPaidUndoAlert = true   // still show — alert text shows coin count
            }
        }
    }

    private func handleRestartTap() {
        // If no strokes drawn yet, restart is free
        if lineScores.isEmpty && redoStack.isEmpty { return }
        if UserSession.shared.goldCoins >= 1 {
            showRetryCostAlert = true
        } else {
            showRetryCostAlert = true   // still show — alert shows coin count
        }
    }

    private func performUndo() {
        guard hasUndoableStrokes else { return }
        let s = finishedStrokes.removeLast(); let sc = lineScores.removeLast()
        redoStack.append(StrokeRecord(stroke: s, score: sc.timeAdjustedScore))
        connectionIndex = max(0, connectionIndex - 1)
        totalUndosUsed += 1; undosThisSegment += 1
        phase = .idle
        resultSaved = false
        showIdeal = false; idealOpacity = 0; flashScore = nil
        flashGuide()
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

    /// Briefly flash the expected path as a solid bright line, then fade out
    /// so only the dashed guide remains.
    private func flashGuide() {
        guideFlashOpacity = 0.9
        withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
            guideFlashOpacity = 0
        }
    }

    private func restartGame() {
        phase = .idle; connectionIndex = 0; activePath = []
        finishedStrokes = []; lineScores = []; flashScore = nil
        resultSaved = false; redoStack = []; totalUndosUsed = 0
        undosThisSegment = 0
        showIdeal = false; idealOpacity = 0; lastScoredConnIndex = nil
        gameStartTime = nil; segmentStartTime = nil; elapsedSeconds = 0
        guideFlashOpacity = 0
        showCopperAnim = false; showSilverAnim = false; showGoldAnim = false
        copperAwarded = 0; silverAwarded = 0; goldAwarded = 0
        flyingCoins = []; showGuestRegisterPrompt = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { flashGuide() }
    }

    private func saveResult() {
        guard !resultSaved else { return }
        let scores = lineScores.map { $0.timeAdjustedScore }
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
                playerID: UserSession.shared.appleUserID,
                displayName: UserSession.shared.displayName,
                level: currentLevel, game: currentGame,
                score: totalScore, totalTime: elapsedSeconds)
        }

        // Award coins with staggered animations
        awardCoinsAnimated(scores: scores)
    }

    private func awardCoinsAnimated(scores: [Int]) {
        let total = scores.reduce(0, +)
        copperAwarded = total / 10
        silverAwarded = scores.filter { $0 >= 90 && $0 <= 95 }.count
        let g96 = scores.filter { $0 >= 96 && $0 <= 99 }.count
        let g100 = scores.filter { $0 == 100 }.count * 5
        goldAwarded = g96 + g100

        var delay: Double = 0.5

        if copperAwarded > 0 {
            let d = delay
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                withAnimation(.spring(response: 0.4)) { showCopperAnim = true }
                UserSession.shared.copperCoins += copperAwarded
            }
            spawnCoinBurst(type: .copper, count: copperAwarded, delay: delay)
            delay += 1.4
        }

        if silverAwarded > 0 {
            let d = delay
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                withAnimation(.spring(response: 0.4)) { showSilverAnim = true }
                UserSession.shared.silverCoins += silverAwarded
            }
            spawnCoinBurst(type: .silver, count: silverAwarded, delay: delay)
            delay += 1.4
        }

        if goldAwarded > 0 {
            let d = delay
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                withAnimation(.spring(response: 0.4)) { showGoldAnim = true }
                let g96only = scores.filter { $0 >= 96 && $0 <= 99 }.count
                let perfect = scores.filter { $0 == 100 }.count * 5
                UserSession.shared.goldCoins += g96only + perfect
            }
            spawnCoinBurst(type: .gold, count: goldAwarded, delay: delay)
            delay += 1.4
        }

        // Clear text animations after all done
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showCopperAnim = false; showSilverAnim = false; showGoldAnim = false
            }
        }

        // Show registration prompt for guests after Level 1 completion
        if UserSession.shared.isGuest || UserSession.shared.appleUserID.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.0) {
                showGuestRegisterPrompt = true
            }
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

// ── Coin animation types ──────────────────────────────────────────────────────

enum CoinType {
    case copper, silver, gold

    var color: Color {
        switch self {
        case .copper: return Color(hex: "CD7F32")
        case .silver: return Color(.systemGray3)
        case .gold:   return Color(hex: "FFD700")
        }
    }

    var highlight: Color {
        switch self {
        case .copper: return Color(hex: "E8A860")
        case .silver: return .white
        case .gold:   return Color(hex: "FFF4B0")
        }
    }
}

struct FlyingCoin: Identifiable {
    let id = UUID()
    let type: CoinType
    let count: Int       // total coins awarded (shown as "+275")
    let delay: Double
}

/// One celebratory burst per coin type: a single large coin appears at
/// screen center, spins, shows "+count", then flies into the chest.
struct CoinBurstView: View {
    let coin: FlyingCoin
    let containerSize: CGSize

    @State private var phase: Int = 0  // 0=hidden, 1=burst at center, 2=fly to chest

    private var centerPos: CGPoint {
        CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
    }
    private var chestPos: CGPoint { CGPoint(x: 30, y: -10) }

    var body: some View {
        ZStack {
            // Glow ring during burst
            if phase == 1 {
                Circle()
                    .fill(coin.type.color.opacity(0.25))
                    .frame(width: 80, height: 80)
                    .blur(radius: 12)
            }

            // Coin disc
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [coin.type.highlight, coin.type.color, coin.type.color.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(coin.type.highlight.opacity(0.6), lineWidth: 2))
                    .shadow(color: coin.type.color.opacity(phase == 1 ? 0.6 : 0.2),
                            radius: phase == 1 ? 12 : 3)

                Circle()
                    .fill(coin.type.highlight.opacity(0.35))
                    .frame(width: 14, height: 14)
            }
            .rotation3DEffect(.degrees(phase >= 1 ? 720 : 0), axis: (x: 0.2, y: 1, z: 0))

            // "+count" label
            if phase == 1 {
                Text("+\(coin.count)")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(coin.type.color)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(y: 38)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(phase == 0 ? 0.1 : phase == 1 ? 1.3 : 0.25)
        .opacity(phase == 0 ? 0 : phase == 1 ? 1.0 : 0.5)
        .position(phase <= 1 ? centerPos : chestPos)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { phase = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeIn(duration: 0.6)) { phase = 2 }
            }
        }
    }
}

// ── Coin sound player ─────────────────────────────────────────────────────────

enum CoinSoundPlayer {
    private static var lastPlayTime: TimeInterval = 0

    /// Short bright "clink" when coin bursts from center.
    static func playClink() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlayTime > 0.08 else { return }
        lastPlayTime = now
        // 1057 = short metallic tink
        AudioServicesPlaySystemSound(1057)
    }

    /// Softer "thud" when coin lands in chest.
    static func playLand() {
        // 1306 = subtle tap (key press)
        AudioServicesPlaySystemSound(1306)
    }
}
