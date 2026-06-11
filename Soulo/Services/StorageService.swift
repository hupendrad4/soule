import Foundation
import SQLite3

final class StorageService: Sendable {
    static let shared = StorageService()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.soulo.storage", qos: .userInitiated)

    private var dbPath: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appending(path: "soulo.sqlite")
    }

    private init() {}

    func initialize() throws {
        try queue.sync {
            let path = dbPath.path
            let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FILEPROTECTION_COMPLETE
            guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
                throw StorageError.couldNotOpen(String(cString: sqlite3_errmsg(db)))
            }
            try applyMigrations()
        }
    }

    // MARK: - Journal Entries

    func saveEntry(_ entry: JournalEntry) throws {
        try queue.sync {
            let sql = """
                INSERT OR REPLACE INTO entries (
                    id, timestamp, timezone_offset, duration_ms,
                    audio_format, audio_encrypted, audio_file_size,
                    transcript, transcript_status, transcript_error, transcript_ms,
                    biomarkers_json, biomarkers_status, biomarkers_error,
                    emotion_json, emotion_status, emotion_error,
                    topics_json, topics_status, topics_error,
                    app_version, device_model, os_version, created_at, updated_at
                ) VALUES (?,?,?,?, ?,?,?, ?,?,?,?, ?,?,?, ?,?,?, ?,?,?, ?,?,?, ?,?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (entry.id as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, entry.timestamp)
            sqlite3_bind_int(stmt, 3, Int32(entry.timezoneOffset))
            sqlite3_bind_int(stmt, 4, Int32(entry.durationMs))
            sqlite3_bind_text(stmt, 5, (entry.audioFormat as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 6, entry.audioEncrypted ? 1 : 0)
            bindOptionalInt(stmt, 7, entry.audioFileSize)
            bindOptionalText(stmt, 8, entry.transcript)
            bindOptionalText(stmt, 9, entry.transcriptStatus.rawValue)
            bindOptionalText(stmt, 10, entry.transcriptError)
            bindOptionalInt(stmt, 11, entry.transcriptMs)
            bindOptionalText(stmt, 12, entry.biomarkersJson)
            bindOptionalText(stmt, 13, entry.biomarkersStatus.rawValue)
            bindOptionalText(stmt, 14, entry.biomarkersError)
            bindOptionalText(stmt, 15, entry.emotionJson)
            bindOptionalText(stmt, 16, entry.emotionStatus.rawValue)
            bindOptionalText(stmt, 17, entry.emotionError)
            bindOptionalText(stmt, 18, entry.topicsJson)
            bindOptionalText(stmt, 19, entry.topicsStatus.rawValue)
            bindOptionalText(stmt, 20, entry.topicsError)
            bindOptionalText(stmt, 21, entry.appVersion)
            bindOptionalText(stmt, 22, entry.deviceModel)
            bindOptionalText(stmt, 23, entry.osVersion)
            sqlite3_bind_double(stmt, 24, entry.createdAt)
            sqlite3_bind_double(stmt, 25, entry.updatedAt)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StorageError.writeFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    func loadEntries(from startDate: TimeInterval? = nil, to endDate: TimeInterval? = nil) throws -> [JournalEntry] {
        try queue.sync {
            var sql = "SELECT * FROM entries"
            var conditions: [String] = []
            if let start = startDate { conditions.append("timestamp >= \(start)") }
            if let end = endDate { conditions.append("timestamp <= \(end)") }
            if !conditions.isEmpty { sql += " WHERE " + conditions.joined(separator: " AND ") }
            sql += " ORDER BY timestamp DESC"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.readFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            var entries: [JournalEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                entries.append(readEntry(from: stmt!))
            }
            return entries
        }
    }

    func loadEntry(id: String) throws -> JournalEntry? {
        try queue.sync {
            let sql = "SELECT * FROM entries WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return readEntry(from: stmt!)
        }
    }

    func deleteEntry(id: String) throws {
        try queue.sync {
            let sql = "DELETE FROM entries WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
            deleteAudioFile(for: id)
        }
    }

    // MARK: - Patterns

    func savePatterns(_ patterns: [DetectedPattern]) throws {
        try queue.sync {
            for pattern in patterns {
                let sql = """
                    INSERT OR REPLACE INTO patterns (
                        id, pattern_type, severity, title, message, data_json,
                        first_detected, last_detected, occurrence_count, dismissed,
                        created_at, updated_at
                    ) VALUES (?,?,?,?,?,?, ?,?,?,?, ?,?)
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, (pattern.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (pattern.patternType.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 3, Int32(pattern.severity))
                bindOptionalText(stmt, 4, pattern.title)
                bindOptionalText(stmt, 5, pattern.message)
                bindOptionalText(stmt, 6, pattern.dataJson)
                sqlite3_bind_double(stmt, 7, pattern.firstDetected)
                sqlite3_bind_double(stmt, 8, pattern.lastDetected)
                sqlite3_bind_int(stmt, 9, Int32(pattern.occurrenceCount))
                sqlite3_bind_int(stmt, 10, pattern.dismissed ? 1 : 0)
                sqlite3_bind_double(stmt, 11, pattern.createdAt)
                sqlite3_bind_double(stmt, 12, pattern.updatedAt)
                sqlite3_step(stmt)
            }
        }
    }

    func loadPatterns(activeOnly: Bool = true) throws -> [DetectedPattern] {
        try queue.sync {
            var sql = "SELECT * FROM patterns"
            if activeOnly { sql += " WHERE dismissed = 0" }
            sql += " ORDER BY severity DESC LIMIT 50"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.readFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            var patterns: [DetectedPattern] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                patterns.append(readPattern(from: stmt!))
            }
            return patterns
        }
    }

    func deleteAll() throws {
        try queue.sync {
            sqlite3_exec(db, "DELETE FROM entries", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM patterns", nil, nil, nil)
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let audioDir = docs.appending(path: "audio_encrypted")
            try? FileManager.default.removeItem(at: audioDir)
        }
    }

    func dismissPattern(_ id: String) throws {
        try queue.sync {
            let sql = "UPDATE patterns SET dismissed = 1, updated_at = ? WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Decisions

    func saveDecisions(_ decisions: [JournalDecision]) throws {
        try queue.sync {
            for d in decisions {
                let sql = """
                    INSERT OR REPLACE INTO decisions (
                        id, entry_id, decision_text, category, expected_outcome,
                        status, follow_up_entry_id, follow_up_sentiment, follow_up_text,
                        first_mentioned, last_mentioned, mention_count, created_at
                    ) VALUES (?,?,?,?,?, ?,?,?,?, ?,?,?,?)
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, (d.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (d.entryId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (d.decisionText as NSString).utf8String, -1, nil)
                bindOptionalText(stmt, 4, d.category)
                bindOptionalText(stmt, 5, d.expectedOutcome)
                sqlite3_bind_text(stmt, 6, (d.status.rawValue as NSString).utf8String, -1, nil)
                bindOptionalText(stmt, 7, d.followUpEntryId)
                bindOptionalDouble(stmt, 8, d.followUpSentiment)
                bindOptionalText(stmt, 9, d.followUpText)
                sqlite3_bind_double(stmt, 10, d.firstMentioned)
                sqlite3_bind_double(stmt, 11, d.lastMentioned)
                sqlite3_bind_int(stmt, 12, Int32(d.mentionCount))
                sqlite3_bind_double(stmt, 13, d.createdAt)
                sqlite3_step(stmt)
            }
        }
    }

    func loadDecisions(activeOnly: Bool = true) throws -> [JournalDecision] {
        try queue.sync {
            var sql = "SELECT * FROM decisions"
            if activeOnly { sql += " WHERE status IN ('active','pending')" }
            sql += " ORDER BY first_mentioned DESC"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StorageError.readFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            var decisions: [JournalDecision] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                decisions.append(readDecision(from: stmt!))
            }
            return decisions
        }
    }

    // MARK: - Settings

    func getSetting(_ key: String) -> String? {
        queue.sync {
            let sql = "SELECT value FROM settings WHERE key = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return String(cString: sqlite3_column_text(stmt, 0))
        }
    }

    func setSetting(_ key: String, value: String) throws {
        try queue.sync {
            let sql = "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?,?,?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Subscription

    func getSubscription() -> SubscriptionInfo {
        queue.sync {
            let sql = "SELECT * FROM subscription WHERE id = 1"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return .default }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return .default }
            return readSubscription(from: stmt!)
        }
    }

    func saveSubscription(_ info: SubscriptionInfo) throws {
        try queue.sync {
            let sql = """
                INSERT OR REPLACE INTO subscription (id, status, plan_type, original_id, current_id,
                    expires_at, auto_renew, trial_start, trial_end, updated_at)
                VALUES (1,?,?,?,?, ?,?,?,?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (info.status.rawValue as NSString).utf8String, -1, nil)
            bindOptionalText(stmt, 2, info.planType?.rawValue)
            bindOptionalText(stmt, 3, info.originalId)
            bindOptionalText(stmt, 4, info.currentId)
            bindOptionalDouble(stmt, 5, info.expiresAt)
            sqlite3_bind_int(stmt, 6, info.autoRenew ? 1 : 0)
            bindOptionalDouble(stmt, 7, info.trialStart)
            bindOptionalDouble(stmt, 8, info.trialEnd)
            sqlite3_bind_double(stmt, 9, info.updatedAt)
            sqlite3_step(stmt)
        }
    }

    // MARK: - Maintenance

    func reindexTimestamps() throws {
        try queue.sync {
            sqlite3_exec(db, "REINDEX idx_entries_timestamp", nil, nil, nil)
        }
    }

    func runIntegrityCheck() -> Bool {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &stmt, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return false }
            let result = String(cString: sqlite3_column_text(stmt, 0))
            return result == "ok"
        }
    }

    func close() {
        queue.sync {
            sqlite3_close(db)
            db = nil
        }
    }

    // MARK: - Private

    private func applyMigrations() throws {
        let currentVersion = getSchemaVersion()
        let migrations = SchemaMigrations.all

        for migration in migrations where migration.version > currentVersion {
            try migration.apply(db: db, queue: queue)
            setSchemaVersion(migration.version)
        }
    }

    private func getSchemaVersion() -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(version) FROM schema_migrations", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func setSchemaVersion(_ version: Int) {
        var stmt: OpaquePointer?
        let sql = "INSERT INTO schema_migrations (version, description, applied_at) VALUES (?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 0, Int32(version))
        sqlite3_bind_text(stmt, 1, "Migration v\(version)", -1, nil)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    private func deleteAudioFile(for entryId: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let audioURL = docs.appending(path: "audio/\(entryId).aac")
        try? FileManager.default.removeItem(at: audioURL)
    }

    // MARK: - Row Readers

    private func readEntry(from stmt: OpaquePointer) -> JournalEntry {
        var e = JournalEntry(
            id: stringColumn(stmt, 0),
            timestamp: doubleColumn(stmt, 1),
            timezoneOffset: intColumn(stmt, 2),
            durationMs: intColumn(stmt, 3),
            audioFormat: stringColumn(stmt, 4),
            audioEncrypted: intColumn(stmt, 5) == 1
        )
        e.audioFileSize = optionalIntColumn(stmt, 6)
        e.transcript = optionalStringColumn(stmt, 7)
        e.transcriptStatus = ProcessingStatus(rawValue: stringColumn(stmt, 8)) ?? .pending
        e.transcriptError = optionalStringColumn(stmt, 9)
        e.transcriptMs = optionalIntColumn(stmt, 10)
        e.biomarkersJson = optionalStringColumn(stmt, 11)
        e.biomarkersStatus = ProcessingStatus(rawValue: stringColumn(stmt, 12)) ?? .pending
        e.biomarkersError = optionalStringColumn(stmt, 13)
        e.emotionJson = optionalStringColumn(stmt, 14)
        e.emotionStatus = ProcessingStatus(rawValue: stringColumn(stmt, 15)) ?? .pending
        e.emotionError = optionalStringColumn(stmt, 16)
        e.topicsJson = optionalStringColumn(stmt, 17)
        e.topicsStatus = ProcessingStatus(rawValue: stringColumn(stmt, 18)) ?? .pending
        e.topicsError = optionalStringColumn(stmt, 19)
        e.updatedAt = doubleColumn(stmt, 24)
        return e
    }

    private func readPattern(from stmt: OpaquePointer) -> DetectedPattern {
        DetectedPattern(
            id: stringColumn(stmt, 0),
            patternType: PatternType(rawValue: stringColumn(stmt, 1)) ?? .contradiction,
            severity: intColumn(stmt, 2),
            title: stringColumn(stmt, 3),
            message: stringColumn(stmt, 4),
            dataJson: optionalStringColumn(stmt, 5),
            firstDetected: doubleColumn(stmt, 6),
            lastDetected: doubleColumn(stmt, 7),
            occurrenceCount: intColumn(stmt, 8)
        )
    }

    private func readDecision(from stmt: OpaquePointer) -> JournalDecision {
        JournalDecision(
            id: stringColumn(stmt, 0),
            entryId: stringColumn(stmt, 1),
            decisionText: stringColumn(stmt, 2),
            category: optionalStringColumn(stmt, 3),
            expectedOutcome: optionalStringColumn(stmt, 4),
            status: DecisionStatus(rawValue: stringColumn(stmt, 5)) ?? .active,
            followUpEntryId: optionalStringColumn(stmt, 6),
            followUpSentiment: optionalDoubleColumn(stmt, 7),
            followUpText: optionalStringColumn(stmt, 8),
            firstMentioned: doubleColumn(stmt, 9),
            lastMentioned: doubleColumn(stmt, 10),
            mentionCount: intColumn(stmt, 11)
        )
    }

    private func readSubscription(from stmt: OpaquePointer) -> SubscriptionInfo {
        SubscriptionInfo(
            status: SubscriptionStatus(rawValue: stringColumn(stmt, 1)) ?? .free,
            planType: SubscriptionPlan(rawValue: optionalStringColumn(stmt, 2) ?? ""),
            originalId: optionalStringColumn(stmt, 3),
            currentId: optionalStringColumn(stmt, 4),
            expiresAt: optionalDoubleColumn(stmt, 5),
            autoRenew: intColumn(stmt, 6) == 1,
            trialStart: optionalDoubleColumn(stmt, 7),
            trialEnd: optionalDoubleColumn(stmt, 8),
            updatedAt: doubleColumn(stmt, 9)
        )
    }

    // MARK: - Column Helpers

    private func stringColumn(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        String(cString: sqlite3_column_text(stmt, idx))
    }
    private func optionalStringColumn(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, idx))
    }
    private func intColumn(_ stmt: OpaquePointer?, _ idx: Int32) -> Int { Int(sqlite3_column_int(stmt, idx)) }
    private func optionalIntColumn(_ stmt: OpaquePointer?, _ idx: Int32) -> Int? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, idx))
    }
    private func doubleColumn(_ stmt: OpaquePointer?, _ idx: Int32) -> Double { sqlite3_column_double(stmt, idx) }
    private func optionalDoubleColumn(_ stmt: OpaquePointer?, _ idx: Int32) -> Double? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, idx)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String?) {
        if let v = value { sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, nil) }
        else { sqlite3_bind_null(stmt, idx) }
    }
    private func bindOptionalInt(_ stmt: OpaquePointer?, _ idx: Int32, _ value: Int?) {
        if let v = value { sqlite3_bind_int(stmt, idx, Int32(v)) }
        else { sqlite3_bind_null(stmt, idx) }
    }
    private func bindOptionalDouble(_ stmt: OpaquePointer?, _ idx: Int32, _ value: Double?) {
        if let v = value { sqlite3_bind_double(stmt, idx, v) }
        else { sqlite3_bind_null(stmt, idx) }
    }
}

