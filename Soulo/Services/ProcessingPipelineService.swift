import Foundation

final class ProcessingPipelineService: Sendable {
    static let shared = ProcessingPipelineService()

    private init() {}

    enum PipelineStage: String, Sendable {
        case recording, transcribing, biomarkers, emotion, topics, patterns, decisions, saving, complete, failed
    }

    struct PipelineResult: Sendable {
        let entry: JournalEntry
        let patterns: [DetectedPattern]
        let decisions: [JournalDecision]
        let failedStages: [PipelineStage]
    }

    // MARK: - Full Pipeline

    func processRecording(audioURL: URL, duration: TimeInterval) async -> PipelineResult {
        var entry = JournalEntry(
            id: UUID().uuidString,
            durationMs: Int(duration * 1000),
            audioEncrypted: true
        )
        var patterns: [DetectedPattern] = []
        var decisions: [JournalDecision] = []
        var failedStages: [PipelineStage] = []

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            return PipelineResult(entry: entry, patterns: [], decisions: [], failedStages: [.transcribing, .biomarkers, .emotion, .topics, .patterns, .decisions, .failed])
        }

        // Stage 1: Transcribe
        let transcript = await transcribeStage(audioData: audioData)
        entry.transcript = transcript.text
        entry.transcriptStatus = transcript.success ? .done : .failed
        entry.transcriptMs = transcript.durationMs
        if !transcript.success { failedStages.append(.transcribing) }

        // Stage 2: Biomarkers
        let biomarkers = await biomarkerStage(audioData: audioData)
        entry.biomarkers = biomarkers.value
        entry.biomarkersStatus = biomarkers.success ? .done : .failed
        if !biomarkers.success { failedStages.append(.biomarkers) }

        // Stage 3: Emotion (ML first, heuristic fallback)
        let emotion = await emotionStage(audioData: audioData, biomarkers: biomarkers.value)
        entry.emotion = emotion.value
        entry.emotionStatus = emotion.success ? .done : .failed
        if !emotion.success { failedStages.append(.emotion) }

        // Stage 4: Topics
        let text = transcript.text ?? ""
        if !text.isEmpty {
            let topicResult = await topicStage(transcript: text, entryId: entry.id)
            entry.topics = topicResult.value
            entry.topicsStatus = topicResult.success ? .done : .failed
            if !topicResult.success { failedStages.append(.topics) }

            // Stage 5: Patterns (needs topics + biomarkers)
            patterns = await patternStage(entries: [entry])
        } else {
            entry.topicsStatus = .pending
        }

        // Stage 6: Decisions
        if !text.isEmpty {
            decisions = await decisionStage(transcript: text, entryId: entry.id)
        }

        // Stage 7: Encrypt audio
        do {
            let encryptedURL = try await EncryptionService.shared.encryptAudio(at: audioURL, entryId: entry.id)
            entry.audioFileSize = (try? FileManager.default.attributesOfItem(atPath: encryptedURL.path))?[.size] as? Int
        } catch {
            failedStages.append(.saving)
        }

        // Stage 8: Save
        do {
            try StorageService.shared.saveEntry(entry)
        } catch {
            failedStages.append(.saving)
        }

        // Clean up raw audio
        try? FileManager.default.removeItem(at: audioURL)

