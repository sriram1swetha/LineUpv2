import SwiftUI
import AuthenticationServices

struct RegistrationView: View {
    @EnvironmentObject var userSession: UserSession
    @Environment(\.colorScheme) var colorScheme

    // ── Admin ──────────────────────────────────────────────────────────────
    @State private var showAdminLogin = false
    @State private var adminPasscode  = ""
    @State private var adminError     = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0f3460"), Color(hex: "16213e"), Color(hex: "533483")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // ── Header ────────────────────────────────────────────
                VStack(spacing: 14) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color(hex: "e94560"))

                    Text("Welcome to LineUp")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Sign in to save scores, unlock all levels,\nand compete on the leaderboard.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }

                // ── Sign in with Apple ────────────────────────────────
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
                .padding(.horizontal, 40)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                // ── Error message ─────────────────────────────────────
                if let error = userSession.authError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 40)
                }

                // ── Skip for now ──────────────────────────────────────
                Button {
                    // Let user continue as guest with limited features.
                    // They'll be prompted again next session.
                    userSession.role = .gamer
                    userSession.playerName = "Guest"
                } label: {
                    Text("Continue as Guest")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
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

                Spacer()

                // ── Admin login (hidden at bottom) ────────────────────
                adminSection

                Spacer().frame(height: 20)
            }
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
                .padding(.horizontal, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Handle Sign in with Apple result

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                userSession.authError = "Unexpected credential type"
                return
            }
            userSession.handleAppleSignIn(credential: credential)

        case .failure(let error):
            // ASAuthorizationError.canceled = user tapped Cancel — don't show error.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            userSession.authError = error.localizedDescription
        }
    }
}
