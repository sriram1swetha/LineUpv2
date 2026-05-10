import Foundation
import Combine
import AuthenticationServices

// ── Roles ──────────────────────────────────────────────────────────────────────

enum UserRole: String, Codable {
    case guest, gamer, admin
}

// ── App states ─────────────────────────────────────────────────────────────────

enum AppState {
    case guest          // Not registered — can only play intro
    case registering    // Forced sign-in screen after intro
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
    @Published var appleUserID: String      { didSet { saveLocal() } }
    @Published var role: UserRole           { didSet { saveLocal() } }
    @Published var hasCompletedIntro: Bool  { didSet { saveLocal() } }

    // ── Coin chest ─────────────────────────────────────────────────────────
    @Published var copperCoins: Int  { didSet { saveLocal() } }
    @Published var silverCoins: Int  { didSet { saveLocal() } }
    @Published var goldCoins: Int    { didSet { saveLocal() } }

    // ── Status ─────────────────────────────────────────────────────────────
    @Published var profileSyncedToCloud = false
    @Published var authError: String? = nil

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
    var isSignedIn: Bool { !appleUserID.isEmpty && role != .guest }

    /// Display name: First Name + Initial of Last Name (e.g. "Sriram S.")
    var displayName: String {
        let parts = playerName.split(separator: " ")
        if parts.count >= 2, let initial = parts[1].first {
            return "\(parts[0]) \(initial)."
        }
        return playerName.isEmpty ? "Player" : playerName
    }

    // ── Keys ───────────────────────────────────────────────────────────────
    private enum K {
        static let name      = "lu_playerName"
        static let email     = "lu_playerEmail"
        static let appleID   = "lu_appleUserID"
        static let role      = "lu_playerRole"
        static let intro     = "lu_hasCompletedIntro"
        static let synced    = "lu_profileSyncedToCloud"
        static let copper    = "lu_copperCoins"
        static let silver    = "lu_silverCoins"
        static let gold      = "lu_goldCoins"
    }

    private init() {
        let d = UserDefaults.standard
        playerName         = d.string(forKey: K.name)    ?? ""
        playerEmail        = d.string(forKey: K.email)   ?? ""
        appleUserID        = d.string(forKey: K.appleID) ?? ""
        role               = UserRole(rawValue: d.string(forKey: K.role) ?? "") ?? .guest
        hasCompletedIntro  = d.bool(forKey: K.intro)
        profileSyncedToCloud = d.bool(forKey: K.synced)
        copperCoins        = d.integer(forKey: K.copper)
        silverCoins        = d.integer(forKey: K.silver)
        goldCoins          = d.integer(forKey: K.gold)

        // On launch, verify the Apple ID credential is still valid.
        if !appleUserID.isEmpty {
            checkExistingCredential()
        }
    }

    private func saveLocal() {
        let d = UserDefaults.standard
        d.set(playerName,              forKey: K.name)
        d.set(playerEmail,             forKey: K.email)
        d.set(appleUserID,             forKey: K.appleID)
        d.set(role.rawValue,           forKey: K.role)
        d.set(hasCompletedIntro,       forKey: K.intro)
        d.set(profileSyncedToCloud,    forKey: K.synced)
        d.set(copperCoins,             forKey: K.copper)
        d.set(silverCoins,             forKey: K.silver)
        d.set(goldCoins,               forKey: K.gold)
    }

    /// Award coins based on per-connection scores.
    func awardCoins(lineScores: [Int]) {
        // Copper: 10% of total score
        let total = lineScores.reduce(0, +)
        let copper = total / 10
        if copper > 0 { copperCoins += copper }

        // Silver: 1 per score 90–95
        let silver = lineScores.filter { $0 >= 90 && $0 <= 95 }.count
        if silver > 0 { silverCoins += silver }

        // Gold: 1 per score 96–99, 5 per perfect 100
        let gold96to99 = lineScores.filter { $0 >= 96 && $0 <= 99 }.count
        let perfect100 = lineScores.filter { $0 == 100 }.count
        let goldTotal = gold96to99 + (perfect100 * 5)
        if goldTotal > 0 { goldCoins += goldTotal }
    }

    // MARK: - Sign in with Apple — completion handler

    /// Called by RegistrationView after a successful ASAuthorizationAppleIDCredential.
    func handleAppleSignIn(credential: ASAuthorizationAppleIDCredential) {
        let userID = credential.user

        // Apple only provides name & email on the FIRST sign-in.
        // On subsequent sign-ins these are nil — so only overwrite if present.
        if let fullName = credential.fullName {
            let first = fullName.givenName ?? ""
            let last  = fullName.familyName ?? ""
            let name  = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { playerName = name }
        }
        if let email = credential.email {
            playerEmail = email
        }

        appleUserID = userID
        role = .gamer
        authError = nil

        // Sync to CloudKit
        syncProfileToCloud()
    }

    // MARK: - Check existing credential on launch

    /// Verify the stored Apple ID is still authorized (user might have
    /// revoked access in Settings → Apple ID → Sign‑In & Security).
    func checkExistingCredential() {
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: appleUserID) { [weak self] state, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .authorized:
                    // Still valid — keep signed in.
                    if self.role == .guest { self.role = .gamer }
                case .revoked, .notFound:
                    // Credential gone — force re-sign-in.
                    self.appleUserID = ""
                    self.role = .guest
                case .transferred:
                    break   // App transferred to new dev team — rare edge case
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - CloudKit sync

    func syncProfileToCloud() {
        CloudKitManager.shared.saveProfile(
            displayName: displayName,
            email: playerEmail,
            emailVerified: true   // Apple-verified email
        ) { [weak self] success in
            self?.profileSyncedToCloud = success
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
        appleUserID        = ""
        hasCompletedIntro  = false
        profileSyncedToCloud = false
    }

    func markIntroComplete() {
        hasCompletedIntro = true
    }
}
