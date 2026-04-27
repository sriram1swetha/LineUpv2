import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var userSession: UserSession
    @EnvironmentObject var scoreStore: ScoreStore
    @State private var showResetConfirm = false
    @State private var adminPasscode = ""
    @State private var adminError = false
    @State private var showAdminLogin = false

    var body: some View {
        Form {
            if userSession.isAdmin {
                adminSections
            } else {
                gamerSections
            }
            feedbackSection
        }
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Reset all scores?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { scoreStore.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This resets all scores and progress. Cannot be undone.") }
    }

    // ── Admin sections (full access) ───────────────────────────────────────

    @ViewBuilder private var adminSections: some View {
        // Level structure (read-only info)
        Section {
            ForEach(LevelType.allCases, id: \.rawValue) { lt in
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(hex: lt.badgeColor).opacity(0.15)).frame(width: 34, height: 34)
                        Text("\(lt.rawValue)").font(.system(size: 15, weight: .black, design: .rounded)).foregroundStyle(Color(hex: lt.badgeColor))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lt.title).font(.subheadline.bold())
                        Text(lt.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: { Label("Level Structure", systemImage: "lock.shield") }
        footer: { Text("6 fixed levels — lines to curves, guided to freehand.") }

        // Games per level
        Section {
            stepper("Games per Level", value: $settings.gamesPerLevel,
                    range: settings.minGamesPerLevel...settings.maxGamesPerLevel)
            stepper("Min games (bound)", value: $settings.minGamesPerLevel, range: 1...max(1, settings.maxGamesPerLevel-1))
            stepper("Max games (bound)", value: $settings.maxGamesPerLevel, range: (settings.minGamesPerLevel+1)...8)
        } header: { Label("Games per Level", systemImage: "square.grid.2x2") }

        // Undo
        Section {
            stepper("Max Undos per Segment", value: $settings.maxUndosPerSegment, range: 0...5)
        } header: { Label("Undo Rules", systemImage: "arrow.uturn.backward") }
        footer: { Text("0 = unlimited. Each segment (A→B connection) has its own undo counter.") }

        // Dot & stroke
        Section {
            slider("Dot diameter", value: $settings.dotDiameter, in: 12...56, unit: "pt", step: 2)
            slider("Thick stroke (Levels 1,3,5)", value: $settings.thickStroke,
                   in: max(settings.thinStroke+1, 2)...settings.dotDiameter, unit: "pt", step: 1)
            slider("Thin stroke (Levels 2,4,6)", value: $settings.thinStroke,
                   in: 1...max(1, settings.thickStroke-1), unit: "pt", step: 1)
        } header: { Label("Dot & Stroke Size", systemImage: "circle") }

        // Time scoring
        Section {
            slider("Par seconds per segment", value: $settings.parSecondsPerConnection, in: 3...15, unit: "s", step: 1)
        } header: { Label("Time Scoring", systemImage: "timer") }
        footer: { Text("Par × connections = expected game time. Going over par reduces score.") }

        // Admin visualizer
        Section {
            NavigationLink(destination: AdminVisualizerView()) {
                Label("Dot Layout Visualizer", systemImage: "dot.scope")
            }
        } header: { Label("Admin Tools", systemImage: "wrench.and.screwdriver") }

        // Data
        Section {
            Button(role: .destructive) { showResetConfirm = true } label: {
                Label("Reset All Scores & Progress", systemImage: "trash")
            }
        } header: { Label("Data", systemImage: "externaldrive") }
    }

    // ── Gamer sections (minimal) ───────────────────────────────────────────

    @ViewBuilder private var gamerSections: some View {
        Section {
            HStack {
                Label("Name", systemImage: "person")
                Spacer()
                Text(userSession.displayName).foregroundStyle(.secondary)
            }
            HStack {
                Label("Email", systemImage: "envelope")
                Spacer()
                Text(userSession.playerEmail).foregroundStyle(.secondary).font(.caption)
            }
        } header: { Label("Your Profile", systemImage: "person.circle") }

        Section {
            Button(role: .destructive) { showResetConfirm = true } label: {
                Label("Reset My Scores", systemImage: "trash")
            }
        } header: { Label("Data", systemImage: "externaldrive") }

        // Admin upgrade
        Section {
            if !showAdminLogin {
                Button { showAdminLogin = true } label: {
                    Label("Admin Login", systemImage: "shield.lefthalf.filled")
                }
            } else {
                SecureField("Admin passcode", text: $adminPasscode)
                if adminError { Text("Incorrect passcode").font(.caption).foregroundStyle(.red) }
                Button("Confirm") {
                    adminError = !userSession.tryAdminLogin(passcode: adminPasscode)
                    if !adminError { showAdminLogin = false }
                }
            }
        } header: { Label("Developer Access", systemImage: "lock") }
    }

    // ── App Feedback ───────────────────────────────────────────────────────

    @ViewBuilder private var feedbackSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Color(hex: "e94560"), Color(hex: "533483")],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        Text("S").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sriram S.").font(.headline)
                        Text("Developer & Designer").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Button {
                    if let url = URL(string: "mailto:photerrificshots@gmail.com") { UIApplication.shared.open(url) }
                } label: {
                    HStack {
                        Image(systemName: "envelope.fill").foregroundStyle(Color(hex: "e94560"))
                        Text("photerrificshots@gmail.com").font(.subheadline).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(.vertical, 4)
        } header: { Label("App Feedback", systemImage: "bubble.left.and.bubble.right") }
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    @ViewBuilder private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack { Text(title); Spacer(); Text("\(value.wrappedValue)").monospacedDigit().foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, unit: String, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
