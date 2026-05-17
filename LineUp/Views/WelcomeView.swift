import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @EnvironmentObject var userSession: UserSession
    @Environment(\.colorScheme) var colorScheme

    @State private var displayName = ""
    @State private var nameError   = false

    // Admin
    @State private var showAdminLogin = false
    @State private var adminPasscode  = ""
    @State private var adminError     = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0f3460"), Color(hex: "16213e"), Color(hex: "533483")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 50)

                    // ── Header ────────────────────────────────────────────
                    VStack(spacing: 14) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color(hex: "e94560"))

                        Text("ConnectDaDots")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Draw with precision. Earn coins.\nClimb the leaderboard.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                    }

                    // ── Name field ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What should we call you?")
                            .font(.headline).foregroundStyle(.white)

                        TextField("Enter your name", text: $displayName)
                            .textContentType(.name)
                            .padding()
                            .background(.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(nameError ? Color.red : Color.clear, lineWidth: 1.5)
                            )

                        if nameError {
                            Text("Please enter a name (at least 2 characters)")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 36)

                    // ── Play as Guest ─────────────────────────────────────
                    Button {
                        validateAndPlayAsGuest()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill").font(.headline)
                            Text("Play as Guest").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).opacity(0.6)
                        }
                        .padding()
                        .background(
                            LinearGradient(colors: [Color(hex: "e94560"), Color(hex: "c0392b")],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color(hex: "e94560").opacity(0.4), radius: 10, y: 4)
                    }
                    .padding(.horizontal, 36)

                    // ── OR divider ────────────────────────────────────────
                    HStack {
                        Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
                        Text("OR").font(.caption.bold()).foregroundStyle(.white.opacity(0.4))
                        Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
                    }
                    .padding(.horizontal, 50)

                    // ── Sign in with Apple ────────────────────────────────
                    VStack(spacing: 6) {
                        Text("Sign in for leaderboard & cloud sync")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))

                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleSignInResult(result)
                        }
                        .signInWithAppleButtonStyle(
                            colorScheme == .dark ? .white : .black
                        )
                        .frame(height: 52)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 36)

                    // ── Error message ─────────────────────────────────────
                    if let error = userSession.authError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .font(.caption).foregroundStyle(.red)
                        .padding(.horizontal, 36)
                    }

                    // ── iCloud status ─────────────────────────────────────
                    HStack(spacing: 6) {
                        Image(systemName: CloudKitManager.shared.isAvailable
                              ? "checkmark.icloud.fill" : "xmark.icloud")
                            .foregroundStyle(CloudKitManager.shared.isAvailable ? .green : .orange)
                            .font(.caption2)
                        Text(CloudKitManager.shared.statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Spacer().frame(height: 30)

                    // ── Admin (hidden) ────────────────────────────────────
                    adminSection

                    Spacer().frame(height: 20)
                }
            }
        }
    }

    // MARK: - Actions

    private func validateAndPlayAsGuest() {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        nameError = trimmed.count < 2
        guard !nameError else { return }
        userSession.setupGuest(name: trimmed)
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                userSession.authError = "Unexpected credential type"
                return
            }
            // If user typed a name and Apple doesn't provide one, use typed name.
            let trimmed = displayName.trimmingCharacters(in: .whitespaces)
            if credential.fullName?.givenName == nil && trimmed.count >= 2 {
                userSession.playerName = trimmed
            }
            userSession.handleAppleSignIn(credential: credential)

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            userSession.authError = error.localizedDescription
        }
    }

    // MARK: - Admin section

    private var adminSection: some View {
        VStack(spacing: 10) {
            Button { withAnimation { showAdminLogin.toggle() } } label: {
                Text("Developer / Admin")
                    .font(.caption2).foregroundStyle(.white.opacity(0.25))
            }

            if showAdminLogin {
                VStack(spacing: 10) {
                    SecureField("Admin passcode", text: $adminPasscode)
                        .padding()
                        .background(.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)

                    if adminError {
                        Text("Incorrect passcode").font(.caption).foregroundStyle(.red)
                    }

                    Button {
                        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
                        if trimmed.count >= 2 { userSession.playerName = trimmed }
                        adminError = !userSession.tryAdminLogin(passcode: adminPasscode)
                    } label: {
                        Text("Login as Admin")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.white.opacity(0.15))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 36)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
