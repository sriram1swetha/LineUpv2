import Foundation
import Combine

// ── Roles ──────────────────────────────────────────────────────────────────────

enum UserRole: String, Codable {
    case guest, gamer, admin
}

// ── App states ─────────────────────────────────────────────────────────────────

enum AppState {
    case guest          // Not registered — can only play intro
    case registering    // Forced registration screen after intro
    case registered     // Full access as gamer
    case admin          // Full access + admin settings
}

// ── User Session ───────────────────────────────────────────────────────────────

class UserSession: ObservableObject {
    static let shared = UserSession()

    // ── Admin passcode (hardcoded) ─────────────────────────────────────────
    static let adminPasscode = "LINEUP2024"

    // ── Persisted user data ────────────────────────────────────────────────
    @Published var playerName: String  { didSet { save() } }
    @Published var playerEmail: String { didSet { save() } }
    @Published var role: UserRole      { didSet { save() } }
    @Published var hasCompletedIntro: Bool { didSet { save() } }

    var appState: AppState {
        switch role {
        case .admin:  return .admin
        case .gamer:  return .registered
        case .guest:
            return hasCompletedIntro ? .registering : .guest
        }
    }

    var isAdmin: Bool   { role == .admin }
    var isGamer: Bool   { role == .gamer || role == .admin }
    var isGuest: Bool   { role == .guest }

    /// Display name: First Name + Initial of Last Name
    var displayName: String {
        let parts = playerName.split(separator: " ")
        if parts.count >= 2, let initial = parts[1].first {
            return "\(parts[0]) \(initial)."
        }
        return playerName
    }

    private let nameKey       = "lu_playerName"
    private let emailKey      = "lu_playerEmail"
    private let roleKey       = "lu_playerRole"
    private let introKey      = "lu_hasCompletedIntro"

    private init() {
        let d = UserDefaults.standard
        playerName          = d.string(forKey: "lu_playerName")  ?? ""
        playerEmail         = d.string(forKey: "lu_playerEmail") ?? ""
        role                = UserRole(rawValue: d.string(forKey: "lu_playerRole") ?? "") ?? .guest
        hasCompletedIntro   = d.bool(forKey: "lu_hasCompletedIntro")
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(playerName,          forKey: nameKey)
        d.set(playerEmail,         forKey: emailKey)
        d.set(role.rawValue,       forKey: roleKey)
        d.set(hasCompletedIntro,   forKey: introKey)
    }

    // ── Auth actions ───────────────────────────────────────────────────────

    func register(name: String, email: String) {
        playerName  = name.trimmingCharacters(in: .whitespaces)
        playerEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        role        = .gamer
    }

    func tryAdminLogin(passcode: String) -> Bool {
        guard passcode == UserSession.adminPasscode else { return false }
        role = .admin
        return true
    }

    func logout() {
        role = .guest
        playerName = ""
        playerEmail = ""
        hasCompletedIntro = false
    }

    func markIntroComplete() {
        hasCompletedIntro = true
    }
}
