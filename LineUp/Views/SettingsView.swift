import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: GameSettings
    @EnvironmentObject var userSession: UserSession
    @ObservedObject private var audio = AudioManager.shared
    @State private var showResetConfirm = false
    @State private var showLogoutConfirm = false

    var body: some View {
        Form {

            // ── Profile ──────────────────────────────────────────────────
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color(hex: "e94560").opacity(0.15))
                            .frame(width: 48, height: 48)
                        Text(String(userSession.playerName.prefix(1)).uppercased())
                            .font(.title2.bold())
                            .foregroundStyle(Color(hex: "e94560"))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(userSession.displayName).font(.headline)
                        if !userSession.playerEmail.isEmpty {
                            Text(userSession.playerEmail).font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            if !userSession.appleUserID.isEmpty {
                                Label("Apple ID", systemImage: "checkmark.seal.fill")
                                    .font(.caption2).foregroundStyle(.green)
                            }
                            Text(userSession.role == .admin ? "Admin" : "Gamer")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(userSession.isAdmin ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                                .foregroundStyle(userSession.isAdmin ? .orange : .blue)
                                .clipShape(Capsule())
                        }
                    }
                }

                if userSession.profileSyncedToCloud {
                    Label("Synced to iCloud", systemImage: "checkmark.icloud.fill")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Button {
                        userSession.syncProfileToCloud()
                    } label: {
                        Label("Sync to iCloud", systemImage: "arrow.triangle.2.circlepath.icloud")
                            .font(.caption)
                    }
                }

                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .confirmationDialog("Sign out?", isPresented: $showLogoutConfirm) {
                    Button("Sign Out", role: .destructive) { userSession.logout() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("You'll return to the sign-in screen. Your local scores are kept.")
                }
            } header: {
                Label("Profile", systemImage: "person.circle")
            }

            // ── CloudKit Status ───────────────────────────────────────────
            Section {
                HStack {
                    Text("iCloud")
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: CloudKitManager.shared.isAvailable
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(CloudKitManager.shared.isAvailable ? .green : .red)
                        Text(CloudKitManager.shared.statusMessage)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let status = CloudKitManager.shared.lastSubmitStatus {
                    HStack {
                        Text("Last submit")
                        Spacer()
                        Text(status)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let error = CloudKitManager.shared.lastError {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Error", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption2).foregroundStyle(.red)
                    }
                }

                if userSession.isAdmin {
                    Button {
                        CloudKitManager.shared.submitScore(
                            playerID: userSession.appleUserID,
                            displayName: userSession.displayName,
                            level: 1, game: 1, score: 42, totalTime: 5.0)
                    } label: {
                        Label("Test Submit Score", systemImage: "arrow.up.circle")
                    }

                    Button {
                        CloudKitManager.shared.retryConnection()
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                }
            } header: {
                Label("CloudKit", systemImage: "icloud")
            } footer: {
                Text("Scores are submitted to CloudKit when you complete a game. Check icloud.developer.apple.com → your container → Records to verify.")
            }

            // ── Games per level (admin-only editable) ──────────────────────
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
                        in: (settings.minGamesPerLevel + 1)...12) {
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
            .disabled(!userSession.isAdmin)
            .opacity(userSession.isAdmin ? 1.0 : 0.45)

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
            .disabled(!userSession.isAdmin)
            .opacity(userSession.isAdmin ? 1.0 : 0.45)

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
            .disabled(!userSession.isAdmin)
            .opacity(userSession.isAdmin ? 1.0 : 0.45)

            // ── Drawing mode ────────────────────────────────────────────
            Section {
                Toggle(isOn: $settings.continuousDrawing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continuous Drawing")
                        Text(settings.continuousDrawing
                             ? "Draw through dots without lifting your finger"
                             : "Lift and re-tap for each connection")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Drawing Mode", systemImage: "hand.draw")
            } footer: {
                Text(settings.continuousDrawing
                     ? "Scores update instantly as you pass through each dot. Lifting before reaching the next dot discards that stroke."
                     : "Each connection is scored when you lift your finger. You see the ideal path overlay between strokes.")
            }

            // ── Undo & Timing ──────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max undos per segment")
                        Spacer()
                        Text(settings.maxUndosPerSegment == 0 ? "∞" : "\(settings.maxUndosPerSegment)")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(settings.maxUndosPerSegment) },
                        set: { settings.maxUndosPerSegment = Int($0) }
                    ), in: 0...5, step: 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Par seconds per segment")
                        Spacer()
                        Text("\(Int(settings.parSecondsPerConnection))s")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.parSecondsPerConnection, in: 3...15, step: 1)
                }
            } header: {
                Label("Undo & Timing", systemImage: "clock.arrow.circlepath")
            } footer: {
                Text("0 undos = unlimited. Scores are penalized when total time exceeds par (connections × par seconds).")
            }
            .disabled(!userSession.isAdmin)
            .opacity(userSession.isAdmin ? 1.0 : 0.45)

            // ── Music ─────────────────────────────────────────────────────
            Section {
                Toggle(isOn: $audio.musicEnabled) {
                    Text("Background Music")
                }

                if audio.musicEnabled {
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
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)

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
                } // end if musicEnabled
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
                .disabled(!userSession.isAdmin)
            } header: {
                Label("Data", systemImage: "externaldrive")
            }
            .disabled(!userSession.isAdmin)
            .opacity(userSession.isAdmin ? 1.0 : 0.45)

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
