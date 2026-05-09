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
    @Published var playerName: String       { didSet { saveLocal() } }
    @Published var playerEmail: String      { didSet { saveLocal() } }
    @Published var emailVerified: Bool      { didSet { saveLocal() } }
    @Published var role: UserRole           { didSet { saveLocal() } }
    @Published var hasCompletedIntro: Bool  { didSet { saveLocal() } }

    // ── Registration status for UI ─────────────────────────────────────────
    @Published var isRegistering = false
    @Published var registrationError: String? = nil
    @Published var profileSyncedToCloud = false

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

    /// Display name: First Name + Initial of Last Name (e.g. "Sriram S.")
    var displayName: String {
        let parts = playerName.split(separator: " ")
        if parts.count >= 2, let initial = parts[1].first {
            return "\(parts[0]) \(initial)."
        }
        return playerName
    }

    // ── Keys ───────────────────────────────────────────────────────────────
    private enum K {
        static let name     = "lu_playerName"
        static let email    = "lu_playerEmail"
        static let verified = "lu_emailVerified"
        static let role     = "lu_playerRole"
        static let intro    = "lu_hasCompletedIntro"
        static let synced   = "lu_profileSyncedToCloud"
    }

    private init() {
        let d = UserDefaults.standard
        playerName         = d.string(forKey: K.name)  ?? ""
        playerEmail        = d.string(forKey: K.email) ?? ""
        emailVerified      = d.bool(forKey: K.verified)
        role               = UserRole(rawValue: d.string(forKey: K.role) ?? "") ?? .guest
        hasCompletedIntro  = d.bool(forKey: K.intro)
        profileSyncedToCloud = d.bool(forKey: K.synced)

        // On launch, try to restore profile from CloudKit (cross-device sync).
        if role == .guest && !hasCompletedIntro {
            restoreFromCloud()
        }
    }

    private func saveLocal() {
        let d = UserDefaults.standard
        d.set(playerName,                forKey: K.name)
        d.set(playerEmail,               forKey: K.email)
        d.set(emailVerified,             forKey: K.verified)
        d.set(role.rawValue,             forKey: K.role)
        d.set(hasCompletedIntro,         forKey: K.intro)
        d.set(profileSyncedToCloud,      forKey: K.synced)
    }

    // MARK: - Registration

    /// Register a new player. Saves locally and to CloudKit.
    func register(name: String, email: String, verified: Bool = false) {
        let trimmedName  = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()

        playerName     = trimmedName
        playerEmail    = trimmedEmail
        emailVerified  = verified
        role           = .gamer
        registrationError = nil

        // Save to CloudKit
        syncProfileToCloud()
    }

    /// Mark email as verified (after confirmation step).
    func confirmEmailVerified() {
        emailVerified = true
        syncProfileToCloud()
    }

    // MARK: - CloudKit sync

    func syncProfileToCloud() {
        CloudKitManager.shared.saveProfile(
            displayName: displayName,
            email: playerEmail,
            emailVerified: emailVerified
        ) { [weak self] success in
            self?.profileSyncedToCloud = success
            if !success {
                print("UserSession: profile sync failed — will retry next launch.")
            }
        }
    }

    /// On launch, check if there's an existing profile in CloudKit
    /// (e.g. user reinstalled the app or is on a new device).
    private func restoreFromCloud() {
        CloudKitManager.shared.fetchProfile { [weak self] name, email, verified in
            guard let self, let name, !name.isEmpty else { return }
            // Found a profile — restore it.
            self.playerName    = name
            self.playerEmail   = email ?? ""
            self.emailVerified = verified ?? false
            self.role          = .gamer
            self.profileSyncedToCloud = true
        }
    }

    // MARK: - Admin

    func tryAdminLogin(passcode: String) -> Bool {
        guard passcode == UserSession.adminPasscode else { return false }
        role = .admin
        return true
    }

    // MARK: - Logout

    func logout() {
        role               = .guest
        playerName         = ""
        playerEmail        = ""
        emailVerified      = false
        hasCompletedIntro  = false
        profileSyncedToCloud = false
    }

    func markIntroComplete() {
        hasCompletedIntro = true
    }
}