        return PipelineResult(
            entry: entry,
            patterns: patterns,
            decisions: decisions,
            failedStages: failedStages
        )
    }

    // MARK: - Individual Stages

    private func transcribeStage(audioData: Data) async -> (text: String?, durationMs: Int?, success: Bool) {
        guard TranscriptionService.shared.isReady else {
            return (nil, nil, false)
        }
        do {
            let result = try await TranscriptionService.shared.transcribe(audioData: audioData)
            return (result.text, result.durationMs, true)
        } catch {
            Logger.shared.error("Pipeline", "Transcription failed: \(error.localizedDescription)")
            return (nil, nil, false)
        }
    }

    private func biomarkerStage(audioData: Data) async -> (value: VoiceBiomarkers?, success: Bool) {
        do {
            let biomarkers = try await BiomarkerService.shared.extractBiomarkers(from: audioData)
            return (biomarkers, true)
        } catch {
            Logger.shared.error("Pipeline", "Biomarker extraction failed: \(error.localizedDescription)")
            return (nil, false)
        }
    }

    private func emotionStage(audioData: Data, biomarkers: VoiceBiomarkers?) async -> (value: EmotionalState?, success: Bool) {
        if EmotionDetectionService.shared.isModelAvailable {
            do {
                let emotion = try await EmotionDetectionService.shared.detectEmotion(from: audioData)
                return (emotion, true)
            } catch {
                Logger.shared.error("Pipeline", "ML emotion failed, using heuristic: \(error.localizedDescription)")
            }
        }
        if let bio = biomarkers {
            let heuristic = EmotionDetectionService.shared.detectEmotionHeuristic(from: bio)
            return (heuristic, false)
        }
        return (EmotionalState(primaryEmotion: .neutral, confidence: 0, valence: 0, arousal: 0), false)
    }

    private func topicStage(transcript: String, entryId: String) async -> (value: [TopicAnalysis]?, success: Bool) {
        do {
            let topics = try await TopicAnalysisService.shared.analyzeTopics(transcript: transcript, entryId: entryId)
            return (topics, true)
        } catch {
            Logger.shared.error("Pipeline", "Topic analysis failed: \(error.localizedDescription)")
            return (nil, false)
        }
    }

    private func patternStage(entries: [JournalEntry]) async -> [DetectedPattern] {
        do {
            return try await PatternDetectionService().detectPatterns(in: entries)
        } catch {
            Logger.shared.error("Pipeline", "Pattern detection failed: \(error.localizedDescription)")
            return []
        }
    }

    private func decisionStage(transcript: String, entryId: String) async -> [JournalDecision] {
        let dummyEntry = JournalEntry(durationMs: 0, audioEncrypted: false)
        // We clone with the real transcript for decision scanning
        var e = dummyEntry
        e.transcript = transcript
        e.id = entryId

        var decisions = DecisionOutcomeService.shared.scanDecisions(in: [e])
        // Load existing decisions for follow-up detection
        if let existing = try? StorageService.shared.loadDecisions() {
            decisions = DecisionOutcomeService.shared.scanDecisions(in: [e], existingDecisions: existing)
            var mutable = decisions
            _ = DecisionOutcomeService.shared.detectFollowUps(in: [e], decisions: &mutable)
            decisions = mutable
        }
        try? StorageService.shared.saveDecisions(decisions)
        return decisions
    }

    // MARK: - Quick Entry Pipeline (text only)

    func processQuickEntry(text: String) async -> PipelineResult {
        var entry = JournalEntry(durationMs: 0, audioEncrypted: false)
        entry.transcript = text
        entry.transcriptStatus = .done
        var failedStages: [PipelineStage] = []

        let topics = await topicStage(transcript: text, entryId: entry.id)
        entry.topics = topics.value
        entry.topicsStatus = topics.success ? .done : .failed
        if !topics.success { failedStages.append(.topics) }

        let patterns = await patternStage(entries: [entry])
        let decisions = await decisionStage(transcript: text, entryId: entry.id)

        do {
            try StorageService.shared.saveEntry(entry)
        } catch {
            failedStages.append(.saving)
        }

        return PipelineResult(
            entry: entry,
            patterns: patterns,
            decisions: decisions,
            failedStages: failedStages
        )
    }

    // MARK: - Retry

    func retryFailedPipeline(for entry: JournalEntry, audioData: Data?) async -> PipelineResult {
        var mutableEntry = entry
        var failedStages: [PipelineStage] = []

        if mutableEntry.transcriptStatus == .failed, let data = audioData {
            let transcript = await transcribeStage(audioData: data)
            mutableEntry.transcript = transcript.text
            mutableEntry.transcriptStatus = transcript.success ? .done : .failed
            if !transcript.success { failedStages.append(.transcribing) }
        }

        if mutableEntry.biomarkersStatus == .failed, let data = audioData {
            let biomarkers = await biomarkerStage(audioData: data)
            mutableEntry.biomarkers = biomarkers.value
            mutableEntry.biomarkersStatus = biomarkers.success ? .done : .failed
            if !biomarkers.success { failedStages.append(.biomarkers) }
        }

        if mutableEntry.emotionStatus == .failed || mutableEntry.emotion == nil {
            if let data = audioData {
                let emotion = await emotionStage(audioData: data, biomarkers: mutableEntry.biomarkers)
                mutableEntry.emotion = emotion.value
                mutableEntry.emotionStatus = emotion.success ? .done : .failed
                if !emotion.success { failedStages.append(.emotion) }
            } else if let bio = mutableEntry.biomarkers {
                let heuristic = EmotionDetectionService.shared.detectEmotionHeuristic(from: bio)
                mutableEntry.emotion = heuristic
                mutableEntry.emotionStatus = .done
            }
        }

        if mutableEntry.topicsStatus == .failed, let text = mutableEntry.transcript, !text.isEmpty {
            let topics = await topicStage(transcript: text, entryId: mutableEntry.id)
            mutableEntry.topics = topics.value
            mutableEntry.topicsStatus = topics.success ? .done : .failed
            if !topics.success { failedStages.append(.topics) }
        }

        try? StorageService.shared.saveEntry(mutableEntry)

        return PipelineResult(
            entry: mutableEntry,
            patterns: [],
            decisions: [],
            failedStages: failedStages
        )
    }
}
