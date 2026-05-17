import Foundation
import Combine
import AuthenticationServices
import Security

// ── Account type ───────────────────────────────────────────────────────────────

enum AccountType: String, Codable {
    case guest       // UUID-based, name chosen by player
    case appleID     // Sign in with Apple
    case admin       // Admin (developer)
}

// ── App state ──────────────────────────────────────────────────────────────────

enum AppState {
    case needsWelcome    // First launch — show welcome screen
    case playing         // Full access (guest or signed in)
    case deactivated     // Account on hold
}

// ── User Session ───────────────────────────────────────────────────────────────

class UserSession: ObservableObject {
    static let shared = UserSession()

    static let adminPasscode = "LINEUP2024"

    // ── Persisted ──────────────────────────────────────────────────────────
    @Published var playerName: String        { didSet { saveLocal() } }
    @Published var playerEmail: String       { didSet { saveLocal() } }
    @Published var appleUserID: String       { didSet { saveLocal() } }
    @Published var guestID: String           { didSet { saveLocal() } }
    @Published var accountType: AccountType  { didSet { saveLocal() } }
    @Published var hasSeenWelcome: Bool      { didSet { saveLocal() } }

    // ── Deactivation ───────────────────────────────────────────────────────
    @Published var isDeactivated: Bool       { didSet { saveLocal() } }
    @Published var deactivationDate: Date?   { didSet { saveLocal() } }

    // ── Coin chest ─────────────────────────────────────────────────────────
    @Published var copperCoins: Int  { didSet { saveLocal() } }
    @Published var silverCoins: Int  { didSet { saveLocal() } }
    @Published var goldCoins: Int    { didSet { saveLocal() } }

    // ── Status ─────────────────────────────────────────────────────────────
    @Published var profileSyncedToCloud = false
    @Published var authError: String? = nil

    // ── Computed ───────────────────────────────────────────────────────────

    var appState: AppState {
        if isDeactivated { return .deactivated }
        if !hasSeenWelcome { return .needsWelcome }
        return .playing
    }

    var isAdmin: Bool   { accountType == .admin }
    var isGuest: Bool   { accountType == .guest }
    var isAppleID: Bool { accountType == .appleID }
    var isSignedIn: Bool { !appleUserID.isEmpty }

    /// The unique identifier used for leaderboard — Apple user ID or guest UUID.
    var playerID: String {
        if !appleUserID.isEmpty { return appleUserID }
        return guestID
    }

    /// Display name for leaderboard.
    var displayName: String {
        let parts = playerName.split(separator: " ")
        if parts.count >= 2, let initial = parts[1].first {
            return "\(parts[0]) \(initial)."
        }
        return playerName.isEmpty ? "Guest" : playerName
    }

    // ── Keys ───────────────────────────────────────────────────────────────
    private enum K {
        static let name         = "lu_playerName"
        static let email        = "lu_playerEmail"
        static let appleID      = "lu_appleUserID"
        static let guestID      = "lu_guestID"
        static let accountType  = "lu_accountType"
        static let welcome      = "lu_hasSeenWelcome"
        static let deactivated  = "lu_isDeactivated"
        static let deactivDate  = "lu_deactivationDate"
        static let synced       = "lu_profileSyncedToCloud"
        static let copper       = "lu_copperCoins"
        static let silver       = "lu_silverCoins"
        static let gold         = "lu_goldCoins"
        static let keychainGuestID = "com.connectdadots.guestID"
    }

    private init() {
        let d = UserDefaults.standard
        playerName     = d.string(forKey: K.name)    ?? ""
        playerEmail    = d.string(forKey: K.email)   ?? ""
        appleUserID    = d.string(forKey: K.appleID) ?? ""
        guestID        = d.string(forKey: K.guestID) ?? ""
        accountType    = AccountType(rawValue: d.string(forKey: K.accountType) ?? "") ?? .guest
        hasSeenWelcome = d.bool(forKey: K.welcome)
        isDeactivated  = d.bool(forKey: K.deactivated)
        if let ts = d.object(forKey: K.deactivDate) as? Date { deactivationDate = ts }
        else { deactivationDate = nil }
        profileSyncedToCloud = d.bool(forKey: K.synced)
        copperCoins    = d.integer(forKey: K.copper)
        silverCoins    = d.integer(forKey: K.silver)
        goldCoins      = d.integer(forKey: K.gold)

        // Restore or generate guest ID from Keychain (persists across reinstalls)
        if guestID.isEmpty {
            guestID = Self.keychainGuestID ?? Self.generateAndStoreGuestID()
        }

        // Check deactivation expiry (90 days)
        checkDeactivationExpiry()

        // Verify Apple ID credential on launch
        if !appleUserID.isEmpty {
            checkExistingCredential()
        }
    }

