import Foundation

final class PatternDetectionService: Sendable {
    func detectPatterns(in entries: [JournalEntry]) async throws -> [DetectedPattern] {
        guard entries.count >= 3 else { return [] }

        return try await Task.detached(priority: .utility) {
            var patterns: [DetectedPattern] = []

            let sorted = entries.sorted { $0.timestamp < $1.timestamp }

            patterns += self.detectBrokenPromises(in: sorted)
            patterns += self.detectTopicAvoidance(in: sorted)
            patterns += self.detectSentimentDecline(in: sorted)
            patterns += self.detectGoalAbandonment(in: sorted)
            patterns += self.detectContradictions(in: sorted)
            patterns += self.detectCognitiveShift(in: sorted)
            patterns += self.detectRelationshipPatterns(in: sorted)
            patterns += self.detectDecisionPatterns(in: sorted)

            return patterns
                .filter { $0.severity >= UserDefaults.standard.integer(forKey: "insight_threshold").nonZero(default: 30) }
                .sorted { $0.severity > $1.severity }
        }.value
    }

    // MARK: - Broken Promise Detection

    private func detectBrokenPromises(in entries: [JournalEntry]) -> [DetectedPattern] {
        let commitmentPhrases = [
            "i will", "i'll", "i'm going to", "i need to", "i should",
            "i promise", "i swear", "starting", "going to start"
        ]
        let backtrackPhrases = ["i didn't", "i haven't", "i failed", "i couldn't", "still haven't"]

        var patterns: [DetectedPattern] = []
        var pendingCommitments: [(phrase: String, date: TimeInterval, entryId: String)] = []

        for entry in entries {
            let transcript = entry.transcript?.lowercased() ?? ""
            guard !transcript.isEmpty else { continue }

            for phrase in commitmentPhrases where transcript.contains(phrase) {
                if let range = transcript.range(of: phrase) {
                    let afterPhrase = transcript[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    let commitment = String(afterPhrase.prefix(60))
                        .components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? ""

                    if commitment.count > 5 {
                        pendingCommitments.append((commitment, entry.timestamp, entry.id))
                    }
                }
            }

            for phrase in backtrackPhrases where transcript.contains(phrase) {
                pendingCommitments.removeAll { pending in
                    let daysSince = (entry.timestamp - pending.date) / 86400
                    let words = pending.phrase.split(separator: " ")
                    let matched = words.filter { transcript.contains($0.lowercased()) }.count
                    return daysSince > 1 && daysSince < 90 && matched >= words.count / 2
                }
            }
        }

        for commitment in pendingCommitments {
            let daysSince = (Date().timeIntervalSince1970 - commitment.date) / 86400
            guard daysSince > 3 else { continue }

            let severity = min(95, Int(daysSince) * 3 + 10)
            patterns.append(DetectedPattern(
                patternType: .brokenPromise,
                severity: severity,
                title: "Unkept Commitment",
                message: "You said you would '\(commitment.phrase)' \(Int(daysSince)) days ago. You haven't mentioned following through.",
                firstDetected: commitment.date,
                lastDetected: commitment.date,
                occurrenceCount: 1
            ))
        }

        return patterns
    }

    // MARK: - Topic Avoidance Detection

    private func detectTopicAvoidance(in entries: [JournalEntry]) -> [DetectedPattern] {
        guard entries.count >= 5 else { return [] }

        var topics: [String: [Double]] = [:] // topic -> list of vocal energies

        for entry in entries {
            guard let biomarkers = entry.biomarkers, let topicsList = entry.topics else { continue }

            for topic in topicsList {
                let energy = biomarkers.vocalEnergy
                topics[topic.topic, default: []].append(energy)
            }
        }

        let globalMeanEnergy = topics.values.flatMap { $0 }.reduce(0, +) / Double(max(1, topics.values.flatMap { $0 }.count))

        var patterns: [DetectedPattern] = []
        for (topic, energies) in topics where energies.count >= 2 {
            let topicMean = energies.reduce(0, +) / Double(energies.count)
            let energyDrop = globalMeanEnergy - topicMean

            if energyDrop > 0.2 { // Energy drops >20% on this topic
                let severity = min(90, Int(energyDrop * 150))
                patterns.append(DetectedPattern(
                    patternType: .topicAvoidance,
                    severity: severity,
                    title: "Topic Avoidance: \(topic)",
                    message: "Your vocal energy drops \(Int(energyDrop * 100))% when discussing \(topic). Mentioned \(energies.count) times with consistent avoidance.",
                    firstDetected: entries.first(where: { $0.topics?.contains(where: { $0.topic == topic }) == true })?.timestamp ?? Date().timeIntervalSince1970,
                    lastDetected: entries.last(where: { $0.topics?.contains(where: { $0.topic == topic }) == true })?.timestamp ?? Date().timeIntervalSince1970,
                    occurrenceCount: energies.count
                ))
            }
        }

        return patterns
    }

    // MARK: - Sentiment Decline Detection

    private func detectSentimentDecline(in entries: [JournalEntry]) -> [DetectedPattern] {
        guard entries.count >= 5 else { return [] }

        var topicSentiments: [String: [(date: TimeInterval, sentiment: Double)]] = [:]

        for entry in entries {
            guard let topics = entry.topics else { continue }
            for topic in topics {
                topicSentiments[topic.topic, default: []].append((entry.timestamp, topic.sentiment))
            }
        }

        var patterns: [DetectedPattern] = []
        for (topic, dataPoints) in topicSentiments where dataPoints.count >= 3 {
            let sortedData = dataPoints.sorted { $0.date < $1.date }
            let sentiments = sortedData.map { $0.sentiment }

            // Linear regression slope
            let n = Double(sentiments.count)
            let sumX = (0..<sentiments.count).reduce(0, +)
            let sumY = sentiments.reduce(0, +)
            let sumXY = sentiments.enumerated().map { Double($0.offset) * $0.element }.reduce(0, +)
            let sumX2 = (0..<sentiments.count).map { Double($0 * $0) }.reduce(0, +)

            let slope = (n * sumXY - Double(sumX) * sumY) / (n * sumX2 - Double(sumX) * Double(sumX))

            if slope < -0.05 { // Declining sentiment
                let severity = min(95, Int(abs(slope) * 200))
                let first = sortedData.first!.sentiment
                let last = sortedData.last!.sentiment
                let daysSpan = Int((sortedData.last!.date - sortedData.first!.date) / 86400)

                patterns.append(DetectedPattern(
                    patternType: .sentimentDecline,
                    severity: severity,
                    title: "Declining: \(topic)",
                    message: "Your sentiment about \(topic) has declined from \(String(format: "%.1f", first)) to \(String(format: "%.1f", last)) over \(daysSpan) days.",
                    firstDetected: sortedData.first!.date,
                    lastDetected: sortedData.last!.date,
                    occurrenceCount: sentiments.count
                ))
            }
        }

        return patterns
    }

    // MARK: - Goal Abandonment Detection

    private func detectGoalAbandonment(in entries: [JournalEntry]) -> [DetectedPattern] {
        let startPhrases = ["starting", "beginning", "new goal", "new habit", "this time", "motivated"]
        let declinePhrases = ["skipped", "missed", "hard", "difficult", "tired", "no time", "busy"]
        let abandonPhrases = ["gave up", "quit", "stopped", "failed", "couldn't do it", "not for me"]

        var patterns: [DetectedPattern] = []
        var activeGoals: [(id: UUID, goal: String, startDate: TimeInterval, entries: [String])] = []

        for entry in entries {
            let transcript = entry.transcript?.lowercased() ?? ""
            guard !transcript.isEmpty else { continue }

            // Detect goal start
            for phrase in startPhrases where transcript.contains(phrase) {
                let goal = extractGoal(from: transcript, after: phrase)
                if !goal.isEmpty {
                    activeGoals.append((UUID(), goal, entry.timestamp, [transcript]))
                }
            }

            // Track progress
            for idx in activeGoals.indices {
                let goalWords = activeGoals[idx].goal.split(separator: " ").map(String.init)
                let matchCount = goalWords.filter { transcript.contains($0.lowercased()) }.count
                if matchCount >= goalWords.count / 3 {
                    activeGoals[idx].entries.append(transcript)
                }
            }

            // Detect abandonment
            for phrase in abandonPhrases where transcript.contains(phrase) {
                for goal in activeGoals {
                    let goalWords = goal.goal.split(separator: " ").map(String.init)
                    let matchCount = goalWords.filter { transcript.contains($0.lowercased()) }.count
                    if matchCount >= goalWords.count / 3 {
                        let daysActive = (entry.timestamp - goal.startDate) / 86400
                        let severity = min(90, 30 + Int(daysActive) * 2)

                        patterns.append(DetectedPattern(
                            patternType: .goalAbandonment,
                            severity: severity,
                            title: "Abandoned Goal: \(goal.goal)",
                            message: "You started '\(goal.goal)' but mentioned giving up \(Int(daysActive)) days later. You mentioned it \(goal.entries.count) times with declining enthusiasm.",
                            firstDetected: goal.startDate,
                            lastDetected: entry.timestamp,
                            occurrenceCount: goal.entries.count
                        ))
                    }
                }
            }
        }

        // Detect cycles (multiple abandoned goals with similar patterns)
        if patterns.count >= 2 && Set(patterns.map { $0.title }).count >= 2 {
            let avgDaysToAbandon = patterns.map { Int(($0.lastDetected - $0.firstDetected) / 86400) }.reduce(0, +) / patterns.count
            if patterns.count >= 3 {
                let cyclePattern = DetectedPattern(
                    patternType: .goalAbandonment,
                    severity: max(patterns.map { $0.severity }.max() ?? 50, 70),
                    title: "Goal Abandonment Cycle",
                    message: "You've started and abandoned \(patterns.count) goals. Average time to abandon: \(avgDaysToAbandon) days. The pattern is nearly identical each time.",
                    firstDetected: patterns.first!.firstDetected,
                    lastDetected: patterns.last!.lastDetected,
                    occurrenceCount: patterns.count
                )
                return [cyclePattern]
            }
        }

        return patterns
    }

    // MARK: - Contradiction Detection

    private func detectContradictions(in entries: [JournalEntry]) -> [DetectedPattern] {
        guard entries.count >= 3 else { return [] }

        var topicSentiments: [String: [(date: TimeInterval, sentiment: Double, text: String)]] = [:]

        for entry in entries {
            guard let topics = entry.topics else { continue }
            let transcript = entry.transcript ?? ""
            for topic in topics {
                topicSentiments[topic.topic, default: []].append((entry.timestamp, topic.sentiment, transcript))
            }
        }

        var patterns: [DetectedPattern] = []
        for (topic, dataPoints) in topicSentiments where dataPoints.count >= 2 {
            let sorted = dataPoints.sorted { $0.date < $1.date }

            for i in 0..<sorted.count - 1 {
                for j in (i + 1)..<sorted.count {
                    let delta = abs(sorted[i].sentiment - sorted[j].sentiment)
                    if delta > 1.2 && abs(sorted[j].date - sorted[i].date) < 86400 * 30 {
                        let severity = min(85, Int(delta * 60))
                        patterns.append(DetectedPattern(
                            patternType: .contradiction,
                            severity: severity,
                            title: "Contradiction: \(topic)",
                            message: "You felt \(sentimentLabel(sorted[i].sentiment)) about \(topic), then \(sentimentLabel(sorted[j].sentiment)) within \(Int((sorted[j].date - sorted[i].date) / 86400)) days.",
                            firstDetected: sorted[i].date,
                            lastDetected: sorted[j].date,
                            occurrenceCount: 2
                        ))
                    }
                }
            }
        }

        return patterns
    }

    // MARK: - Cognitive Shift Detection

    private func detectCognitiveShift(in entries: [JournalEntry]) -> [DetectedPattern] {
        guard entries.count >= 10 else { return [] }

        let biomarkers: [(date: TimeInterval, speechRate: Double, hesitationRate: Double, pitchInstability: Double)] = entries.compactMap { entry in
            guard let b = entry.biomarkers, entry.biomarkersStatus == .done else { return nil }
            return (entry.timestamp, b.speechRate, b.hesitationRate, b.pitchInstability)
        }.sorted { $0.date < $1.date }

        guard biomarkers.count >= 10 else { return [] }

        let midpoint = biomarkers.count / 2
        let firstHalf = biomarkers[0..<midpoint]
        let secondHalf = biomarkers[midpoint..<biomarkers.count]

        func avg(_ keyPath: KeyPath<(date: TimeInterval, speechRate: Double, hesitationRate: Double, pitchInstability: Double), Double>) -> Double {
            let first = firstHalf.reduce(0) { $0 + $1[keyPath: keyPath] } / Double(firstHalf.count)
            let second = secondHalf.reduce(0) { $0 + $1[keyPath: keyPath] } / Double(secondHalf.count)
            return second - first
        }

        let speechRateDelta = avg(\.speechRate)
        let hesitationDelta = avg(\.hesitationRate)
        let pitchDelta = avg(\.pitchInstability)

        var patterns: [DetectedPattern] = []

        if abs(speechRateDelta) > 0.5 || abs(hesitationDelta) > 0.1 || abs(pitchDelta) > 20 {
            var changes: [String] = []
            if speechRateDelta > 0.5 { changes.append("speech rate increased \(String(format: "%.1f", speechRateDelta)) wps") }
            if speechRateDelta < -0.5 { changes.append("speech rate decreased \(String(format: "%.1f", abs(speechRateDelta))) wps") }
            if hesitationDelta > 0.1 { changes.append("hesitation increased \(String(format: "%.0f", hesitationDelta * 100))%") }
            if pitchDelta > 20 { changes.append("pitch instability increased") }

            let severity = min(90, Int(abs(speechRateDelta) * 30 + abs(hesitationDelta) * 100 + abs(pitchDelta) / 2))
            patterns.append(DetectedPattern(
                patternType: .cognitiveShift,
                severity: severity,
                title: "Speech Pattern Shift Detected",
                message: "Your speech patterns have changed: \(changes.joined(separator: ", ")). This could indicate increased stress, fatigue, or cognitive load over the past \(biomarkers.count / max(1, Int(biomarkers.last!.date - biomarkers.first!.date) / 86400)) days.",
                firstDetected: biomarkers.first!.date,
                lastDetected: biomarkers.last!.date,
                occurrenceCount: biomarkers.count
            ))
        }

        return patterns
    }

    // MARK: - Relationship Pattern Detection

    private func detectRelationshipPatterns(in entries: [JournalEntry]) -> [DetectedPattern] {
        let relationshipTerms = [
            "partner", "boyfriend", "girlfriend", "husband", "wife", "spouse",
            "mom", "dad", "mother", "father", "sister", "brother", "friend",
            "boss", "manager", "colleague", "team", "relationship", "marriage"
        ]

        var patterns: [DetectedPattern] = []
        var personMentions: [String: [(date: TimeInterval, sentiment: Double)]] = [:]

        for entry in entries {
            guard let topics = entry.topics else { continue }
            for topic in topics {
                let lower = topic.topic.lowercased()
                if relationshipTerms.contains(lower) || relationshipTerms.contains(where: { lower.contains($0) }) {
                    personMentions[topic.topic, default: []].append((entry.timestamp, topic.sentiment))
                }
            }
        }

        for (person, mentions) in personMentions where mentions.count >= 3 {
            let sorted = mentions.sorted { $0.date < $1.date }
            let avgSentiment = sorted.map { $0.sentiment }.reduce(0, +) / Double(sorted.count)

            if avgSentiment < -0.3 {
                let daysActive = Int((sorted.last!.date - sorted.first!.date) / 86400)
                let severity = min(85, Int(abs(avgSentiment) * 80))
                patterns.append(DetectedPattern(
                    patternType: .relationshipPattern,
                    severity: severity,
                    title: "Strained Relationship: \(person)",
                    message: "Your sentiment about \(person) is consistently negative (\(String(format: "%.1f", avgSentiment)) avg). Mentioned \(mentions.count) times over \(daysActive) days.",
                    firstDetected: sorted.first!.date,
                    lastDetected: sorted.last!.date,
                    occurrenceCount: mentions.count
                ))
            }

            // Volatility detection
            let volatility = sorted.enumerated().dropFirst().map { abs($0.element.sentiment - sorted[$0.offset - 1].sentiment) }.reduce(0, +) / Double(sorted.count - 1)
            if volatility > 0.8 {
                let severity = min(80, Int(volatility * 60))
                patterns.append(DetectedPattern(
                    patternType: .relationshipPattern,
                    severity: severity,
                    title: "Volatile Sentiment: \(person)",
                    message: "Your feelings about \(person) swing dramatically (volatility: \(String(format: "%.1f", volatility))). Mentioned \(mentions.count) times.",
                    firstDetected: sorted.first!.date,
                    lastDetected: sorted.last!.date,
                    occurrenceCount: mentions.count
                ))
            }
        }

        return patterns
    }

    // MARK: - Decision Outcome Detection

    private func detectDecisionPatterns(in entries: [JournalEntry]) -> [DetectedPattern] {
        guard entries.count >= 3 else { return [] }

        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        var decisions = DecisionOutcomeService.shared.scanDecisions(in: sorted)
        _ = DecisionOutcomeService.shared.detectFollowUps(in: sorted, decisions: &decisions)

        let regretPatterns = DecisionOutcomeService.shared.detectRegretPatterns(in: entries)
        var patterns = regretPatterns

        let regretted = decisions.filter { $0.status == .regretted }
        for decision in regretted {
            guard let followUpSentiment = decision.followUpSentiment else { continue }
            let severity = min(80, 30 + decision.daysSinceDecision * 2 + Int(abs(followUpSentiment) * 20))
            patterns.append(DetectedPattern(
                patternType: .decisionRegret,
                severity: severity,
                title: "Regretted Decision",
                message: "You regretted '\(decision.decisionText.prefix(60))' after \(decision.daysSinceDecision) days. Sentiment at outcome: \(String(format: "%.1f", followUpSentiment)).",
                dataJson: (try? String(data: JSONEncoder().encode(decision.id), encoding: .utf8)),
                firstDetected: decision.firstMentioned,
                lastDetected: decision.lastMentioned,
                occurrenceCount: decision.mentionCount
            ))
        }

        let pending = decisions.filter { $0.status == .pending && $0.daysSinceDecision > 14 }
        for decision in pending {
            let severity = min(50, 20 + decision.daysSinceDecision)
            patterns.append(DetectedPattern(
                patternType: .decisionRegret,
                severity: severity,
                title: "Unresolved Decision",
                message: "You decided '\(decision.decisionText.prefix(60))' \(decision.daysSinceDecision) days ago with no follow-up recorded.",
                dataJson: (try? String(data: JSONEncoder().encode(decision.id), encoding: .utf8)),
                firstDetected: decision.firstMentioned,
                lastDetected: decision.lastMentioned,
                occurrenceCount: decision.mentionCount
            ))
        }

        return patterns
    }

    // MARK: - Helpers

    private func extractGoal(from text: String, after phrase: String) -> String {
        guard let range = text.range(of: phrase) else { return "" }
        let afterPhrase = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let goal = String(afterPhrase.prefix(80))
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? ""
        return goal.trimmingCharacters(in: .whitespaces)
    }

    private func sentimentLabel(_ value: Double) -> String {
        if value > 0.5 { return "positively" }
        if value > 0.1 { return "somewhat positively" }
        if value < -0.5 { return "very negatively" }
        if value < -0.1 { return "negatively" }
        return "neutrally"
    }
}


