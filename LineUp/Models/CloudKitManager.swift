import Foundation
import CloudKit
import Combine

// ── Value types ────────────────────────────────────────────────────────────────

struct LeaderboardEntry: Identifiable {
    let id: String
    let playerID: String
    let displayName: String
    let level: Int
    let game: Int
    let score: Int
    let totalTime: Double
    let date: Date
    let weekOf: String
}

struct WeeklyLevelConfig: Identifiable {
    let id: String
    let weekNumber: Int
    let configJSON: String
    let publishedAt: Date
}

// ── Manager ────────────────────────────────────────────────────────────────────

class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var isAvailable = false
    @Published var statusMessage = "Checking iCloud…"
    @Published var weeklyLevel: WeeklyLevelConfig? = nil
    @Published var lastError: String? = nil      // visible to UI for debugging
    @Published var lastSubmitStatus: String? = nil

    private var publicDB: CKDatabase?
    private var privateDB: CKDatabase?
    private var profileRecordID: CKRecord.ID?   // cached after first save/fetch

    private init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupContainer()
        }
    }

    // MARK: - Container setup

    private func setupContainer() {
        let container = CKContainer.default()
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.isAvailable   = false
                    self.statusMessage = "iCloud error: \(error.localizedDescription)"
                    return
                }
                switch status {
                case .available:
                    self.publicDB      = container.publicCloudDatabase
                    self.privateDB     = container.privateCloudDatabase
                    self.isAvailable   = true
                    self.statusMessage = "Connected to iCloud"
                case .noAccount:
                    self.isAvailable   = false
                    self.statusMessage = "Sign in to iCloud in Settings to use online features"
                case .restricted:
                    self.isAvailable   = false
                    self.statusMessage = "iCloud access is restricted on this device"
                case .temporarilyUnavailable:
                    self.isAvailable   = false
                    self.statusMessage = "iCloud temporarily unavailable — try again later"
                default:
                    self.isAvailable   = false
                    self.statusMessage = "iCloud unavailable"
                }
            }
        }
    }

    // MARK: - Player Profile (private database)

    /// Save or update the player's profile in the private database.
    /// Uses a deterministic record ID so updates overwrite the previous record.
    func saveProfile(displayName: String, email: String,
                     emailVerified: Bool,
                     completion: @escaping (Bool) -> Void = { _ in }) {
        guard isAvailable, let db = privateDB else {
            completion(false); return
        }

        let recordID = CKRecord.ID(recordName: "PlayerProfile_v1")
        self.profileRecordID = recordID

        // Fetch-then-update to avoid "server record changed" errors.
        db.fetch(withRecordID: recordID) { existing, _ in
            let record = existing ?? CKRecord(recordType: "PlayerProfile", recordID: recordID)
            record["displayName"]   = displayName    as CKRecordValue
            record["email"]         = email          as CKRecordValue
            record["emailVerified"] = (emailVerified ? 1 : 0) as CKRecordValue
            if existing == nil {
                record["createdAt"] = Date() as CKRecordValue
            }

            db.save(record) { [weak self] _, error in
                DispatchQueue.main.async {
                    if let error {
                        self?.lastError = "saveProfile: \(error.localizedDescription)"
                        print("CloudKit saveProfile error: \(error)")
                        completion(false)
                    } else {
                        self?.lastError = nil
                        completion(true)
                    }
                }
            }
        }
    }

    /// Fetch the player's profile from the private database (e.g. on launch
    /// to restore state across devices).
    func fetchProfile(completion: @escaping (String?, String?, Bool?) -> Void) {
        guard isAvailable, let db = privateDB else {
            completion(nil, nil, nil); return
        }

        let recordID = CKRecord.ID(recordName: "PlayerProfile_v1")
        db.fetch(withRecordID: recordID) { record, error in
            DispatchQueue.main.async {
                if let record {
                    let name     = record["displayName"]   as? String
                    let email    = record["email"]          as? String
                    let verified = (record["emailVerified"] as? Int) == 1
                    completion(name, email, verified)
                } else {
                    completion(nil, nil, nil)
                }
            }
        }
    }

    // MARK: - Score submission (public database)

    /// Current ISO week string, e.g. "2026-W19".
    static var currentWeekOf: String {
        let cal  = Calendar(identifier: .iso8601)
        let comp = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return String(format: "%04d-W%02d",
                      comp.yearForWeekOfYear ?? 2026,
                      comp.weekOfYear ?? 1)
    }

    func submitScore(playerID: String, displayName: String, level: Int, game: Int,
                     score: Int, totalTime: Double) {
        guard isAvailable, let db = publicDB else {
            DispatchQueue.main.async {
                self.lastError = "CloudKit not available (isAvailable=\(self.isAvailable), db=\(self.publicDB != nil))"
                self.lastSubmitStatus = "Failed: not available"
            }
            return
        }

        DispatchQueue.main.async {
            self.lastSubmitStatus = "Submitting…"
            self.lastError = nil
        }

        let record = CKRecord(recordType: "PlayerScore")
        record["playerID"]    = playerID                     as CKRecordValue
        record["displayName"] = displayName                  as CKRecordValue
        record["level"]       = level                        as CKRecordValue
        record["game"]        = game                         as CKRecordValue
        record["score"]       = score                        as CKRecordValue
        record["totalTime"]   = totalTime                    as CKRecordValue
        record["weekOf"]      = CloudKitManager.currentWeekOf as CKRecordValue

        db.save(record) { [weak self] savedRecord, error in
            DispatchQueue.main.async {
                if let error {
                    self?.lastError = "submitScore: \(error.localizedDescription)"
                    self?.lastSubmitStatus = "Failed"
                    print("CloudKit submitScore error: \(error)")
                } else {
                    self?.lastSubmitStatus = "Submitted ✓ (ID: \(savedRecord?.recordID.recordName ?? "?"))"
                    self?.lastError = nil
                    print("CloudKit submitScore success: \(savedRecord?.recordID.recordName ?? "")")
                }
            }
        }
    }

    // MARK: - Leaderboard (public database)

    /// Fetch top scores for a specific level + game, optionally filtered by week.
    func fetchLeaderboard(level: Int, game: Int? = nil,
                          weekOf: String? = nil, limit: Int = 20) {
        guard isAvailable, let db = publicDB else { return }

        var formatParts: [String] = ["level == %d"]
        var args: [Any] = [level]
        if let g = game {
            formatParts.append("game == %d")
            args.append(g)
        }
        if let week = weekOf {
            formatParts.append("weekOf == %@")
            args.append(week)
        }

        let predicate = NSPredicate(format: formatParts.joined(separator: " AND "),
                                    argumentArray: args)

        let query = CKQuery(recordType: "PlayerScore", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "score", ascending: false)]

        let operation        = CKQueryOperation(query: query)
        operation.resultsLimit = limit
        var entries: [LeaderboardEntry] = []

        operation.recordMatchedBlock = { _, result in
            if case .success(let r) = result,
               let name  = r["displayName"] as? String,
               let lv    = r["level"]       as? Int,
               let gm    = r["game"]        as? Int,
               let sc    = r["score"]       as? Int {
                let pid  = r["playerID"]    as? String ?? ""
                let time = r["totalTime"]   as? Double ?? 0
                let week = r["weekOf"]      as? String ?? ""
                entries.append(LeaderboardEntry(
                    id: r.recordID.recordName,
                    playerID: pid,
                    displayName: name, level: lv, game: gm,
                    score: sc, totalTime: time,
                    date: r.creationDate ?? Date(), weekOf: week))
            }
        }

        operation.queryResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.leaderboard = entries
                    self?.lastError = entries.isEmpty ? "Leaderboard query OK — 0 results" : nil
                case .failure(let error):
                    self?.lastError = "fetchLeaderboard: \(error.localizedDescription)"
                    print("CloudKit fetchLeaderboard error: \(error)")
                }
            }
        }

        db.add(operation)
    }

    // MARK: - Weekly level (public database)

    func fetchWeeklyLevel() {
        guard isAvailable, let db = publicDB else { return }

        let predicate = NSPredicate(format: "isActive == 1")
        let query     = CKQuery(recordType: "WeeklyLevel", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "weekNumber", ascending: false)]

        let operation        = CKQueryOperation(query: query)
        operation.resultsLimit = 1

        operation.recordMatchedBlock = { [weak self] _, result in
            if case .success(let r) = result,
               let week = r["weekNumber"]  as? Int,
               let json = r["configJSON"]  as? String,
               let date = r["publishedAt"] as? Date {
                DispatchQueue.main.async {
                    self?.weeklyLevel = WeeklyLevelConfig(
                        id: r.recordID.recordName,
                        weekNumber: week, configJSON: json, publishedAt: date)
                }
            }
        }

        operation.queryResultBlock = { result in
            if case .failure(let error) = result {
                print("CloudKit fetchWeeklyLevel error: \(error.localizedDescription)")
            }
        }

        db.add(operation)
    }

    // MARK: - Retry

    func retryConnection() {
        isAvailable   = false
        statusMessage = "Reconnecting…"
        publicDB      = nil
        privateDB     = nil
        setupContainer()
    }
}
