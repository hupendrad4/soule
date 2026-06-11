import Foundation
import CloudKit

final class BackupService: Sendable {
    static let shared = BackupService()

    private let container: CKContainer
    private let database: CKDatabase
    private let defaults = UserDefaults.standard

    private init() {
        container = CKContainer(identifier: "iCloud.com.soulo.app")
        database = container.privateCloudDatabase
    }

    // MARK: - Perform Backup

    func performBackup(password: String) async throws -> BackupMetadata {
        let entries = try StorageService.shared.loadEntries()
        let patterns = try StorageService.shared.loadPatterns(activeOnly: false)
        let decisions = try StorageService.shared.loadDecisions(activeOnly: false)

        let backupData = BackupDataV2(
            version: 2,
            createdAt: Date().timeIntervalSince1970,
            entries: entries,
            patterns: patterns,
            decisions: decisions,
            baselinesJson: nil
        )

        let json = try JSONEncoder().encode(backupData)
        let encrypted = try EncryptionService.shared.encryptBackup(json, passphrase: password)
        let tempURL = FileManager.default.temporaryDirectory.appending(path: "soulo_backup.enc")
        try encrypted.write(to: tempURL)

        let record = CKRecord(recordType: "SouloBackup")
        record["version"] = 2
        record["createdAt"] = Date().timeIntervalSince1970
        record["entryCount"] = entries.count
        record["fileSize"] = encrypted.count
        record["file"] = CKAsset(fileURL: tempURL)

        try await database.save(record)
        try FileManager.default.removeItem(at: tempURL)

        defaults.set(Date().timeIntervalSince1970, forKey: "last_backup_date")

        let metadata = BackupMetadata(
            date: Date().timeIntervalSince1970,
            entryCount: entries.count,
            patternCount: patterns.count,
            decisionCount: decisions.count,
            fileSize: encrypted.count,
            version: 2
        )

        Logger.shared.info("Backup", "Backup completed (\(entries.count) entries)")
        return metadata
    }

    // MARK: - Restore

    func restoreFromBackup(password: String) async throws -> RestoreResult {
        let query = CKQuery(recordType: "SouloBackup", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        query.resultsLimit = 1

        let result = try await database.records(matching: query)
        guard let record = result.matchResults.first?.1 else {
            throw BackupError.noBackupFound
        }

        let asset = try record.get().object(forKey: "file") as! CKAsset
        guard let fileURL = asset.fileURL else { throw BackupError.corruptedBackup }

        let encryptedData = try Data(contentsOf: fileURL)
        let decrypted = try EncryptionService.shared.decryptBackup(encryptedData, passphrase: password)

        if let backupV2 = try? JSONDecoder().decode(BackupDataV2.self, from: decrypted) {
            for entry in backupV2.entries {
                try StorageService.shared.saveEntry(entry)
            }
            try StorageService.shared.savePatterns(backupV2.patterns)
            if !backupV2.decisions.isEmpty {
                try StorageService.shared.saveDecisions(backupV2.decisions)
            }
            Logger.shared.info("Backup", "Restored v2: \(backupV2.entries.count) entries")
            return RestoreResult(
                entriesRestored: backupV2.entries.count,
                patternsRestored: backupV2.patterns.count,
                decisionsRestored: backupV2.decisions.count,
                backupDate: backupV2.createdAt
            )
        }

        // Fallback to v1
        let backupV1 = try JSONDecoder().decode(BackupData.self, from: decrypted)
        for entry in backupV1.entries {
            try StorageService.shared.saveEntry(entry)
        }
        try StorageService.shared.savePatterns(backupV1.patterns)
        Logger.shared.info("Backup", "Restored v1: \(backupV1.entries.count) entries")
        return RestoreResult(
            entriesRestored: backupV1.entries.count,
            patternsRestored: backupV1.patterns.count,
            decisionsRestored: 0,
            backupDate: backupV1.createdAt
        )
    }

    // MARK: - List Backups

    func listBackups() async throws -> [BackupMetadata] {
        let query = CKQuery(recordType: "SouloBackup", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        query.resultsLimit = 20

        let result = try await database.records(matching: query, desiredKeys: [
            "createdAt", "version", "entryCount", "fileSize"
        ])

        return try result.matchResults.compactMap { try? $0.1.get() }.map { record in
            BackupMetadata(
                date: record.object(forKey: "createdAt") as? TimeInterval ?? 0,
                entryCount: record.object(forKey: "entryCount") as? Int ?? 0,
                patternCount: 0,
                decisionCount: 0,
                fileSize: record.object(forKey: "fileSize") as? Int ?? 0,
                version: record.object(forKey: "version") as? Int ?? 1
            )
        }
    }

    // MARK: - Auto-Backup Scheduling

    func scheduleAutoBackup(password: String) {
        let interval = defaults.double(forKey: "auto_backup_interval")
        let frequency = interval > 0 ? interval : 86400 * 7

        Task {
            let lastBackup = defaults.double(forKey: "last_backup_date")
            let now = Date().timeIntervalSince1970
            guard now - lastBackup >= frequency else { return }
            do {
                _ = try await performBackup(password: password)
            } catch {
                Logger.shared.error("Backup", "Auto-backup failed: \(error.localizedDescription)")
            }
        }
    }

    func setAutoBackupInterval(days: Int) {
        defaults.set(Double(days * 86400), forKey: "auto_backup_interval")
    }
}

// MARK: - Models

struct BackupMetadata: Codable, Sendable {
    let date: TimeInterval
    let entryCount: Int
    let patternCount: Int
    let decisionCount: Int
    let fileSize: Int
    let version: Int

    var formattedSize: String {
        if fileSize < 1024 { return "\(fileSize) B" }
        if fileSize < 1024 * 1024 { return "\(fileSize / 1024) KB" }
        return String(format: "%.1f MB", Double(fileSize) / (1024 * 1024))
    }
}

struct RestoreResult: Codable, Sendable {
    let entriesRestored: Int
    let patternsRestored: Int
    let decisionsRestored: Int
    let backupDate: TimeInterval
}

struct BackupDataV2: Codable {
    let version: Int
    let createdAt: TimeInterval
    let entries: [JournalEntry]
    let patterns: [DetectedPattern]
    let decisions: [JournalDecision]
    let baselinesJson: String?
}

struct BackupData: Codable {
    let version: Int
    let createdAt: TimeInterval
    let entries: [JournalEntry]
    let patterns: [DetectedPattern]
}

enum BackupError: Error, LocalizedError {
    case noBackupFound
    case corruptedBackup
    case cloudKitError(String)

    var errorDescription: String? {
        switch self {
        case .noBackupFound: return "No backup found in iCloud"
        case .corruptedBackup: return "Backup file is corrupted"
        case .cloudKitError(let msg): return "iCloud error: \(msg)"
        }
    }
}
