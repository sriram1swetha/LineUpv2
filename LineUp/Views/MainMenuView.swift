import SwiftUI

struct MainMenuView: View {
    @EnvironmentObject var userSession: UserSession

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0f3460"), Color(hex: "16213e"), Color(hex: "533483")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            staticDots

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(.white.opacity(0.08)).frame(width: 110, height: 110)
                        ZStack {
                            Path { p in
                                p.move(to: CGPoint(x: 24, y: 55)); p.addLine(to: CGPoint(x: 86, y: 55))
                            }
                            .stroke(Color(hex: "f5a623").opacity(0.5),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            Path { p in
                                p.move(to: CGPoint(x: 24, y: 55))
                                p.addLine(to: CGPoint(x: 55, y: 28))
                                p.addLine(to: CGPoint(x: 86, y: 55))
                            }
                            .stroke(LinearGradient(colors: [Color(hex: "e94560"), Color(hex: "f5a623")],
                                                   startPoint: .leading, endPoint: .trailing),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            dotAt(CGPoint(x: 24, y: 55), color: Color(hex: "e94560"))
                            dotAt(CGPoint(x: 55, y: 28), color: .white)
                            dotAt(CGPoint(x: 86, y: 55), color: Color(hex: "f5a623"))
                        }
                        .frame(width: 110, height: 110)
                    }

                    Text("LineUp")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(LinearGradient(colors: [Color(hex: "e94560"), Color(hex: "f5a623")],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: 28, height: 2).cornerRadius(1)
                        Text("Draw with precision")
                            .font(.system(size: 15, weight: .semibold, design: .rounded)).tracking(1.4)
                            .foregroundStyle(LinearGradient(colors: [Color(hex: "e94560"), Color(hex: "f5a623")],
                                                            startPoint: .leading, endPoint: .trailing))
                        Rectangle()
                            .fill(LinearGradient(colors: [Color(hex: "f5a623"), Color(hex: "e94560")],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: 28, height: 2).cornerRadius(1)
                    }

                    // Player badge
                    if userSession.isGamer {
                        HStack(spacing: 6) {
                            Image(systemName: userSession.isAdmin ? "shield.fill" : "person.fill")
                                .font(.caption)
                            Text(userSession.displayName)
                                .font(.caption.bold())
                            Text(userSession.isAdmin ? "· Admin" : "· Gamer")
                                .font(.caption).opacity(0.6)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(.white.opacity(0.1)).clipShape(Capsule())
                    }
                }

                Spacer()

                // Buttons
                VStack(spacing: 14) {
                    if userSession.isGamer {
                        NavigationLink(destination: LevelSelectView()) {
                            GlowButton(title: "Play", icon: "play.fill", isPrimary: true)
                        }
                        NavigationLink(destination: LeaderboardView()) {
                            GlowButton(title: "Leaderboard", icon: "trophy.fill", isPrimary: false)
                        }
                        NavigationLink(destination: ScoreboardView()) {
                            GlowButton(title: "My Scores", icon: "list.number", isPrimary: false)
                        }
                        NavigationLink(destination: SettingsView()) {
                            GlowButton(title: "Settings", icon: "gearshape.fill", isPrimary: false)
                        }
                        if userSession.isAdmin {
                            NavigationLink(destination: AdminVisualizerView()) {
                                GlowButton(title: "Dot Visualizer", icon: "eye.circle", isPrimary: false)
                            }
                        }
                        Button {
                            userSession.logout()
                        } label: {
                            GlowButton(title: "Sign Out", icon: "rectangle.portrait.and.arrow.right", isPrimary: false)
                        }
                    } else {
                        // Guest: can play Level 1 as intro
                        NavigationLink(destination: LevelSelectView(guestIntroOnly: true)) {
                            GlowButton(title: "Play Level 1", icon: "play.fill", isPrimary: true)
                        }
                        Button { userSession.hasCompletedIntro = true } label: {
                            GlowButton(title: "Register to Play All Levels", icon: "person.badge.plus", isPrimary: false)
                        }
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                Text("Version 1.0  ·  Sriram S.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.35)).padding(.bottom, 12)
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func dotAt(_ pos: CGPoint, color: Color) -> some View {
        Circle().fill(color).frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5)).position(pos)
    }

    @ViewBuilder
    private var staticDots: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Group {
                Circle().fill(Color(hex: "e94560").opacity(0.14)).frame(width: 60, height: 60).position(x: 0.1*w, y: 0.12*h)
                Circle().fill(Color(hex: "f5a623").opacity(0.10)).frame(width: 40, height: 40).position(x: 0.8*w, y: 0.08*h)
                Circle().fill(Color(hex: "533483").opacity(0.10)).frame(width: 30, height: 30).position(x: 0.05*w, y: 0.55*h)
                Circle().fill(Color(hex: "e94560").opacity(0.12)).frame(width: 50, height: 50).position(x: 0.88*w, y: 0.45*h)
                Circle().fill(Color(hex: "f5a623").opacity(0.10)).frame(width: 35, height: 35).position(x: 0.5*w, y: 0.82*h)
            }
        }.ignoresSafeArea()
    }
}

// ── Shared UI ──────────────────────────────────────────────────────────────────

struct GlowButton: View {
    let title: String; let icon: String; let isPrimary: Bool
    var body: some View {
        HStack {
            Image(systemName: icon).font(.headline)
            Text(title).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).opacity(0.6)
        }
        .padding()
        .background(Group {
            if isPrimary {
                LinearGradient(colors: [Color(hex: "e94560"), Color(hex: "c0392b")],
                               startPoint: .leading, endPoint: .trailing).eraseToAnyView()
            } else { Color.white.opacity(0.10).eraseToAnyView() }
        })
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(isPrimary ? 0 : 0.18), lineWidth: 1))
        .shadow(color: isPrimary ? Color(hex: "e94560").opacity(0.5) : .clear, radius: 12, y: 4)
    }
}

extension Color {
    init(hex: String) {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0; Scanner(string: s).scanHexInt64(&rgb)
        self.init(red: Double((rgb>>16)&0xFF)/255, green: Double((rgb>>8)&0xFF)/255, blue: Double(rgb&0xFF)/255)
    }
}
extension View { func eraseToAnyView() -> AnyView { AnyView(self) } }