// MARK: - Schema Migrations

struct SchemaMigration {
    let version: Int
    let description: String
    let sql: [String]

    func apply(db: OpaquePointer?, queue: DispatchQueue) throws {
        for statement in sql {
            var errMsg: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(db, statement, nil, nil, &errMsg) == SQLITE_OK else {
                let err = String(cString: errMsg!)
                sqlite3_free(errMsg)
                throw StorageError.migrationFailed("v\(version): \(err)")
            }
        }
    }
}

enum SchemaMigrations {
    static let all: [SchemaMigration] = [
        SchemaMigration(version: 1, description: "Initial schema", sql: [
            """
            CREATE TABLE IF NOT EXISTS entries (
                id TEXT PRIMARY KEY, timestamp REAL NOT NULL, timezone_offset INTEGER NOT NULL DEFAULT 0,
                duration_ms INTEGER NOT NULL, audio_format TEXT NOT NULL DEFAULT 'aac',
                audio_encrypted INTEGER NOT NULL DEFAULT 1, audio_file_size INTEGER,
                transcript TEXT, transcript_status TEXT NOT NULL DEFAULT 'pending',
                transcript_error TEXT, transcript_ms INTEGER,
                biomarkers_json TEXT, biomarkers_status TEXT NOT NULL DEFAULT 'pending',
                biomarkers_error TEXT,
                emotion_json TEXT, emotion_status TEXT NOT NULL DEFAULT 'pending',
                emotion_error TEXT,
                topics_json TEXT, topics_status TEXT NOT NULL DEFAULT 'pending', topics_error TEXT,
                app_version TEXT NOT NULL, device_model TEXT, os_version TEXT,
                created_at REAL NOT NULL, updated_at REAL NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_entries_timestamp ON entries(timestamp DESC)",
            "CREATE INDEX IF NOT EXISTS idx_entries_status ON entries(transcript_status)",
            """
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS patterns (
                id TEXT PRIMARY KEY, pattern_type TEXT NOT NULL, severity INTEGER NOT NULL,
                title TEXT NOT NULL, message TEXT NOT NULL, data_json TEXT,
                first_detected REAL NOT NULL, last_detected REAL NOT NULL,
                occurrence_count INTEGER DEFAULT 1, dismissed INTEGER DEFAULT 0,
                created_at REAL NOT NULL, updated_at REAL NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_patterns_type ON patterns(pattern_type)",
            "CREATE INDEX IF NOT EXISTS idx_patterns_severity ON patterns(severity DESC)",
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY, description TEXT NOT NULL, applied_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS subscription (
                id INTEGER PRIMARY KEY CHECK (id = 1), status TEXT NOT NULL DEFAULT 'free',
                plan_type TEXT, original_id TEXT, current_id TEXT, expires_at REAL,
                auto_renew INTEGER DEFAULT 1, trial_start REAL, trial_end REAL, updated_at REAL NOT NULL
            )
            """,
            "INSERT OR IGNORE INTO subscription (id, status) VALUES (1, 'free')"
        ]),

        SchemaMigration(version: 2, description: "Goals table", sql: [
            """
            CREATE TABLE IF NOT EXISTS goals (
                id TEXT PRIMARY KEY, goal_text TEXT NOT NULL, original_entry TEXT NOT NULL REFERENCES entries(id),
                status TEXT NOT NULL DEFAULT 'active', first_mentioned REAL NOT NULL,
                last_mentioned REAL, mention_count INTEGER DEFAULT 1,
                completion_date REAL, abandonment_date REAL,
                created_at REAL NOT NULL, updated_at REAL NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_goals_status ON goals(status)"
        ]),

        SchemaMigration(version: 3, description: "User baselines", sql: [
            """
            CREATE TABLE IF NOT EXISTS user_baselines (
                metric TEXT PRIMARY KEY, mean REAL NOT NULL, stddev REAL NOT NULL,
                min REAL, max REAL, p5 REAL, p25 REAL, p75 REAL, p95 REAL,
                sample_count INTEGER NOT NULL DEFAULT 0, last_updated REAL NOT NULL
            )
            """
        ]),

        SchemaMigration(version: 6, description: "Predictions + baselines cache", sql: [
            """
            CREATE TABLE IF NOT EXISTS predictions_cache (
                id TEXT PRIMARY KEY, type TEXT NOT NULL, prediction TEXT NOT NULL,
                probability REAL NOT NULL, confidence TEXT NOT NULL,
                based_on_json TEXT, valid_until REAL NOT NULL, created_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS baseline_cache (
                metric TEXT PRIMARY KEY, mean REAL NOT NULL, stddev REAL NOT NULL,
                min REAL, max REAL, p5 REAL, p25 REAL, p75 REAL, p95 REAL,
                sample_count INTEGER NOT NULL, stability_score REAL,
                is_mature INTEGER DEFAULT 0, daily_patterns_json TEXT,
                last_updated REAL NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_predictions_type ON predictions_cache(type)"
        ]),

        SchemaMigration(version: 5, description: "Decisions table", sql: [
            """
            CREATE TABLE IF NOT EXISTS decisions (
                id TEXT PRIMARY KEY, entry_id TEXT NOT NULL REFERENCES entries(id),
                decision_text TEXT NOT NULL, category TEXT, expected_outcome TEXT,
                status TEXT NOT NULL DEFAULT 'active',
                follow_up_entry_id TEXT, follow_up_sentiment REAL, follow_up_text TEXT,
                first_mentioned REAL NOT NULL, last_mentioned REAL NOT NULL,
                mention_count INTEGER DEFAULT 1, created_at REAL NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_decisions_status ON decisions(status)",
            "CREATE INDEX IF NOT EXISTS idx_decisions_entry ON decisions(entry_id)"
        ]),

        SchemaMigration(version: 4, description: "Debug logs", sql: [
            """
            CREATE TABLE IF NOT EXISTS debug_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT, level TEXT NOT NULL DEFAULT 'info',
                component TEXT, message TEXT NOT NULL, details_json TEXT,
                app_version TEXT, device_model TEXT, os_version TEXT, created_at REAL NOT NULL
            )
            """
        ]),
    ]
}

// MARK: - Errors

enum StorageError: Error, LocalizedError {
    case couldNotOpen(String)
    case prepareFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .couldNotOpen(let msg): return "Could not open database: \(msg)"
        case .prepareFailed(let msg): return "Query prepare failed: \(msg)"
        case .writeFailed(let msg): return "Write failed: \(msg)"
        case .readFailed(let msg): return "Read failed: \(msg)"
        case .migrationFailed(let msg): return "Migration failed: \(msg)"
        }
    }
}
