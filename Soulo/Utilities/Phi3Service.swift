import Foundation
import ONNXRuntime

final class Phi3Service: Sendable {
    static let shared = Phi3Service()

    private let queue = DispatchQueue(label: "com.soulo.phi3", qos: .userInitiated)
    private var session: ORTSession?
    private var env: ORTEnv!

    private init() {
        do {
            env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        } catch {
            Logger.shared.error("Phi3", "Failed to create ORTEnv: \(error.localizedDescription)")
        }
        loadModel()
    }

    private func loadModel() {
        guard let path = findModel(), let env else { return }
        let opts = try? ORTSessionOptions()
        opts?.setIntraOpNumThreadsOverride(ProcessInfo.processInfo.activeProcessorCount)
        session = try? ORTSession(env: env, modelPath: path, sessionOptions: opts)
    }

    private func findModel() -> String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let docPath = docs.appending(path: "models/phi-3-mini-q4.onnx").path
        if FileManager.default.fileExists(atPath: docPath) { return docPath }
        if let p = Bundle.main.path(forResource: "phi-3-mini-q4", ofType: "onnx") { return p }
        return nil
    }

    var isAvailable: Bool { session != nil }

    // MARK: - Public API

    func extractTopics(from transcript: String) async throws -> [LLMTopicResult] {
        guard let session else { throw Phi3Error.modelNotAvailable }
        let prompt = makePrompt(system: topicSystemPrompt, user: transcript)
        return try await run(session: session, prompt: prompt, maxTokens: 256)
    }

    func classifySentiment(topic: String, in transcript: String) async throws -> Double {
        guard let session else { throw Phi3Error.modelNotAvailable }
        let prompt = makePrompt(
            system: "Rate the sentiment about \"\(topic)\" from -1.0 to 1.0. Return ONLY a number.",
            user: transcript
        )
        let result: [DoubleResult] = try await run(session: session, prompt: prompt, maxTokens: 16)
        return result.first?.value ?? 0
    }

    func extractEntities(from transcript: String) async throws -> [ExtractedEntity] {
        guard let session else { throw Phi3Error.modelNotAvailable }
        let prompt = makePrompt(
            system: "Extract people, places, organizations as JSON: [{\"name\":\"...\",\"type\":\"person|place|org\"}]",
            user: transcript
        )
        let entities: [ExtractedEntity] = try await run(session: session, prompt: prompt, maxTokens: 128)
        return entities
    }

    // MARK: - Prompt Template

    private let topicSystemPrompt = """
    Extract main topics from this journal entry. For each return:
    {"topic": "short name", "sentiment": -1.0 to 1.0, "entities": ["person", "place"]}
    Return ONLY valid JSON array.
    """

    private func makePrompt(system: String, user: String) -> String {
        """
        <|system|>
        \(system)
        <|end|>
        <|user|>
        \(user)
        <|end|>
        <|assistant|>
        """
    }

    // MARK: - Inference

    private func run<T: Decodable & Sendable>(session: ORTSession, prompt: String, maxTokens: Int) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let tokens = try self.tokenize(prompt)
                    let outputTokens = try self.generate(session: session, inputTokens: tokens, maxTokens: maxTokens)
                    let text = self.detokenize(outputTokens)
                    let result: T = try self.parseJSON(text)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func tokenize(_ text: String) throws -> [Int64] {
        guard let path = Bundle.main.path(forResource: "phi3_tokenizer", ofType: "json") else {
            throw Phi3Error.tokenizerNotFound
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let tokenizer = try JSONDecoder().decode(Phi3TokenizerConfig.self, from: data)
        return BPEEncoder.encode(text: text, config: tokenizer)
    }

    private func detokenize(_ tokens: [Int64]) -> String {
        guard let path = Bundle.main.path(forResource: "phi3_tokenizer", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let config = try? JSONDecoder().decode(Phi3TokenizerConfig.self, from: data) else {
            return tokens.map { String(UnicodeScalar(UInt32($0)) ?? " ") }.joined()
        }
        return BPEEncoder.decode(tokens: tokens, config: config)
    }

    private func generate(session: ORTSession, inputTokens: [Int64], maxTokens: Int) throws -> [Int64] {
        var tokens = inputTokens
        let eosToken: Int64 = 2

        for _ in 0..<maxTokens {
            guard let nextId = try nextToken(session: session, tokens: tokens) else { break }
            tokens.append(nextId)
            if nextId == eosToken { break }
        }
        return Array(tokens.dropFirst(inputTokens.count))
    }

    private func nextToken(session: ORTSession, tokens: [Int64]) throws -> Int64? {
        let shape: [NSNumber] = [1, NSNumber(value: tokens.count)]
        var tokenData = Data(bytes: tokens, count: tokens.count * MemoryLayout<Int64>.stride)
        let inputTensor = try ORTValue(
            tensorData: NSMutableData(data: tokenData),
            elementType: .int64,
            shape: shape
        )
        let outputs = try session.run(withInputs: ["input_ids": inputTensor], outputNames: ["logits"], runOptions: nil)

        guard let logitsTensor = outputs["logits"] else { return nil }
        let data = try logitsTensor.tensorData() as Data
        let logits = data.withUnsafeBytes { buf -> [Float] in
            let count = buf.count / MemoryLayout<Float>.stride
            return Array(UnsafeBufferPointer<Float>(start: buf.baseAddress!.assumingMemoryBound(to: Float.self), count: count))
        }
        let vocabSize = 32064
        let last = Array(logits.suffix(vocabSize))
        return Int64(last.enumerated().max { $0.element < $1.element }?.offset ?? 0)
    }

    private func parseJSON<T: Decodable>(_ text: String) throws -> T {
        guard let json = extractJSON(text) else { throw Phi3Error.parseFailed }
        return try JSONDecoder().decode(T.self, from: json.data(using: .utf8)!)
    }

    private func extractJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]") {
            return String(trimmed[start...end])
        }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return trimmed
    }

    func reload() {
        session = nil
        loadModel()
    }
}