    private func saveLocal() {
        let d = UserDefaults.standard
        d.set(playerName,              forKey: K.name)
        d.set(playerEmail,             forKey: K.email)
        d.set(appleUserID,             forKey: K.appleID)
        d.set(guestID,                 forKey: K.guestID)
        d.set(accountType.rawValue,    forKey: K.accountType)
        d.set(hasSeenWelcome,          forKey: K.welcome)
        d.set(isDeactivated,           forKey: K.deactivated)
        d.set(deactivationDate,        forKey: K.deactivDate)
        d.set(profileSyncedToCloud,    forKey: K.synced)
        d.set(copperCoins,             forKey: K.copper)
        d.set(silverCoins,             forKey: K.silver)
        d.set(goldCoins,               forKey: K.gold)
    }

    // MARK: - Guest setup

    /// Called from WelcomeView when user taps "Play as Guest".
    func setupGuest(name: String) {
        playerName = name.trimmingCharacters(in: .whitespaces)
        accountType = .guest
        hasSeenWelcome = true
        authError = nil
    }

    // MARK: - Sign in with Apple

    func handleAppleSignIn(credential: ASAuthorizationAppleIDCredential) {
        let userID = credential.user

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
        accountType = .appleID
        hasSeenWelcome = true
        isDeactivated = false
        deactivationDate = nil
        authError = nil

        syncProfileToCloud()
    }

    /// Upgrade guest to Apple ID — migrate existing scores.
    func upgradeToAppleID(credential: ASAuthorizationAppleIDCredential) {
        let oldPlayerID = playerID
        handleAppleSignIn(credential: credential)
        // Migrate scores: update playerID in CloudKit
        CloudKitManager.shared.migrateScores(from: oldPlayerID, to: playerID,
                                              newDisplayName: displayName)
    }

    func checkExistingCredential() {
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: appleUserID) { [weak self] state, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .authorized:
                    break  // still valid
                case .revoked, .notFound:
                    // Credential gone — downgrade to guest (keep their data)
                    self.appleUserID = ""
                    self.accountType = .guest
                case .transferred:
                    break
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
            emailVerified: isAppleID
        ) { [weak self] success in
            self?.profileSyncedToCloud = success
        }
    }

    // MARK: - Admin

    func tryAdminLogin(passcode: String) -> Bool {
        guard passcode == UserSession.adminPasscode else { return false }
        accountType = .admin
        hasSeenWelcome = true
        return true
    }

    // MARK: - Coin awards

    func awardCoins(lineScores: [Int]) {
        let total = lineScores.reduce(0, +)
        let copper = total / 10
        if copper > 0 { copperCoins += copper }
        let silver = lineScores.filter { $0 >= 90 && $0 <= 95 }.count
        if silver > 0 { silverCoins += silver }
        let gold96 = lineScores.filter { $0 >= 96 && $0 <= 99 }.count
        let perfect = lineScores.filter { $0 == 100 }.count * 5
        if gold96 + perfect > 0 { goldCoins += gold96 + perfect }
    }

    // MARK: - Account deactivation (90-day hold)

    func deactivateAccount() {
        isDeactivated = true
        deactivationDate = Date()
    }

    func reactivateAccount() {
        isDeactivated = false
        deactivationDate = nil
    }

    private func checkDeactivationExpiry() {
        guard isDeactivated, let date = deactivationDate else { return }
        let daysSince = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysSince >= 90 {
            // Auto-delete after 90 days
            deleteAccount()
        }
    }

    // MARK: - Account deletion (permanent)

    func deleteAccount() {
        let pid = playerID

        // Delete from CloudKit
        CloudKitManager.shared.deleteAllPlayerData(playerID: pid)

        // Clear all local data
        playerName = ""
        playerEmail = ""
        appleUserID = ""
        accountType = .guest
        hasSeenWelcome = false
        isDeactivated = false
        deactivationDate = nil
        profileSyncedToCloud = false
        copperCoins = 0
        silverCoins = 0
        goldCoins = 0

        // Clear local scores
        ScoreStore.shared.deleteAll()

        // Generate a fresh guest ID
        guestID = Self.generateAndStoreGuestID()
    }

    // MARK: - Sign out (keeps data, just returns to welcome)

    func signOut() {
        appleUserID = ""
        accountType = .guest
        hasSeenWelcome = false
        profileSyncedToCloud = false
    }

    // MARK: - Keychain guest ID (persists across reinstalls)

    private static var keychainGuestID: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: K.keychainGuestID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func generateAndStoreGuestID() -> String {
        let id = UUID().uuidString
        let data = id.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: K.keychainGuestID,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)  // remove old if exists
        SecItemAdd(query as CFDictionary, nil)
        return id
    }
}
