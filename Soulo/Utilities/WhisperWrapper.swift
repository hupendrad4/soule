import Foundation
import Whisper

final class WhisperWrapper: Sendable {
    static let shared = WhisperWrapper()

    private let queue = DispatchQueue(label: "com.soulo.whisper", qos: .userInitiated)
    private var whisper: Whisper?

    private init() {
        loadModel()
    }

    private func loadModel() {
        guard let path = findModel() else { return }
        whisper = try? Whisper(modelPath: path)
    }

    private func findModel() -> String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let docPath = docs.appending(path: "models/ggml-tiny.en.bin").path
        if FileManager.default.fileExists(atPath: docPath) { return docPath }

        if let bundlePath = Bundle.main.path(forResource: "ggml-tiny.en", ofType: "bin") { return bundlePath }

        if let resourcePath = Bundle.main.resourcePath {
            let altPath = "\(resourcePath)/Models/ggml-tiny.en.bin"
            if FileManager.default.fileExists(atPath: altPath) { return altPath }
        }

        return nil
    }

    var isModelAvailable: Bool { whisper != nil }

    func transcribe(samples: [Float]) async throws -> TranscriptionResult {
        guard let whisper else { throw WhisperError.modelNotFound }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let params = self.defaultParams()
                    let result = try whisper.transcribe(samples: samples, params: params)
                    let segments = result.segments.map {
                        TranscriptionSegment(text: $0.text, startMs: Int($0.startTime * 1000), endMs: Int($0.endTime * 1000))
                    }
                    continuation.resume(returning: TranscriptionResult(
                        text: result.text,
                        segments: segments,
                        inferenceMs: Int(result.inferenceTime * 1000),
                        segmentCount: segments.count
                    ))
                } catch {
                    continuation.resume(throwing: WhisperError.transcriptionFailed)
                }
            }
        }
    }

    private func defaultParams() -> WhisperParams {
        var params = WhisperParams()
        params.language = "en"
        params.maxSegmentLength = 100
        params.suppressBlank = true
        params.suppressNonSpeech = true
        params.useGPU = true
        return params
    }

    func reloadModel() {
        whisper = nil
        loadModel()
    }
}

struct TranscriptionResult: Sendable {
    let text: String
    let segments: [TranscriptionSegment]
    let inferenceMs: Int
    let segmentCount: Int
}

struct TranscriptionSegment: Sendable {
    let text: String
    let startMs: Int
    let endMs: Int
}

enum WhisperError: LocalizedError {
    case modelNotFound
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "Whisper model not found. Download it first."
        case .transcriptionFailed: return "Transcription failed. Try again."
        }
    }
}
