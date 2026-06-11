import Foundation

final class ErrorRecoveryService: Sendable {
    static let shared = ErrorRecoveryService()

    private init() {}

    // MARK: - Failed Entry Recovery

    struct RecoveryResult: Sendable {
        let recovered: Int
        let stillFailed: Int
        let errors: [String]
    }

    func recoverFailedEntries() async -> RecoveryResult {
        guard let allEntries = try? StorageService.shared.loadEntries() else {
            return RecoveryResult(recovered: 0, stillFailed: 0, errors: ["Could not load entries"])
        }

        let failed = allEntries.filter { entry in
            entry.transcriptStatus == .failed ||
            entry.biomarkersStatus == .failed ||
            entry.emotionStatus == .failed ||
            entry.topicsStatus == .failed
        }

        guard !failed.isEmpty else {
            return RecoveryResult(recovered: 0, stillFailed: 0, errors: [])
        }

        var recovered = 0
        var errors: [String] = []

        for entry in failed {
            let audioData = try? loadAudioData(for: entry.id)
            let result = await ProcessingPipelineService.shared.retryFailedPipeline(for: entry, audioData: audioData)
            if result.failedStages.isEmpty {
                recovered += 1
            } else {
                errors.append("Entry \(entry.id.prefix(8)): failed stages \(result.failedStages.map { $0.rawValue })")
            }
        }

        return RecoveryResult(
            recovered: recovered,
            stillFailed: failed.count - recovered,
            errors: errors
        )
    }

    private func loadAudioData(for entryId: String) -> Data? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let encryptedURL = docs.appending(path: "audio_encrypted/\(entryId).enc")
        guard FileManager.default.fileExists(atPath: encryptedURL.path) else { return nil }
        return try? EncryptionService.shared.decryptAudio(at: encryptedURL)
    }

    // MARK: - Stuck Processing Recovery

    func recoverStuckProcessing() async -> Int {
        guard let allEntries = try? StorageService.shared.loadEntries() else { return 0 }

        let stuck = allEntries.filter { $0.transcriptStatus == .processing || $0.biomarkersStatus == .processing }
        guard !stuck.isEmpty else { return 0 }

        for var entry in stuck {
            if entry.transcriptStatus == .processing {
                entry.transcriptStatus = .failed
                entry.transcriptError = "Processing timed out"
            }
            if entry.biomarkersStatus == .processing {
                entry.biomarkersStatus = .failed
                entry.biomarkersError = "Processing timed out"
            }
            try? StorageService.shared.saveEntry(entry)
        }

        return stuck.count
    }

    // MARK: - Database Integrity

    func checkDatabaseIntegrity() -> Bool {
        StorageService.shared.runIntegrityCheck()
    }

    func rebuildIndexes() {
        try? StorageService.shared.reindexTimestamps()
    }

    // MARK: - Model Recovery

    func verifyModels() -> (missing: [String], corrupted: [String]) {
        var missing: [String] = []
        var corrupted: [String] = []

        for model in ModelDownloadService.Model.allCases {
            let path = ModelDownloadService.shared.modelPath(model)
            guard FileManager.default.fileExists(atPath: path) else {
                missing.append(model.rawValue)
                continue
            }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? Int64,
                  size > model.expectedSize / 2 else {
                corrupted.append(model.rawValue)
                continue
            }
        }

        return (missing, corrupted)
    }
}