// MARK: - BPE Tokenizer

struct Phi3TokenizerConfig: Codable {
    let model: TokenizerModel
    let addedTokens: [AddedToken]?
    let preTokenizer: String?

    struct TokenizerModel: Codable {
        let type: String
        let vocab: [String: Int]
        let merges: [String]
    }

    struct AddedToken: Codable {
        let id: Int
        let content: String
        let singleWord: Bool?
    }
}

enum BPEEncoder {
    static func encode(text: String, config: Phi3TokenizerConfig) -> [Int64] {
        let vocab = config.model.vocab
        let words = text.lowercased().split(separator: " ").map(String.init)
        var ids: [Int64] = []

        for word in words {
            let wordWithSpace = " " + word
            if let id = vocab[wordWithSpace] {
                ids.append(Int64(id))
                continue
            }
            let chars = wordWithSpace.map { String($0) }
            var bestSegmentation = chars
            var improved = true

            while improved {
                improved = false
                var bestPair: (String, String, String)?
                var bestPairScore = Int.max

                for i in 0..<bestSegmentation.count - 1 {
                    let pair = bestSegmentation[i] + bestSegmentation[i + 1]
                    if let idx = config.model.merges.firstIndex(of: pair), idx < bestPairScore {
                        bestPairScore = idx
                        bestPair = (bestSegmentation[i], bestSegmentation[i + 1], pair)
                    }
                }

                if let (first, second, merged) = bestPair {
                    var newSegments: [String] = []
                    var i = 0
                    while i < bestSegmentation.count {
                        if i < bestSegmentation.count - 1 && bestSegmentation[i] == first && bestSegmentation[i + 1] == second {
                            newSegments.append(merged)
                            i += 2
                        } else {
                            newSegments.append(bestSegmentation[i])
                            i += 1
                        }
                    }
                    bestSegmentation = newSegments
                    improved = true
                }
            }

            for segment in bestSegmentation {
                if let id = vocab[segment] {
                    ids.append(Int64(id))
                }
            }
        }

        return ids
    }

    static func decode(tokens: [Int64], config: Phi3TokenizerConfig) -> String {
        let idToToken = Dictionary(uniqueKeysWithValues: config.model.vocab.map { ($1, $0) })
        var text = ""
        for token in tokens {
            if let word = idToToken[Int(token)] {
                text += word
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Models

struct LLMTopicResult: Codable, Sendable {
    let topic: String
    let sentiment: Double
    let entities: [String]?
}

struct ExtractedEntity: Codable, Sendable, Identifiable {
    let id = UUID()
    let name: String
    let type: String
}

struct DoubleResult: Codable {
    let value: Double
}

enum Phi3Error: LocalizedError {
    case modelNotAvailable
    case tokenizerNotFound
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable: return "Phi-3-mini model not downloaded. Requires Wi-Fi."
        case .tokenizerNotFound: return "Tokenizer file missing. Reinstall app."
        case .parseFailed: return "Could not parse model output."
        }
    }
}
