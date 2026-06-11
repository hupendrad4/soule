import Foundation
import AVFoundation

final class TranscriptionService: Sendable {
    static let shared = TranscriptionService()

    private init() {}

    var isReady: Bool { WhisperWrapper.shared.isModelAvailable }

    func transcribe(audioData: Data) async throws -> TranscriptionResult {
        guard WhisperWrapper.shared.isModelAvailable else {
            throw TranscriptionError.modelNotDownloaded
        }

        let samples = audioData.withUnsafeBytes { buf -> [Float] in
            let count = buf.count / MemoryLayout<Float>.size
            guard count > 0 else { return [] }
            return Array(UnsafeBufferPointer<Float>(
                start: buf.baseAddress!.assumingMemoryBound(to: Float.self),
                count: count
            ))
        }

        guard !samples.isEmpty else { throw TranscriptionError.emptyResult }

        return try await WhisperWrapper.shared.transcribe(samples: samples)
    }

    func transcribe(audioFileURL: URL) async throws -> TranscriptionResult {
        let audioData = try Data(contentsOf: audioFileURL)
        return try await transcribe(audioData: audioData)
    }

    func transcribeEncrypted(audioFileURL: URL) async throws -> TranscriptionResult {
        let audioData = try EncryptionService.shared.decryptAudio(at: audioFileURL)
        let tempURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try await transcribe(audioFileURL: tempURL)
    }

    func loadAudioSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = UInt32(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TranscriptionError.transcriptionFailed("Could not create audio buffer")
        }
        try file.read(into: buffer)

        guard let floatData = buffer.floatChannelData else {
            throw TranscriptionError.transcriptionFailed("No float channel data")
        }
        let channelData = floatData.pointee
        return Array(UnsafeBufferPointer(start: channelData, count: Int(frameCount)))
    }

    var textOnlyEntries: [TextOnlyEntry] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "text_only_entries") else { return [] }
            return (try? JSONDecoder().decode([TextOnlyEntry].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "text_only_entries")
            }
        }
    }

    func saveTextOnly(_ text: String) {
        var entries = textOnlyEntries
        entries.append(TextOnlyEntry(
            text: text,
            createdAt: Date().timeIntervalSince1970
        ))
        textOnlyEntries = entries
    }
}

struct TextOnlyEntry: Codable, Identifiable {
    let id: String
    let text: String
    let createdAt: TimeInterval

    init(id: String = UUID().uuidString, text: String, createdAt: TimeInterval = Date().timeIntervalSince1970) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotDownloaded
    case transcriptionFailed(String)
    case emptyResult
    case audioLoadFailed

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: return "Whisper model not downloaded"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .emptyResult: return "Transcription returned empty result"
        case .audioLoadFailed: return "Could not load audio file"
        }
    }
}
