import SwiftUI

struct ContentView: View {
    @EnvironmentObject var userSession: UserSession
    @StateObject private var navigator = Navigator()

    var body: some View {
        switch userSession.appState {
        case .needsWelcome:
            WelcomeView()
                .environmentObject(userSession)

        case .deactivated:
            DeactivatedView()
                .environmentObject(userSession)

        case .playing:
            NavigationStack { MainMenuView() }
                .id(navigator.resetCount)
                .environmentObject(navigator)
        }
    }
}

// ── Deactivated account screen ────────────────────────────────────────────────

struct DeactivatedView: View {
    @EnvironmentObject var userSession: UserSession
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0f3460"), Color(hex: "16213e")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 60)).foregroundStyle(.orange)

                Text("Account Deactivated")
                    .font(.title2.bold()).foregroundStyle(.white)

                if let date = userSession.deactivationDate {
                    let daysLeft = max(0, 90 - (Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0))
                    Text("Your account will be permanently deleted in \(daysLeft) days.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                Button {
                    userSession.reactivateAccount()
                } label: {
                    Text("Reactivate Account")
                        .font(.headline)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete Account Now")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                .confirmationDialog("Delete account permanently?", isPresented: $showDeleteConfirm) {
                    Button("Delete Everything", role: .destructive) {
                        userSession.deleteAccount()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will permanently delete your profile, all scores, leaderboard positions, and coins. This cannot be undone.")
                }
            }
            .padding(40)
        }
    }
}
