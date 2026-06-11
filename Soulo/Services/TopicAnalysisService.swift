import Foundation
import NaturalLanguage

final class TopicAnalysisService: Sendable {
    static let shared = TopicAnalysisService()

    private init() {}

    func analyzeTopics(transcript: String, entryId: String) async throws -> [TopicAnalysis] {
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        if Phi3Service.shared.isAvailable {
            return try await llmAnalysis(transcript: transcript, entryId: entryId)
        }
        return heuristicAnalysis(transcript: transcript, entryId: entryId)
    }

    // MARK: - Phi-3-mini Analysis

    private func llmAnalysis(transcript: String, entryId: String) async throws -> [TopicAnalysis] {
        let results = try await Phi3Service.shared.extractTopics(from: transcript)
        let entities = (try? await Phi3Service.shared.extractEntities(from: transcript)) ?? []

        return results.map { result in
            TopicAnalysis(
                entryId: entryId,
                topic: result.topic.capitalized,
                sentiment: max(-1, min(1, result.sentiment)),
                energy: nil,
                keywords: result.entities ?? []
            )
        }
    }

    // MARK: - Heuristic Fallback

    private func heuristicAnalysis(transcript: String, entryId: String) -> [TopicAnalysis] {
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = transcript

        var topicCandidates: [(word: String, sentenceIdx: Int)] = []
        let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".?!"))

        for (idx, sentence) in sentences.enumerated() {
            guard !sentence.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            tagger.string = sentence
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex,
                                 unit: .word, scheme: .nameType) { tag, range in
                let word = String(sentence[range]).lowercased()
                if tag == .personalName || tag == .placeName || tag == .organizationName {
                    topicCandidates.append((word, idx))
                }
                return true
            }

            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex,
                                 unit: .word, scheme: .lexicalClass) { tag, range in
                if tag == .noun || tag == .pluralNoun {
                    let word = String(sentence[range]).lowercased()
                    if !stopWords.contains(word) {
                        topicCandidates.append((word, idx))
                    }
                }
                return true
            }
        }

        var topicScores: [String: (count: Int, sentences: Set<Int>)] = [:]
        for (word, sentenceIdx) in topicCandidates {
            guard word.count > 2, !stopWords.contains(word) else { continue }
            var entry = topicScores[word] ?? (0, [])
            entry.count += 1
            entry.sentences.insert(sentenceIdx)
            topicScores[word] = entry
        }

        let totalWords = transcript.split(separator: " ").count
        return topicScores.compactMap { topic, data -> TopicAnalysis? in
            let relevance = Double(data.count) / Double(max(totalWords, 1))
            guard relevance > 0.01 else { return nil }
            return TopicAnalysis(
                entryId: entryId,
                topic: topic.capitalized,
                sentiment: self.estimateSentiment(for: topic, in: transcript),
                keywords: [topic]
            )
        }
    }

    // MARK: - Entity Extraction

    func extractEntities(from transcript: String) -> [ExtractedEntity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = transcript
        var entities: [ExtractedEntity] = []

        tagger.enumerateTags(in: transcript.startIndex..<transcript.endIndex,
                             unit: .word, scheme: .nameType) { tag, range in
            guard let tag else { return true }
            let name = String(transcript[range])
            let type: String = {
                switch tag {
                case .personalName: return "person"
                case .placeName: return "place"
                case .organizationName: return "organization"
                default: return "unknown"
                }
            }()
            entities.append(ExtractedEntity(name: name, type: type))
            return true
        }

        return entities
    }

    // MARK: - Sentiment

    func computeSentiment(for topic: String, in transcript: String) async -> Double {
        if Phi3Service.shared.isAvailable {
            return (try? await Phi3Service.shared.classifySentiment(topic: topic, in: transcript)) ?? 0
        }
        return estimateSentiment(for: topic, in: transcript)
    }

    private func estimateSentiment(for topic: String, in transcript: String) -> Double {
        let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".?!\n"))
        let relevant = sentences.filter { $0.localizedCaseInsensitiveContains(topic) }
        guard !relevant.isEmpty else { return 0 }

        let positive: Set<String> = ["good", "great", "happy", "love", "wonderful", "amazing",
                                      "excellent", "better", "best", "nice", "glad", "beautiful",
                                      "fantastic", "positive", "improved", "progress", "grateful",
                                      "excited", "proud", "hopeful", "enjoyed"]
        let negative: Set<String> = ["bad", "terrible", "awful", "hate", "worst", "worse",
                                      "horrible", "sad", "angry", "frustrated", "annoyed",
                                      "stressed", "depressed", "anxious", "worried", "scared",
                                      "disappointed", "upset", "miserable", "painful", "lonely",
                                      "tired", "exhausted", "overwhelmed"]

        var total: Double = 0
        for sentence in relevant {
            let words = Set(sentence.lowercased().split(separator: " ").map(String.init))
            let pos = words.intersection(positive).count
            let neg = words.intersection(negative).count
            total += Double(pos - neg)
        }
        return max(-1, min(1, total / Double(relevant.count)))
    }

    // MARK: - Stop Words

    private let stopWords: Set<String> = [
        "the", "a", "an", "this", "that", "it", "its", "i", "me", "my", "you", "your",
        "he", "him", "his", "she", "her", "we", "us", "our", "they", "them", "their",
        "and", "or", "but", "if", "because", "as", "until", "while", "of", "at", "by",
        "for", "with", "about", "against", "between", "into", "through", "during",
        "before", "after", "above", "below", "to", "from", "up", "down", "in", "out",
        "on", "off", "over", "under", "again", "further", "then", "once", "here",
        "there", "when", "where", "why", "how", "all", "any", "both", "each", "few",
        "more", "most", "other", "some", "such", "no", "nor", "not", "only", "own",
        "same", "so", "than", "too", "very", "just", "also", "really", "actually",
        "well", "yeah", "like", "thing", "things", "way", "get", "got", "go", "went",
        "know", "think", "thought", "want", "need", "feel", "felt", "say", "said",
        "see", "saw", "come", "came", "take", "took", "make", "made", "day", "days",
        "time", "people", "good", "bad", "lot", "little", "much", "many"
    ]
}
