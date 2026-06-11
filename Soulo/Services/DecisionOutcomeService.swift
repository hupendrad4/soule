import Foundation

final class DecisionOutcomeService: Sendable {
    static let shared = DecisionOutcomeService()

    private let decisionPhrases: [String] = [
        "i decided", "i chose", "i've decided", "i have decided",
        "i'm going with", "i will", "i'll", "my plan is",
        "i made a decision", "i made up my mind", "i decided to",
        "going to", "planning to", "i've chosen", "i have chosen",
        "i committed to", "i'm committing to"
    ]

    private let positiveFollowUp: [String] = [
        "best decision", "glad i did", "worked out", "paid off",
        "happy i did", "good choice", "right call", "great decision",
        "worked well", "turning out great", "no regrets", "worth it"
    ]

    private let negativeFollowUp: [String] = [
        "worst decision", "regret", "shouldn't have", "mistake",
        "bad choice", "wrong call", "terrible decision", "wish i hadn't",
        "not worth it", "big mistake", "messed up", "failed"
    ]

    private let regretPhrases: [String] = [
        "i regret", "i should have", "i wish i had", "i shouldn't have",
        "that was a mistake", "bad idea", "terrible choice",
        "if only i had", "why did i", "biggest mistake"
    ]

    private let categoryKeywords: [String: String] = [
        "job": "career", "work": "career", "career": "career", "quit": "career",
        "move": "relocation", "relocate": "relocation", "apartment": "relocation",
        "buy": "finance", "invest": "finance", "money": "finance", "spend": "finance",
        "relationship": "relationship", "partner": "relationship", "dating": "relationship",
        "health": "health", "diet": "health", "exercise": "health", "doctor": "health",
        "school": "education", "study": "education", "course": "education", "degree": "education"
    ]

    // MARK: - Decision Scanning

    func scanDecisions(in entries: [JournalEntry], existingDecisions: [JournalDecision] = []) -> [JournalDecision] {
        var decisions = existingDecisions
        var seenTexts = Set(decisions.map { $0.decisionText.lowercased() })

        for entry in entries {
            let transcript = entry.transcript ?? ""
            guard !transcript.isEmpty else { continue }
            let lower = transcript.lowercased()

            for phrase in decisionPhrases where lower.contains(phrase) {
                guard let range = lower.range(of: phrase) else { continue }
                let after = transcript[transcript.index(range.upperBound, offsetBy: 0, limitedBy: transcript.endIndex) ?? transcript.endIndex...]
                    .trimmingCharacters(in: .whitespaces)
                let decisionText = String(after.prefix(100))
                    .components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? ""

                let cleaned = decisionText.trimmingCharacters(in: .whitespaces)
                guard cleaned.count > 5 else { continue }

                let key = cleaned.lowercased()
                if seenTexts.contains(key) {
                    if let idx = decisions.firstIndex(where: { $0.decisionText.lowercased() == key }) {
                        decisions[idx].mentionCount += 1
                        decisions[idx].lastMentioned = entry.timestamp
                    }
                    continue
                }

                seenTexts.insert(key)
                let category = detectCategory(for: cleaned)
                let expected = extractExpectedOutcome(from: cleaned)

                decisions.append(JournalDecision(
                    entryId: entry.id,
                    decisionText: cleaned,
                    category: category,
                    expectedOutcome: expected,
                    firstMentioned: entry.timestamp
                ))
            }
        }

        return decisions
    }

    // MARK: - Follow-Up Detection

    func detectFollowUps(in entries: [JournalEntry], decisions: inout [JournalDecision]) -> [DecisionOutcome] {
        var outcomes: [DecisionOutcome] = []

        for entry in entries {
            let transcript = entry.transcript ?? ""
            guard !transcript.isEmpty else { continue }
            let lower = transcript.lowercased()

            for idx in decisions.indices where decisions[idx].status == .active {
                guard decisions[idx].followUpEntryId == nil else { continue }

                let decisionWords = Set(decisions[idx].decisionText.lowercased()
                    .split(separator: " ").map(String.init))
                let matchCount = decisionWords.filter { lower.contains($0) }.count
                let daysSince = (entry.timestamp - decisions[idx].firstMentioned) / 86400

                guard matchCount >= max(2, decisionWords.count / 3), daysSince >= 1 else { continue }

                let outcome = classifyOutcome(in: transcript, decisionText: decisions[idx].decisionText)

                decisions[idx].followUpEntryId = entry.id
                decisions[idx].followUpSentiment = outcome.sentiment
                decisions[idx].followUpText = outcome.summary
                decisions[idx].status = outcome.status
                decisions[idx].lastMentioned = entry.timestamp

                outcomes.append(DecisionOutcome(
                    decisionId: decisions[idx].id,
                    outcomeStatus: outcome.status,
                    sentimentAtOutcome: outcome.sentiment,
                    timeToOutcome: Int(daysSince),
                    outcomeSummary: outcome.summary
                ))
            }
        }

        return outcomes
    }

