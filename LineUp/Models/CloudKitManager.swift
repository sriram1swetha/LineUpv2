import Foundation
import CloudKit
import Combine

// ── CloudKit record types ──────────────────────────────────────────────────────
// Setup required in Xcode:
// 1. Project → Target → Signing & Capabilities → + Capability → iCloud
// 2. Check "CloudKit" and create container: iCloud.com.yourname.lineup
// 3. In CloudKit Dashboard define record types: PlayerScore, WeeklyLevel

struct LeaderboardEntry: Identifiable {
    let id: String
    let displayName: String  // First Name + Last Initial (e.g. "Sriram S.")
    let totalScore: Int
    let level: Int
    let game: Int
    let date: Date
}

struct WeeklyLevel: Identifiable {
    let id: String
    let weekNumber: Int
    let levelType: Int
    let title: String
    let releaseDate: Date
}

@MainActor
class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    @Published var leaderboardEntries: [LeaderboardEntry] = []
    @Published var weeklyLevels: [WeeklyLevel] = []
    @Published var isAvailable = false
    @Published var errorMessage: String? = nil

    private let container = CKContainer(identifier: "iCloud.com.sriramsistla.lineup")
    private var db: CKDatabase { container.publicCloudDatabase }

    private init() {}

    // ── Availability check ─────────────────────────────────────────────────

    func checkAvailability() async {
        do {
            let status = try await container.accountStatus()
            isAvailable = status == .available
        } catch {
            isAvailable = false
        }
    }

    // ── Submit score ───────────────────────────────────────────────────────

    func submitScore(playerName: String, email: String,
                     level: Int, game: Int, score: Int) async {
        guard isAvailable else { return }

        // Display name: First name + last initial
        let parts = playerName.split(separator: " ")
        let displayName: String
        if parts.count >= 2, let initial = parts[1].first {
            displayName = "\(parts[0]) \(initial)."
        } else {
            displayName = String(parts.first ?? Substring(playerName))
        }

        let record = CKRecord(recordType: "PlayerScore")
        record["displayName"]  = displayName as CKRecordValue
        record["emailHash"]    = email.data(using: .utf8)?.base64EncodedString() as? CKRecordValue
        record["level"]        = level as CKRecordValue
        record["game"]         = game as CKRecordValue
        record["score"]        = score as CKRecordValue
        record["submittedAt"]  = Date() as CKRecordValue

        do {
            _ = try await db.save(record)
        } catch {
            errorMessage = "Score upload failed: \(error.localizedDescription)"
        }
    }

    // ── Fetch leaderboard ──────────────────────────────────────────────────

    func fetchLeaderboard(level: Int, game: Int) async {
        guard isAvailable else { return }
        let pred = NSPredicate(format: "level == %d AND game == %d", level, game)
        let query = CKQuery(recordType: "PlayerScore", predicate: pred)
        query.sortDescriptors = [NSSortDescriptor(key: "score", ascending: false)]

        do {
            let (results, _) = try await db.records(matching: query, resultsLimit: 50)
            leaderboardEntries = results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return LeaderboardEntry(
                    id:          record.recordID.recordName,
                    displayName: record["displayName"] as? String ?? "—",
                    totalScore:  record["score"] as? Int ?? 0,
                    level:       record["level"] as? Int ?? level,
                    game:        record["game"] as? Int ?? game,
                    date:        record["submittedAt"] as? Date ?? Date()
                )
            }
        } catch {
            errorMessage = "Leaderboard unavailable: \(error.localizedDescription)"
        }
    }

    // ── Fetch weekly levels ────────────────────────────────────────────────

    func fetchWeeklyLevels() async {
        guard isAvailable else { return }
        let pred = NSPredicate(value: true)
        let query = CKQuery(recordType: "WeeklyLevel", predicate: pred)
        query.sortDescriptors = [NSSortDescriptor(key: "weekNumber", ascending: false)]

        do {
            let (results, _) = try await db.records(matching: query, resultsLimit: 52)
            weeklyLevels = results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return WeeklyLevel(
                    id:          record.recordID.recordName,
                    weekNumber:  record["weekNumber"] as? Int ?? 0,
                    levelType:   record["levelType"] as? Int ?? 1,
                    title:       record["title"] as? String ?? "Weekly Challenge",
                    releaseDate: record["releaseDate"] as? Date ?? Date()
                )
            }
        } catch {
            errorMessage = "Weekly levels unavailable"
        }
    }
}
