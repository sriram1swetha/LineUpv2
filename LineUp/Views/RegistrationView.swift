import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject var userSession: UserSession

    // ── Form fields ────────────────────────────────────────────────────────
    @State private var name         = ""
    @State private var email        = ""
    @State private var confirmEmail = ""

    // ── Validation ─────────────────────────────────────────────────────────
    @State private var nameError         = false
    @State private var emailError        = false
    @State private var emailMismatch     = false
    @State private var showConfirmStep   = false

    // ── Admin ──────────────────────────────────────────────────────────────
    @State private var showAdminLogin = false
    @State private var adminPasscode  = ""
    @State private var adminError     = false

    // ── Feedback ───────────────────────────────────────────────────────────
    @State private var isSaving = false
    @State private var showSuccess = false

    private var emailIsValid: Bool {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        return e.contains("@") && e.contains(".") && e.count >= 5
    }

    private var emailsMatch: Bool {
        email.trimmingCharacters(in: .whitespaces).lowercased() ==
        confirmEmail.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0f3460"), Color(hex: "16213e"), Color(hex: "533483")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header
                    formFields
                    registerButton

                    // Optional: Confirm email step (appears after first submit)
                    if showConfirmStep && !showSuccess {
                        confirmEmailSection
                    }

                    if showSuccess {
                        successBanner
                    }

                    adminSection

                    // iCloud status
                    iCloudStatus

                    Spacer(minLength: 40)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(Color(hex: "e94560"))
                .padding(.top, 48)

            Text("Join LineUp")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Create your free account to save scores,\nunlock all levels and compete on leaderboards.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Form fields

    private var formFields: some View {
        VStack(spacing: 16) {
            // Name
            VStack(alignment: .leading, spacing: 6) {
                Label("Full Name", systemImage: "person")
                    .font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                TextField("e.g. Sriram Sistla", text: $name)
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
                    Text("Please enter your full name (first and last)")
                        .font(.caption).foregroundStyle(.red)
                }
            }

            // Email
            VStack(alignment: .leading, spacing: 6) {
                Label("Email", systemImage: "envelope")
                    .font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                TextField("you@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(emailError ? Color.red : Color.clear, lineWidth: 1.5)
                    )
                if emailError {
                    Text("Please enter a valid email address")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Register button

    private var registerButton: some View {
        Button {
            attemptRegister()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().tint(.white)
                }
                Text(showConfirmStep ? "Register" : "Continue")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity).padding()
            .background(LinearGradient(colors: [Color(hex: "e94560"), Color(hex: "c0392b")],
                                       startPoint: .leading, endPoint: .trailing))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color(hex: "e94560").opacity(0.4), radius: 10, y: 4)
        }
        .disabled(isSaving)
        .padding(.horizontal, 28)
    }

    // MARK: - Confirm email step

    private var confirmEmailSection: some View {
        VStack(spacing: 12) {
            Text("Verify your email")
                .font(.headline).foregroundStyle(.white)

            Text("Re-enter your email to confirm it's correct. This step is optional — you can skip it.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            TextField("Confirm email", text: $confirmEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(emailMismatch ? Color.red : Color.clear, lineWidth: 1.5)
                )

            if emailMismatch {
                Text("Emails don't match — please check and try again")
                    .font(.caption).foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button {
                    verifyAndRegister()
                } label: {
                    Text("Confirm & Register")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.green.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    skipVerification()
                } label: {
                    Text("Skip")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.white.opacity(0.15))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 28)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Success banner

    private var successBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36)).foregroundStyle(.green)
            Text("Welcome, \(userSession.displayName)!")
                .font(.headline).foregroundStyle(.white)
            if userSession.emailVerified {
                Label("Email verified", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
        }
        .padding()
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Admin section

    private var adminSection: some View {
        VStack(spacing: 10) {
            Button { withAnimation { showAdminLogin.toggle() } } label: {
                Text("Developer / Admin login")
                    .font(.caption).foregroundStyle(.white.opacity(0.4))
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
                    Button { attemptAdminLogin() } label: {
                        Text("Login as Admin")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity).padding()
                            .background(Color.white.opacity(0.15))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - iCloud status

    private var iCloudStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: CloudKitManager.shared.isAvailable
                  ? "checkmark.icloud.fill" : "xmark.icloud")
                .foregroundStyle(CloudKitManager.shared.isAvailable ? .green : .orange)
            Text(CloudKitManager.shared.statusMessage)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func attemptRegister() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        nameError  = trimmedName.isEmpty || !trimmedName.contains(" ")
        emailError = !emailIsValid

        guard !nameError, !emailError else { return }

        if !showConfirmStep {
            // First tap — show the optional email confirmation step.
            withAnimation(.easeInOut(duration: 0.3)) {
                showConfirmStep = true
            }
            return
        }

        // Second tap without confirming — register without verification.
        skipVerification()
    }

    private func verifyAndRegister() {
        emailMismatch = !emailsMatch
        guard !emailMismatch else { return }

        isSaving = true
        userSession.register(name: name, email: email, verified: true)

        withAnimation(.spring(response: 0.5)) {
            showSuccess = true
            isSaving = false
        }
    }

    private func skipVerification() {
        isSaving = true
        userSession.register(name: name, email: email, verified: false)

        withAnimation(.spring(response: 0.5)) {
            showSuccess = true
            isSaving = false
        }
    }

    private func attemptAdminLogin() {
        // Admin also needs name + email.
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty {
            userSession.playerName  = trimmedName
            userSession.playerEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        }
        adminError = !userSession.tryAdminLogin(passcode: adminPasscode)
    }
}
