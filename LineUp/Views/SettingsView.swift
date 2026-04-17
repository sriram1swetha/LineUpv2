import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: GameSettings
    @ObservedObject private var audio = AudioManager.shared
    @State private var showResetConfirm = false

    var body: some View {
        Form {

            // ── Level Structure info ───────────────────────────────────────
            Section {
                ForEach(LevelType.allCases, id: \.rawValue) { lt in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: lt.badgeColor).opacity(0.15))
                                .frame(width: 36, height: 36)
                            Text("\(lt.rawValue)")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(Color(hex: lt.badgeColor))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lt.title).font(.subheadline.bold())
                            Text(lt.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Label("Level Structure (Fixed)", systemImage: "lock.shield")
            } footer: {
                Text("LineUp has 6 fixed level types progressing from guided lines to freehand curves. Complete each level to unlock the next.")
            }

            // ── Games per level ───────────────────────────────────────────
            Section {
                Stepper(value: $settings.gamesPerLevel,
                        in: settings.minGamesPerLevel...settings.maxGamesPerLevel) {
                    HStack {
                        Text("Games per Level")
                        Spacer()
                        Text("\(settings.gamesPerLevel)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $settings.minGamesPerLevel,
                        in: 1...max(1, settings.maxGamesPerLevel - 1)) {
                    HStack {
                        Text("Min games (admin)")
                        Spacer()
                        Text("\(settings.minGamesPerLevel)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $settings.maxGamesPerLevel,
                        in: (settings.minGamesPerLevel + 1)...10) {
                    HStack {
                        Text("Max games (admin)")
                        Spacer()
                        Text("\(settings.maxGamesPerLevel)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Games per Level", systemImage: "square.grid.2x2")
            } footer: {
                Text("Game 1 = 2 dots, Game 2 = 3 dots, … Game \(settings.gamesPerLevel) = \(settings.gamesPerLevel + 1) dots.")
            }

            // ── Dot size ──────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Dot diameter")
                        Spacer()
                        Text("Ø \(Int(settings.dotDiameter)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.dotDiameter, in: 12...56, step: 2)
                }

                // Preview
                HStack(spacing: 16) {
                    Spacer()
                    Circle().fill(Color.blue).frame(width: settings.dotRadius * 2, height: settings.dotRadius * 2)
                    Spacer()
                }
                .frame(height: CGFloat(settings.dotDiameter) + 16)
            } header: {
                Label("Dot Size", systemImage: "circle")
            } footer: {
                Text("All levels share the same dot size.")
            }

            // ── Stroke thicknesses ────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Thick stroke (Levels 1, 3, 5)")
                        Spacer()
                        Text("\(Int(settings.thickStroke)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.thickStroke,
                           in: max(settings.thinStroke + 1, 2)...settings.dotDiameter, step: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Thin stroke (Levels 2, 4, 6)")
                        Spacer()
                        Text("\(Int(settings.thinStroke)) pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.thinStroke,
                           in: 1...max(1, settings.thickStroke - 1), step: 1)
                }

                // Preview
                VStack(spacing: 8) {
                    HStack {
                        Text("Thick").font(.caption).foregroundStyle(.secondary).frame(width: 40)
                        Capsule().fill(Color.blue)
                            .frame(width: 120, height: CGFloat(settings.thickStroke))
                    }
                    HStack {
                        Text("Thin").font(.caption).foregroundStyle(.secondary).frame(width: 40)
                        Capsule().fill(Color.blue)
                            .frame(width: 120, height: CGFloat(settings.thinStroke))
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("Stroke Thickness", systemImage: "scribble")
            } footer: {
                Text("Thin stroke never exceeds dot diameter.")
            }

            // ── Music ─────────────────────────────────────────────────────
            Section {
                HStack(spacing: 12) {
                    Image(systemName: audio.isPlaying ? "music.note" : "music.note.list")
                        .foregroundStyle(Color(hex: "e94560"))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now Playing").font(.caption).foregroundStyle(.secondary)
                        Text(audio.currentTrackName.isEmpty ? "—" : audio.currentTrackName)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(audio.isPlaying ? "Playing" : "Paused")
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            (audio.isPlaying ? Color.green : Color.gray).opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(audio.isPlaying ? .green : .secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        audio.previous()
                    } label: {
                        Label("Previous", systemImage: "backward.fill")
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if audio.isPlaying { audio.pause() } else { audio.play() }
                    } label: {
                        Label(audio.isPlaying ? "Pause" : "Play",
                              systemImage: audio.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "e94560"))

                    Button {
                        audio.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        audio.next()
                    } label: {
                        Label("Next", systemImage: "forward.fill")
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Label("Music", systemImage: "speaker.wave.2.fill")
            } footer: {
                Text("Background tracks loop one after the other. Use ◀︎ ▶︎ to skip between tracks.")
            }

            // ── Data ──────────────────────────────────────────────────────
            Section {
                Button(role: .destructive) { showResetConfirm = true } label: {
                    Label("Reset All Scores & Unlock Progress", systemImage: "trash")
                }
            } header: {
                Label("Data", systemImage: "externaldrive")
            }

            // ── App Feedback ──────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(hex: "e94560"), Color(hex: "533483")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 44, height: 44)
                            Text("S")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sriram S.").font(.headline)
                            Text("Developer & Designer").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    Button {
                        if let url = URL(string: "mailto:photerrificshots@gmail.com") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "envelope.fill").foregroundStyle(Color(hex: "e94560"))
                            Text("photerrificshots@gmail.com").font(.subheadline).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("App Feedback", systemImage: "bubble.left.and.bubble.right")
            } footer: {
                Text("Tap the email to send feedback directly.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Clear all scores?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) { ScoreStore.shared.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This resets all scores and locks all levels. Cannot be undone.") }
    }
}
