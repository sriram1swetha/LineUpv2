import SwiftUI
import AudioToolbox

private enum DrawPhase { case idle, drawing, reviewing, complete }
private struct StrokeRecord { let stroke: FinishedStroke; let score: Int }
// Buttons are now in their own navStrip, not overlaid on the canvas.
private let topArrowReserved: CGFloat = 0

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
    @State private var undosThisSegment = 0
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

    // Guide flash — briefly highlights the expected path before fading to dashed guide
    @State private var guideFlashOpacity: Double = 0

    // Coin animations
    @State private var showCopperAnim = false
    @State private var showSilverAnim = false
    @State private var showGoldAnim   = false
    @State private var copperAwarded  = 0
    @State private var silverAwarded  = 0
    @State private var goldAwarded    = 0
    @State private var showPaidUndoAlert = false
    @State private var showRetryCostAlert = false

    // Per-game coins cache — persists when navigating away and back to the same game
    @State private var gameCoinsCache: [String: (copper: Int, silver: Int, gold: Int)] = [:]
    // Tracks coins already granted this play-through to award only the improvement delta
    @State private var coinsGranted: (copper: Int, silver: Int, gold: Int) = (0, 0, 0)

    // Game objective overlay — shown briefly when a new game loads
    @State private var showGameObjective = true
    @State private var objectiveOpacity: Double = 1.0

    // Zoom / pan
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var panDragStart: CGPoint? = nil
    @State private var isPanDrag = false

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

    // ── Body ───────────────────────────────────────────────────────────────
    // Region layout (top → bottom):
    //   1. Navigation bar  — back arrow, Lv N · Name, Restart, Home   (system toolbar)
    //   2. topStrip        — Chest / coin totals,  connection hint,  segment pips
    //   3. navStrip        — Prev Game,  Undo,  Redo,  Next Game
    //   4. canvas          — main drawing area (zoom + pan supported)
    //   5. footerBar       — Score · Accuracy · Time · Coins Earned   (fixed height)

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            navStrip
            ZStack {
                canvasLayer
                gameObjectiveOverlay
                flyingCoinOverlay
            }
            // Coin award banner floats above the footer without shifting it
            .overlay(alignment: .bottom) {
                if showCopperAnim || showSilverAnim || showGoldAnim {
                    coinAnimationBanner
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
            }
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
                    // Clear this game's cached coins so the footer resets on retry
                    gameCoinsCache.removeValue(forKey: "\(currentLevel)-\(currentGame)")
                    restartGame()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Full retry costs 1 Gold coin.\n\nYou have \(UserSession.shared.goldCoins) Gold coins.")
        }
    }

    // ── Region 2 — Chest + connection hint + segment pips ─────────────────

    private var topStrip: some View {
        HStack(spacing: 10) {
            // Chest icon with running coin totals
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

            // Segment score pips
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

    // ── Region 3 — Prev Game · Undo · Redo · Next Game ────────────────────

    private var navStrip: some View {
        HStack(spacing: 0) {
            navButton(icon: "chevron.left.circle.fill",
                      label: "Prev",
                      enabled: hasPrev && phase != .drawing && phase != .reviewing,
                      action: { navigatePrev() })

            Spacer()

            navButton(icon: "arrow.uturn.backward.circle.fill",
                      label: isFreeUndo ? "Undo" : "Undo 🪙",
                      enabled: hasUndoableStrokes,
                      action: { handleUndoTap() })

            Spacer().frame(width: 14)

            navButton(icon: "arrow.uturn.forward.circle.fill",
                      label: "Redo",
                      enabled: canRedo,
                      action: { performRedo() })

            Spacer()

            navButton(icon: "chevron.right.circle.fill",
                      label: currentGameHasHistory ? "Next" : "Play first",
                      enabled: hasNext && phase != .drawing && phase != .reviewing,
                      action: { navigateNext() })
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
    }

    @ViewBuilder
    private func navButton(icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(enabled ? Color.blue.opacity(0.85) : Color(.systemFill))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(enabled ? Color.blue.opacity(0.75) : Color(.tertiaryLabel))
            }
        }
        .disabled(!enabled)
    }

    // ── Region 4 — Canvas ──────────────────────────────────────────────────

    @ViewBuilder
    private var canvasLayer: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(.systemBackground)

                // Emoji background — faint guide showing what shape to draw
                if let emoji = config.shapeEmoji {
                    Text(emoji)
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.52))
                        .opacity(0.22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }

                // Dashed guide (current connection)
                if let conn = currentConn, phase != .complete {
                    idealHighlight(connectionIndex: connectionIndex)
                        .opacity(guideFlashOpacity)
                    guideShape(conn: conn)
                }

                // Faint circle outline hint for classic full-circle curve games
                if currentLevelType.isCurve,
                   config.perConnectionArcs == nil,
                   let center = config.circleCenter,
                   let radius = config.circleRadius {
                    Circle()
                        .stroke(Color.blue.opacity(0.06), lineWidth: 1)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                }

                // Maze walls
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

                // Ideal highlight (appears briefly after each scored stroke)
                if showIdeal, let idx = lastScoredConnIndex,
                   idx < config.connections.count {
                    idealHighlight(connectionIndex: idx).opacity(idealOpacity)
                }

                // On completion: show all ideal paths for comparison
                if phase == .complete {
                    ForEach(0..<config.connections.count, id: \.self) { idx in
                        idealHighlight(connectionIndex: idx).opacity(0.4)
                    }
                }

                ForEach(finishedStrokes) { stroke in
                    StrokePath(points: stroke.path)
                        .stroke(scoreColor(stroke.score).opacity(0.75), lineWidth: lineW)
                }

                if !activePath.isEmpty {
                    StrokePath(points: activePath).stroke(Color.blue, lineWidth: lineW)
                }

                ForEach(0..<config.dots.count, id: \.self) { i in dotView(index: i) }

                if let s = flashScore {
                    scoreFlashView(score: s)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Zoom indicator (shown when zoomed in)
                if zoomScale > 1.05 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.35)) {
                                    zoomScale = 1.0; panOffset = .zero
                                }
                            } label: {
                                Label(String(format: "%.1f×", zoomScale), systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.regularMaterial, in: Capsule())
                            }
                            .padding(10)
                        }
                    }
                }
            }
            .scaleEffect(zoomScale, anchor: .center)
            .offset(panOffset)
            .contentShape(Rectangle())
            .gesture(drawGesture)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoomScale = max(1.0, min(4.0, value))
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3)) {
                            zoomScale = max(1.0, min(4.0, value))
                            if zoomScale < 1.05 { zoomScale = 1.0; panOffset = .zero }
                        }
                    }
            )
            .onAppear {
                canvasSize = geo.size
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { flashGuide() }
            }
            .onChange(of: geo.size) { canvasSize = $0 }
        }
    }

    // ── Game objective overlay — shown at the start of each new game ───────

    @ViewBuilder
    private var gameObjectiveOverlay: some View {
        if showGameObjective {
            ZStack {
                Color.black.opacity(0.55)
                VStack(spacing: 14) {
                    Text(config.shapeName)
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    Text(gameObjectiveText)
                        .font(.title3.bold())
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Text("Tap to start")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 2)
                }
            }
            .opacity(objectiveOpacity)
            .onTapGesture { dismissObjective() }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    dismissObjective()
                }
            }
        }
    }

    private var gameObjectiveText: String {
        if currentLevelType.isMaze {
            return "Navigate from dot to dot\nwithout crossing the walls"
        } else if currentLevelType.isCurve {
            return "Trace the curved arc\nbetween each dot"
        } else {
            return "Draw straight lines\nbetween each dot"
        }
    }

    private func dismissObjective() {
        guard showGameObjective else { return }
        withAnimation(.easeOut(duration: 0.35)) { objectiveOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showGameObjective = false
            objectiveOpacity = 1.0
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

    // ── Region 5 — Footer: Score · Accuracy · Time · Coins Earned ─────────
    // Fixed height. Coin animation banner floats ABOVE this strip as an overlay.

    private var footerBar: some View {
        let prev = lineScores.isEmpty ? scoreStore.bestResult(level: currentLevel, game: currentGame) : nil
        let showingPrev = prev != nil

        return HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(showingPrev ? "Best" : "Score").font(.system(size: 9)).foregroundStyle(showingPrev ? Color.blue.opacity(0.7) : .secondary)
                Text(showingPrev ? "\(prev!.totalScore)/\(prev!.maxPossibleScore)" : "\(totalScore)/\(maxScore)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(showingPrev ? Color.blue.opacity(0.8) : .primary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack(spacing: 2) {
                Text("Accuracy").font(.system(size: 9)).foregroundStyle(.secondary)
                let pct: Int = {
                    if showingPrev {
                        let p = prev!; return p.maxPossibleScore > 0 ? p.totalScore * 100 / p.maxPossibleScore : 0
                    }
                    return maxScore > 0 ? totalScore * 100 / maxScore : 0
                }()
                Text(showingPrev || maxScore > 0 ? "\(pct)%" : "—")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(showingPrev ? Color.blue.opacity(0.8) : scoreColor(pct))
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack(spacing: 2) {
                Text("Time").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(showingPrev ? prev!.timeLabel : (elapsedSeconds > 0 ? String(format: "%.1fs", elapsedSeconds) : "—"))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(showingPrev ? Color.blue.opacity(0.8) : .primary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack(spacing: 2) {
                Text("Earned").font(.system(size: 9)).foregroundStyle(.secondary)
                coinsEarnedRow
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func footerCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var coinsEarnedRow: some View {
        let earned = gameCoinsCache["\(currentLevel)-\(currentGame)"]
        if let e = earned, e.copper > 0 || e.silver > 0 || e.gold > 0 {
            HStack(spacing: 4) {
                if e.copper > 0 { coinBadge(count: e.copper, color: Color(hex: "CD7F32")) }
                if e.silver > 0 { coinBadge(count: e.silver, color: Color(.systemGray3)) }
                if e.gold   > 0 { coinBadge(count: e.gold,   color: Color(hex: "FFD700")) }
            }
        } else {
            Text("—").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func coinBadge(count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count)").font(.system(size: 10, weight: .bold)).foregroundStyle(color)
        }
    }

    // ── Coin animation banner — floats above footer, doesn't shift layout ──

    private var coinAnimationBanner: some View {
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
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    // ── Flying coin overlay (burst animation) ──────────────────────────────

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

    // ── Drag gesture (draw + pan when zoomed) ─────────────────────────────

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                switch phase {
                case .idle:
                    guard let conn = currentConn else {
                        if zoomScale > 1.05 { handlePanDrag(value) }
                        return
                    }
                    let loc = transformToCanvas(value.location)
                    if ScoringEngine.distance(loc, config.dots[conn.0]) < dotR * 5 {
                        isPanDrag = false
                        phase = .drawing; activePath = [loc]; redoStack = []
                        if gameStartTime == nil { gameStartTime = Date() }
                        if segmentStartTime == nil { segmentStartTime = Date() }
                    } else if zoomScale > 1.05 {
                        isPanDrag = true
                        handlePanDrag(value)
                    }

                case .drawing:
                    if isPanDrag { return }
                    let loc = transformToCanvas(value.location)
                    activePath.append(loc)

                    if settings.continuousDrawing, let conn = currentConn {
                        let endDot   = config.dots[conn.1]
                        let startDot = config.dots[conn.0]
                        let distEnd   = ScoringEngine.distance(loc, endDot)
                        let distStart = ScoringEngine.distance(loc, startDot)
                        if distEnd < dotR * 1.5 && distStart > dotR * 2.5 {
                            completeCurrentStroke(continuous: true, fingerLocation: loc)
                        }
                    }

                default: break
                }
            }
            .onEnded { value in
                if isPanDrag {
                    isPanDrag = false
                    panDragStart = nil
                    return
                }
                guard phase == .drawing else { return }

                if settings.continuousDrawing {
                    activePath = []; phase = .idle
                    return
                }

                let loc = transformToCanvas(value.location)
                activePath.append(loc)
                completeCurrentStroke(continuous: false, fingerLocation: loc)
            }
    }

    // Inverse of scaleEffect(zoomScale, anchor: .center) + offset(panOffset)
    private func transformToCanvas(_ point: CGPoint) -> CGPoint {
        guard zoomScale > 1.001 || panOffset.width != 0 || panOffset.height != 0 else { return point }
        let cx = canvasSize.width / 2
        let cy = canvasSize.height / 2
        return CGPoint(
            x: (point.x - panOffset.width - cx) / zoomScale + cx,
            y: (point.y - panOffset.height - cy) / zoomScale + cy
        )
    }

    private func handlePanDrag(_ value: DragGesture.Value) {
        if panDragStart == nil {
            panDragStart = CGPoint(x: panOffset.width, y: panOffset.height)
        }
        let newX = (panDragStart?.x ?? 0) + value.translation.width
        let newY = (panDragStart?.y ?? 0) + value.translation.height
        let maxPan = (zoomScale - 1.0) * min(canvasSize.width, canvasSize.height) / 2
        panOffset = CGSize(
            width:  max(-maxPan, min(maxPan, newX)),
            height: max(-maxPan, min(maxPan, newY))
        )
    }

    /// Score the current stroke, record it, advance to the next connection.
    private func completeCurrentStroke(continuous: Bool, fingerLocation: CGPoint) {
        guard let conn = currentConn else { return }
        let startDot = config.dots[conn.0], endDot = config.dots[conn.1]

        if !activePath.isEmpty {
            activePath[0] = startDot
            activePath.append(endDot)
        }

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

        elapsedSeconds = gameStartTime.map { Date().timeIntervalSince($0) } ?? 0

        let adjusted = ScoringEngine.applyTimePenalty(
            accuracyScore: accuracy, elapsed: elapsedSeconds, par: parTime)

        lineScores.append(LineScore(connectionIndex: connectionIndex,
                                     rawAccuracyScore: accuracy,
                                     timeAdjustedScore: adjusted))
        finishedStrokes.append(FinishedStroke(path: activePath, score: adjusted))
        lastScoredConnIndex = connectionIndex

        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { flashScore = adjusted }

        let nextIdx = connectionIndex + 1

        if continuous {
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
                    activePath = [fingerLocation]
                } else {
                    activePath = []; phase = .idle
                }
            }
        } else {
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

    private func handleUndoTap() {
        guard hasUndoableStrokes else { return }
        if isFreeUndo {
            performUndo()
        } else {
            showPaidUndoAlert = true
        }
    }

    private func handleRestartTap() {
        if lineScores.isEmpty && redoStack.isEmpty { return }
        showRetryCostAlert = true
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
        coinsGranted = (0, 0, 0)
        flyingCoins = []
        // Reset zoom & pan for the new game
        zoomScale = 1.0; panOffset = .zero; panDragStart = nil; isPanDrag = false
        // Show objective overlay for the incoming game
        showGameObjective = true; objectiveOpacity = 1.0
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

        CloudKitManager.shared.submitScore(
            playerID: UserSession.shared.playerID,
            displayName: UserSession.shared.displayName,
            level: currentLevel, game: currentGame,
            score: totalScore, totalTime: elapsedSeconds)

        awardCoinsAnimated(scores: scores)
    }

    private func awardCoinsAnimated(scores: [Int]) {
        let total = scores.reduce(0, +)
        let newCopper = total / 10
        let newSilver = scores.filter { $0 >= 90 && $0 <= 95 }.count
        let g96 = scores.filter { $0 >= 96 && $0 <= 99 }.count
        let g100 = scores.filter { $0 == 100 }.count * 5
        let newGold = g96 + g100

        // Only award the improvement over what's already been granted this playthrough
        let deltaCopper = max(0, newCopper - coinsGranted.copper)
        let deltaSilver = max(0, newSilver - coinsGranted.silver)
        let deltaGold   = max(0, newGold   - coinsGranted.gold)

        coinsGranted = (copper: newCopper, silver: newSilver, gold: newGold)

        copperAwarded = deltaCopper
        silverAwarded = deltaSilver
        goldAwarded   = deltaGold

        // Update footer cache to the full totals for this game
        gameCoinsCache["\(currentLevel)-\(currentGame)"] = (copper: newCopper, silver: newSilver, gold: newGold)

        var delay: Double = 0.5

        if deltaCopper > 0 {
            let d = delay
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                withAnimation(.spring(response: 0.4)) { showCopperAnim = true }
                UserSession.shared.copperCoins += deltaCopper
            }
            spawnCoinBurst(type: .copper, count: deltaCopper, delay: delay)
            delay += 1.4
        }

        if deltaSilver > 0 {
            let d = delay
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                withAnimation(.spring(response: 0.4)) { showSilverAnim = true }
                UserSession.shared.silverCoins += deltaSilver
            }
            spawnCoinBurst(type: .silver, count: deltaSilver, delay: delay)
            delay += 1.4
        }

        if deltaGold > 0 {
            let d = delay
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                withAnimation(.spring(response: 0.4)) { showGoldAnim = true }
                UserSession.shared.goldCoins += deltaGold
            }
            spawnCoinBurst(type: .gold, count: deltaGold, delay: delay)
            delay += 1.4
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showCopperAnim = false; showSilverAnim = false; showGoldAnim = false
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
    let count: Int
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
            if phase == 1 {
                Circle()
                    .fill(coin.type.color.opacity(0.25))
                    .frame(width: 80, height: 80)
                    .blur(radius: 12)
            }

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

    static func playClink() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlayTime > 0.08 else { return }
        lastPlayTime = now
        AudioServicesPlaySystemSound(1057)
    }

    static func playLand() {
        AudioServicesPlaySystemSound(1306)
    }
}
