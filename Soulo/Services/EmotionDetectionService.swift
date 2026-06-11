import Foundation
import Accelerate
import ONNXRuntime

final class EmotionDetectionService: Sendable {
    static let shared = EmotionDetectionService()

    private let queue = DispatchQueue(label: "com.soulo.emotion", qos: .userInitiated)
    private var session: ORTSession?
    private var env: ORTEnv!

    private init() {
        do {
            env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        } catch {
            Logger.shared.error("Emotion", "Failed to create ORTEnv: \(error.localizedDescription)")
        }
        loadModel()
    }

    private func loadModel() {
        guard let path = findModel(), let env else { return }
        session = try? ORTSession(env: env, modelPath: path, sessionOptions: nil)
    }

    private func findModel() -> String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let docPath = docs.appending(path: "models/emotion2vec.onnx").path
        if FileManager.default.fileExists(atPath: docPath) { return docPath }
        if let p = Bundle.main.path(forResource: "emotion2vec", ofType: "onnx") { return p }
        return nil
    }

    var isModelAvailable: Bool { session != nil }

    // MARK: - ML Inference (emotion2vec)

    func detectEmotion(from audioData: Data) async throws -> EmotionalState {
        guard let session else {
            throw EmotionError.modelNotDownloaded
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let features = try self.extractFeatures(audioData)
                    let output = try self.runInference(session: session, features: features)
                    let result = self.parseOutput(output)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func extractFeatures(_ audioData: Data) throws -> [Float] {
        let samples = audioData.withUnsafeBytes { buf -> [Float] in
            let count = buf.count / MemoryLayout<Float>.stride
            guard count > 0 else { return [] }
            return Array(UnsafeBufferPointer<Float>(
                start: buf.baseAddress!.assumingMemoryBound(to: Float.self),
                count: count
            ))
        }
        guard !samples.isEmpty else { throw EmotionError.inferenceFailed("No audio data") }

        // Extract MFCC-like features: frame-level FFT magnitudes
        let frameSize = 512
        let hopSize = 256
        let numFilters = 40

        var features = [Float]()
        var start = 0
        while start + frameSize <= samples.count {
            let frame = Array(samples[start..<start + frameSize])
            // Apply Hann window
            var windowed = [Float](repeating: 0, count: frameSize)
            vDSP_vmul(frame, 1, hannWindow(frameSize), 1, &windowed, 1, vDSP_Length(frameSize))

            // FFT
            var real = windowed
            var imag = [Float](repeating: 0, count: frameSize)
            if let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(frameSize), vDSP_DFTDirection.FORWARD) {
                real.withUnsafeMutableBufferPointer { rp in
                    imag.withUnsafeMutableBufferPointer { ip in
                        vDSP_DFT_Execute(setup, rp.baseAddress!, ip.baseAddress!, rp.baseAddress!, ip.baseAddress!)
                    }
                }
                vDSP_DFT_DestroySetup(setup)
            }

            var mags = [Float](repeating: 0, count: frameSize / 2)
            vDSP_ztoc(real, 2, imag, 2, &mags, 1, vDSP_Length(frameSize / 2))

            // Mel filterbank (simplified: average into bins)
            let binSize = max(1, mags.count / numFilters)
            for i in 0..<numFilters {
                let lo = i * binSize
                let hi = min(lo + binSize, mags.count)
                let avg = lo < hi ? mags[lo..<hi].reduce(0, +) / Float(hi - lo) : 0
                features.append(log(max(avg, 1e-10)))
            }
            start += hopSize
        }

        // Pad or truncate to fixed size (80 frames × 40 filters)
        let targetFrames = 80
        let targetSize = targetFrames * numFilters
        if features.count < targetSize {
            features.append(contentsOf: repeatElement(0.0, count: targetSize - features.count))
        } else {
            features = Array(features[0..<targetSize])
        }

        return features
    }

    private func runInference(session: ORTSession, features: [Float]) throws -> [Float] {
        let shape: [NSNumber] = [1, 80, 40, 1]
        var featureData = Data(bytes: features, count: features.count * MemoryLayout<Float>.stride)
        let inputTensor = try ORTValue(
            tensorData: NSMutableData(data: featureData),
            elementType: .float,
            shape: shape
        )

        let outputs = try session.run(
            withInputs: ["input": inputTensor],
            outputNames: ["emotion_probs"],
            runOptions: nil
        )

        guard let probsTensor = outputs["emotion_probs"] else {
            throw EmotionError.inferenceFailed("No output tensor")
        }

        let data = try probsTensor.tensorData() as Data
        return data.withUnsafeBytes { buf -> [Float] in
            let count = buf.count / MemoryLayout<Float>.stride
            return Array(UnsafeBufferPointer<Float>(start: buf.baseAddress!.assumingMemoryBound(to: Float.self), count: count))
        }
    }

    // MARK: - Output Parsing

    private func parseOutput(_ probs: [Float]) -> EmotionalState {
        let emotionLabels = EmotionType.allCases
        guard !probs.isEmpty else { return heuristicFallback(biomarkers: nil) }

        let maxIdx = probs.enumerated().max { $0.element < $1.element }?.offset ?? 0
        let emotion = maxIdx < emotionLabels.count ? emotionLabels[maxIdx] : .neutral
        let confidence = maxIdx < probs.count ? Double(probs[maxIdx]) : 0

        // Valence: weighted average of emotion valences
        let valenceMap: [EmotionType: Double] = [
            .joy: 0.8, .gratitude: 0.7, .hope: 0.6, .surprise: 0.3,
            .neutral: 0.0, .sadness: -0.6, .anger: -0.7, .fear: -0.5,
            .anxiety: -0.4, .frustration: -0.5, .loneliness: -0.6, .disgust: -0.5
        ]
        let valence = zip(emotionLabels, probs).reduce(0.0) { $0 + (valenceMap[$1.0] ?? 0) * Double($1.1) }

        // Arousal: weighted average
        let arousalMap: [EmotionType: Double] = [
            .joy: 0.7, .anger: 0.8, .fear: 0.7, .anxiety: 0.7, .surprise: 0.8,
            .frustration: 0.7, .neutral: 0.3, .sadness: 0.2, .loneliness: 0.2,
            .gratitude: 0.4, .hope: 0.5, .disgust: 0.5
        ]
        let arousal = zip(emotionLabels, probs).reduce(0.0) { $0 + (arousalMap[$1.0] ?? 0.5) * Double($1.1) }

        let allProbs = Dictionary(uniqueKeysWithValues: zip(emotionLabels.map { $0.rawValue }, probs.map(Double.init)))

        return EmotionalState(
            primaryEmotion: emotion,
            confidence: min(confidence, 1.0),
            valence: max(-1, min(1, valence)),
            arousal: max(0, min(1, arousal)),
            allProbabilities: allProbs
        )
    }

    // MARK: - Heuristic Fallback

    func detectEmotionHeuristic(from biomarkers: VoiceBiomarkers) -> EmotionalState {
        return heuristicFallback(biomarkers: biomarkers)
    }

    private func heuristicFallback(biomarkers: VoiceBiomarkers?) -> EmotionalState {
        guard let b = biomarkers else {
            return EmotionalState(primaryEmotion: .neutral, confidence: 0, valence: 0, arousal: 0)
        }

        let highEnergy = b.vocalEnergy > 0.6
        let lowEnergy = b.vocalEnergy < 0.3
        let highPitch = b.pitchInstability > 0.15
        let fast = b.speechRate > 4.5
        let slow = b.speechRate < 1.5
        let breaths = b.microBreathCount > 15
        let highJitter = b.jitter > 0.08
        let hesitant = b.hesitationRate > 0.3

        let result: (emotion: EmotionType, confidence: Double, valence: Double, arousal: Double)

        if highEnergy && highPitch && fast { result = (.joy, 0.5, 0.7, 0.8) }
        else if lowEnergy && hesitant && slow { result = (.sadness, 0.45, -0.5, 0.2) }
        else if highPitch && breaths && fast { result = (.anxiety, 0.4, -0.3, 0.7) }
        else if highPitch && lowEnergy { result = (.sadness, 0.35, -0.4, 0.3) }
        else if highEnergy && highJitter { result = (.frustration, 0.35, -0.3, 0.7) }
        else if lowEnergy && breaths { result = (.fear, 0.3, -0.4, 0.6) }
        else if b.speechRate > 5.0 { result = (.surprise, 0.3, 0.3, 0.8) }
        else { result = (.neutral, 0.35, 0.0, b.vocalEnergy) }

        return EmotionalState(
            primaryEmotion: result.emotion,
            confidence: result.confidence,
            valence: result.valence,
            arousal: result.arousal
        )
    }

    // MARK: - Helpers

    private func hannWindow(_ count: Int) -> [Float] {
        var window = [Float](repeating: 0, count: count)
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        return window
    }

    func reloadModel() {
        session = nil
        loadModel()
    }
}

enum EmotionError: LocalizedError {
    case modelNotDownloaded
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: return "Emotion model not downloaded"
        case .inferenceFailed(let msg): return "Emotion inference failed: \(msg)"
        }
    }
}