    // MARK: - Regret Detection (standalone, for entries without prior decision tracking)

    func detectRegretPatterns(in entries: [JournalEntry]) -> [DetectedPattern] {
        guard entries.count >= 3 else { return [] }

        var regretMentions: [(text: String, date: TimeInterval)] = []

        for entry in entries {
            let transcript = entry.transcript?.lowercased() ?? ""
            guard !transcript.isEmpty else { continue }

            for phrase in regretPhrases where transcript.contains(phrase) {
                guard let range = transcript.range(of: phrase) else { continue }
                let after = entry.transcript![transcript.index(range.upperBound, offsetBy: 0, limitedBy: entry.transcript!.endIndex) ?? entry.transcript!.endIndex...]
                    .trimmingCharacters(in: .whitespaces)
                let regretText = String(after.prefix(80))
                    .components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? ""

                regretMentions.append((regretText, entry.timestamp))
            }
        }

        guard regretMentions.count >= 2 else { return [] }

        let distinctTopics = Set(regretMentions.map { extractTopic($0.text) })
        let severity = min(85, 30 + regretMentions.count * 10 + (distinctTopics.count > 1 ? 15 : 0))

        return [DetectedPattern(
            patternType: .decisionRegret,
            severity: severity,
            title: "Decision Regret Pattern",
            message: "You've expressed regret \(regretMentions.count) times about \(distinctTopics.count == 1 ? "a decision" : "\(distinctTopics.count) different decisions"). This may indicate a pattern of hasty choices or difficulty committing.",
            dataJson: (try? String(data: JSONEncoder().encode(regretMentions.map { $0.text }), encoding: .utf8)),
            firstDetected: regretMentions.first!.date,
            lastDetected: regretMentions.last!.date,
            occurrenceCount: regretMentions.count
        )]
    }

    // MARK: - Private Helpers

    private func classifyOutcome(in transcript: String, decisionText: String) -> (status: DecisionStatus, sentiment: Double, summary: String) {
        let lower = transcript.lowercased()

        for phrase in positiveFollowUp where lower.contains(phrase) {
            return (.kept, 0.7, "Outcome was positive: '\(phrase)'")
        }
        for phrase in negativeFollowUp where lower.contains(phrase) {
            return (.regretted, -0.6, "Outcome was negative: '\(phrase)'")
        }

        // Check for abandonment signals
        let abandonSignals = ["gave up", "stopped", "quit", "not doing", "haven't been"]
        for phrase in abandonSignals where lower.contains(phrase) {
            return (.abandoned, -0.3, "Decision appears abandoned: '\(phrase)'")
        }

        // Sentiment-based classification
        let sentiment = estimateSentiment(in: transcript, about: decisionText)
        if sentiment > 0.3 {
            return (.kept, sentiment, "Positive sentiment around the decision")
        } else if sentiment < -0.3 && lower.contains("but") || lower.contains("however") {
            return (.regretted, sentiment, "Mixed but leaning negative")
        }

        return (.pending, sentiment, "Outcome unclear, needs more data")
    }

    private func estimateSentiment(in transcript: String, about decisionText: String) -> Double {
        let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        let relevant = sentences.filter { $0.localizedCaseInsensitiveContains(decisionText.prefix(20)) }
        guard !relevant.isEmpty else { return 0 }

        let positive = ["good", "great", "happy", "love", "wonderful", "best", "right",
                         "glad", "excellent", "fantastic", "improved", "better", "helpful"]
        let negative = ["bad", "terrible", "awful", "hate", "worst", "wrong", "mistake",
                         "regret", "unfortunately", "disappointed", "frustrated", "stupid"]

        var total: Double = 0
        for sentence in relevant {
            let words = Set(sentence.lowercased().split(separator: " ").map(String.init))
            total += Double(words.intersection(positive).count - words.intersection(negative).count)
        }
        return max(-1, min(1, total / Double(max(relevant.count, 1))))
    }

    private func detectCategory(for text: String) -> String? {
        let lower = text.lowercased()
        for (keyword, category) in categoryKeywords {
            if lower.contains(keyword) { return category }
        }
        return nil
    }

    private func extractExpectedOutcome(from text: String) -> String? {
        let hopePhrases = ["so that", "to", "hoping", "hope it", "wanted to", "need to"]
        let lower = text.lowercased()
        for phrase in hopePhrases where lower.contains(phrase) {
            guard let range = lower.range(of: phrase) else { continue }
            let after = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let outcome = String(after.prefix(60))
                .components(separatedBy: CharacterSet(charactersIn: ".!?\n,")).first ?? ""
            return outcome.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func extractTopic(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        return words.first { $0.count > 4 } ?? words.first ?? text
    }
}
