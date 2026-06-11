import Foundation
import Accelerate

final class BiomarkerService: Sendable {
    static let shared = BiomarkerService()

    private init() {}

    func extractBiomarkers(from audioData: Data) async throws -> VoiceBiomarkers {
        let samples = audioData.withUnsafeBytes { buf in
            Array(UnsafeBufferPointer<Float>(
                start: buf.baseAddress!.assumingMemoryBound(to: Float.self),
                count: buf.count / MemoryLayout<Float>.size
            ))
        }

        guard !samples.isEmpty else {
            throw BiomarkerError.noAudioData
        }

        return try await Task.detached(priority: .userInitiated) {
            AudioDSP.extractBiomarkers(from: samples)
        }.value
    }
}

enum BiomarkerError: Error, LocalizedError {
    case noAudioData
    case computationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioData: return "No audio data to analyze"
        case .computationFailed(let msg): return "Biomarker computation failed: \(msg)"
        }
    }
}
