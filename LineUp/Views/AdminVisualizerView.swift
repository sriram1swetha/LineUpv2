import SwiftUI

/// Admin-only tool that renders the dot layout for any level/game combination.
/// Shows dots, connection lines, and coordinates — helps spot layout issues.
struct AdminVisualizerView: View {
    @EnvironmentObject var settings: GameSettings

    @State private var selectedLevel = 1
    @State private var selectedGame  = 1
    @State private var canvasSize: CGSize = CGSize(width: 320, height: 420)

    private var levelType: LevelType { LevelType(rawValue: selectedLevel) ?? .linesWithGuide }
    private var dotCount: Int { settings.dotCount(forGame: selectedGame, levelType: levelType) }

    private var config: DotConfiguration {
        LevelGenerator.configuration(
            levelType: levelType, dotCount: dotCount,
            in: canvasSize, dotRadius: settings.dotRadius, topReserved: 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            Form {
                Section("Level & Game") {
                    Picker("Level", selection: $selectedLevel) {
                        ForEach(1...LevelType.totalLevels, id: \.self) { Text("Level \($0)").tag($0) }
                    }
                    Picker("Game", selection: $selectedGame) {
                        ForEach(1...settings.gamesPerLevel, id: \.self) {
                            let dc = settings.dotCount(forGame: $0, levelType: levelType)
                            Text(LevelGenerator.shapeName(dotCount: dc, isCurve: levelType.isCurve)).tag($0)
                        }
                    }
                }
                Section("Info") {
                    LabeledContent("Shape", value: config.shapeName)
                    LabeledContent("Dots", value: "\(dotCount)")
                    LabeledContent("Connections", value: "\(config.connections.count)")
                    LabeledContent("Mode", value: levelType.isCurve ? "Curves" : "Lines")
                    LabeledContent("Guide", value: levelType.hasGuide ? "Yes" : "No")
                    if let c = config.circleCenter, let r = config.circleRadius {
                        LabeledContent("Circle center", value: "(\(Int(c.x)), \(Int(c.y)))")
                        LabeledContent("Circle radius", value: "\(Int(r)) pt")
                    }
                }
            }
            .frame(maxHeight: 320)

            Divider()

            // Canvas preview
            Text("Layout Preview").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 8)
            GeometryReader { geo in
                ZStack {
                    Color(.systemBackground)
                    visualizerCanvas
                }
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { canvasSize = $0 }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12)).padding()

            // Dot coordinates list
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(config.dots.enumerated()), id: \.offset) { i, dot in
                        VStack(spacing: 2) {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("D\(i+1)").font(.system(size: 10, weight: .bold))
                            Text("(\(Int(dot.x)),\(Int(dot.y)))").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 16)
        }
        .navigationTitle("Dot Visualizer").navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var visualizerCanvas: some View {
        // Connection lines / arcs
        ForEach(0..<config.connections.count, id: \.self) { i in
            let conn = config.connections[i]
            let a = config.dots[conn.0], b = config.dots[conn.1]
            if let c = config.circleCenter, let r = config.circleRadius, config.isCurveMode {
                ArcPath(center: c, radius: r, from: a, to: b)
                    .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            } else {
                Path { p in p.move(to: a); p.addLine(to: b) }
                    .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }

        // Circle outline for curve mode
        if let c = config.circleCenter, let r = config.circleRadius {
            Circle().stroke(Color.orange.opacity(0.2), lineWidth: 1)
                .frame(width: r*2, height: r*2).position(c)
        }

        // Dots with numbers and coordinates
        ForEach(Array(config.dots.enumerated()), id: \.offset) { i, pos in
            ZStack {
                Circle().fill(Color.blue).frame(width: settings.dotRadius*2, height: settings.dotRadius*2)
                Text("\(i+1)").font(.system(size: max(settings.dotRadius*0.9, 7), weight: .bold)).foregroundStyle(.white)
            }
            .position(pos)

            Text("(\(Int(pos.x)),\(Int(pos.y)))")
                .font(.system(size: 8)).foregroundStyle(Color(.tertiaryLabel))
                .position(x: pos.x, y: pos.y + settings.dotRadius + 10)
        }
    }
}
