import Foundation
import CloudKit
import Combine

// ── CloudKit setup instructions (do this BEFORE testing) ──────────────────────
//
// Step 1 — Enable iCloud capability in Xcode:
//   Project navigator → LineUp target → Signing & Capabilities
//   → "+ Capability" → iCloud
//   → Check "CloudKit"
//   → Under "Containers" click "+" to create a new container
//      (Xcode will name it iCloud.com.yourname.LineUp automatically)
//
// Step 2 — Create record types in CloudKit Dashboard:
//   https://icloud.developer.apple.com
//   → Select your container → Schema → Record Types → New Type
//   Create "PlayerScore" with fields:
//     displayName (String), level (Int64), game (Int64),
//     score (Int64), totalTime (Double), date (Date/Time)
//   Create "WeeklyLevel" with fields:
//     weekNumber (Int64), configJSON (String),
//     publishedAt (Date/Time), isActive (Int64)
//
// Until Step 1 is done, all CloudKit calls are safely skipped.
// The app will never crash — it degrades gracefully to local-only mode.

// ── Value types ────────────────────────────────────────────────────────────────

struct LeaderboardEntry: Identifiable {
    let id: String
    let displayName: String
    let level: Int
    let game: Int
    let score: Int
    let totalTime: Double
    let date: Date
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

    // Uses CKContainer.default() — reads from your app's entitlements,
    // never hard-codes a container ID that might not exist yet.
    private var publicDB: CKDatabase? = nil

    private init() {
        setupContainer()
    }

    // ── Safe container setup ───────────────────────────────────────────────

    private func setupContainer() {
        // Wrap in a do/catch equivalent using a deferred availability check.
        // CKContainer.default() itself never crashes, but account status
        // checks can fail gracefully.
        let container = CKContainer.default()
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .available:
                    self.publicDB    = container.publicCloudDatabase
                    self.isAvailable = true
                    self.statusMessage = "Connected to iCloud"
                case .noAccount:
                    self.isAvailable  = false
                    self.statusMessage = "Sign in to iCloud in Settings to use the leaderboard"
                case .restricted:
                    self.isAvailable  = false
                    self.statusMessage = "iCloud access is restricted on this device"
                case .couldNotDetermine:
                    self.isAvailable  = false
                    self.statusMessage = "Could not determine iCloud status"
                case .temporarilyUnavailable:
                    self.isAvailable  = false
                    self.statusMessage = "iCloud temporarily unavailable — try again later"
                @unknown default:
                    self.isAvailable  = false
                    self.statusMessage = "iCloud unavailable"
                }
            }
        }
    }

    // ── Submit score ───────────────────────────────────────────────────────

    func submitScore(displayName: String, level: Int, game: Int,
                     score: Int, totalTime: Double) {
        guard isAvailable, let db = publicDB else { return }

        let record = CKRecord(recordType: "PlayerScore")
        record["displayName"] = displayName as CKRecordValue
        record["level"]       = level       as CKRecordValue
        record["game"]        = game        as CKRecordValue
        record["score"]       = score       as CKRecordValue
        record["totalTime"]   = totalTime   as CKRecordValue
        record["date"]        = Date()      as CKRecordValue

        db.save(record) { _, error in
            if let error {
                print("CloudKit submitScore error: \(error.localizedDescription)")
            }
        }
    }

    // ── Fetch leaderboard ──────────────────────────────────────────────────

    func fetchLeaderboard(level: Int, game: Int, limit: Int = 20) {
        guard isAvailable, let db = publicDB else { return }

        let predicate = NSPredicate(format: "level == %d AND game == %d", level, game)
        let query     = CKQuery(recordType: "PlayerScore", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "score", ascending: false)]

        let operation        = CKQueryOperation(query: query)
        operation.resultsLimit = limit
        var entries: [LeaderboardEntry] = []

        operation.recordMatchedBlock = { _, result in
            if case .success(let record) = result,
               let name  = record["displayName"] as? String,
               let level = record["level"]        as? Int,
               let game  = record["game"]         as? Int,
               let score = record["score"]        as? Int,
               let time  = record["totalTime"]    as? Double,
               let date  = record["date"]         as? Date {
                entries.append(LeaderboardEntry(
                    id: record.recordID.recordName,
                    displayName: name, level: level, game: game,
                    score: score, totalTime: time, date: date))
            }
        }

        operation.queryResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.leaderboard = entries
                case .failure(let error):
                    print("CloudKit fetchLeaderboard error: \(error.localizedDescription)")
                }
            }
        }

        db.add(operation)
    }

    // ── Fetch current weekly level ─────────────────────────────────────────

    func fetchWeeklyLevel() {
        guard isAvailable, let db = publicDB else { return }

        let predicate = NSPredicate(format: "isActive == 1")
        let query     = CKQuery(recordType: "WeeklyLevel", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "weekNumber", ascending: false)]

        let operation        = CKQueryOperation(query: query)
        operation.resultsLimit = 1

        operation.recordMatchedBlock = { [weak self] _, result in
            if case .success(let record) = result,
               let week = record["weekNumber"]  as? Int,
               let json = record["configJSON"]  as? String,
               let date = record["publishedAt"] as? Date {
                DispatchQueue.main.async {
                    self?.weeklyLevel = WeeklyLevelConfig(
                        id: record.recordID.recordName,
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

    // ── Retry connection ───────────────────────────────────────────────────

    func retryConnection() {
        isAvailable    = false
        statusMessage  = "Reconnecting…"
        publicDB       = nil
        setupContainer()
    }
}
