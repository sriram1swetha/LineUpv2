import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject var userSession: UserSession

    @State private var name  = ""
    @State private var email = ""
    @State private var showAdminLogin = false
    @State private var adminPasscode = ""
    @State private var adminError = false
    @State private var nameError = false
    @State private var emailError = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") && email.contains(".")
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0f3460"), Color(hex: "16213e"), Color(hex: "533483")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
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

                    // Form
                    VStack(spacing: 16) {
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
                                Text("Please enter your name").font(.caption).foregroundStyle(.red)
                            }
                        }

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
                                Text("Please enter a valid email").font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 28)

                    // Register button
                    Button { attemptRegister() } label: {
                        Text("Create Account & Play")
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding()
                            .background(LinearGradient(colors: [Color(hex: "e94560"), Color(hex: "c0392b")],
                                                       startPoint: .leading, endPoint: .trailing))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color(hex: "e94560").opacity(0.4), radius: 10, y: 4)
                    }
                    .padding(.horizontal, 28)

                    // Admin login
                    Button { showAdminLogin.toggle() } label: {
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
                    }

                    Spacer(minLength: 40)
                }
            }
        }
    }

    private func attemptRegister() {
        nameError  = name.trimmingCharacters(in: .whitespaces).isEmpty
        emailError = !email.contains("@") || !email.contains(".")
        guard !nameError, !emailError else { return }
        userSession.register(name: name, email: email)
    }

    private func attemptAdminLogin() {
        adminError = !userSession.tryAdminLogin(passcode: adminPasscode)
    }
}
