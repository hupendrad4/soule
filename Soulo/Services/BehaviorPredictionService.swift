import Foundation

final class BehaviorPredictionService: Sendable {
    static let shared = BehaviorPredictionService()

    private init() {}

    // MARK: - Predictions

    func generatePredictions(from entries: [JournalEntry],
                              decisions: [JournalDecision],
                              baselines: BaselineService.FinalizedBaseline?) async -> PredictionSummary {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let now = Date().timeIntervalSince1970

        var predictions: [BehaviorPrediction] = []

        predictions.append(predictJournalFrequency(entries: sorted, now: now))
        predictions.append(predictSentimentTrajectory(entries: sorted, now: now))
        predictions.append(predictGoalCompletion(decisions: decisions, now: now))
        predictions.append(predictNextEmotion(entries: sorted, now: now))
        predictions.append(predictAbandonmentRisk(entries: sorted, decisions: decisions, now: now))
        predictions.append(predictEmotionalCrisis(entries: sorted, baselines: baselines, now: now))

        let valid = predictions.filter { $0.probability > 0.3 }
        let topRisk = valid.filter { $0.type == .abandonmentRisk || $0.type == .emotionalCrisis }
            .sorted { $0.probability > $1.probability }.first
        let topOpportunity = valid.filter { $0.type == .goalCompletion || $0.type == .journalFrequency }
            .sorted { $0.probability > $1.probability }.first

        let recentValence = sorted.compactMap { $0.emotion?.valence }.suffix(5)
        let overallTrend: TrendDirection = recentValence.count >= 3
            ? (BiomarkerTrendService.computeSlope(Array(recentValence)) > 0 ? .increasing : .decreasing)
            : .stable

        return PredictionSummary(
            predictions: valid,
            topRisk: topRisk,
            topOpportunity: topOpportunity,
            overallWellbeingTrend: overallTrend,
            projectionDays: 14
        )
    }

    // MARK: - Individual Predictors

    private func predictJournalFrequency(entries: [JournalEntry], now: TimeInterval) -> BehaviorPrediction {
        guard entries.count >= 7 else {
            return BehaviorPrediction(
                id: UUID().uuidString, type: .journalFrequency,
                prediction: "Not enough data to predict journaling frequency.",
                probability: 0, confidence: .low, basedOn: [],
                validUntil: now + 86400 * 7, createdAt: now
            )
        }

        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let gaps = sorted.enumerated().dropFirst().map { i, e in
            (e.timestamp - sorted[i - 1].timestamp) / 86400
        }

        let recentGaps = gaps.suffix(5)
        let avgRecentGap = recentGaps.reduce(0, +) / Double(max(recentGaps.count, 1))

        // Predict will journal in the next (avg gap) days
        let willJournal = avgRecentGap <= 2.0
        let probability = willJournal ? max(0.5, 1.0 - avgRecentGap / 7.0) : max(0.1, 0.3 / max(avgRecentGap, 0.5))
        let confidence: BehaviorPrediction.PredictionConfidence = entries.count >= 30 ? .high : entries.count >= 15 ? .moderate : .low

        let days = Int(avgRecentGap.rounded())
        let prediction = willJournal
            ? "Likely to journal in the next \(days) day\(days == 1 ? "" : "s")"
            : "Journaling frequency declining. Last \(gaps.count) gaps avg \(String(format: "%.1f", avgRecentGap)) days."

        return BehaviorPrediction(
            id: UUID().uuidString, type: .journalFrequency,
            prediction: prediction, probability: probability,
            confidence: confidence,
            basedOn: ["Average gap: \(String(format: "%.1f", avgRecentGap)) days"],
            validUntil: now + 86400 * 7, createdAt: now
        )
    }

    private func predictSentimentTrajectory(entries: [JournalEntry], now: TimeInterval) -> BehaviorPrediction {
        let withEmotion = entries.compactMap { e -> (TimeInterval, Double)? in
            guard let em = e.emotion else { return nil }
            return (e.timestamp, em.valence)
        }.sorted { $0.0 < $1.0 }

        guard withEmotion.count >= 5 else {
            return BehaviorPrediction(
                id: UUID().uuidString, type: .sentimentTrajectory,
                prediction: "Not enough emotional data to project sentiment.",
                probability: 0, confidence: .low, basedOn: [],
                validUntil: now + 86400 * 7, createdAt: now
            )
        }

        let vals = withEmotion.map { $0.1 }
        let slope = BiomarkerTrendService.computeSlope(vals)
        let recent = vals.suffix(3).reduce(0, +) / Double(min(vals.count, 3))

        let projected = min(1, max(-1, recent + slope * 14))
        let probability = abs(slope) > 0.02 ? min(0.9, abs(slope) * 10) : 0.3
        let confidence: BehaviorPrediction.PredictionConfidence = vals.count >= 20 ? .high : vals.count >= 10 ? .moderate : .low

        let direction = slope > 0 ? "improving" : "declining"
        let prediction = abs(slope) > 0.05
            ? "Sentiment \(direction). Projected valence in 14 days: \(String(format: "%.2f", projected))."
            : "Sentiment stable. No significant change projected."

        return BehaviorPrediction(
            id: UUID().uuidString, type: .sentimentTrajectory,
            prediction: prediction, probability: probability,
            confidence: confidence,
            basedOn: ["Sentiment slope: \(String(format: "%.3f", slope))"],
            validUntil: now + 86400 * 14, createdAt: now
        )
    }

    private func predictGoalCompletion(decisions: [JournalDecision], now: TimeInterval) -> BehaviorPrediction {
        let goals = decisions.filter { $0.status == .active || $0.status == .kept }
        guard !goals.isEmpty else {
            return BehaviorPrediction(
                id: UUID().uuidString, type: .goalCompletion,
                prediction: "No active goals to track. Try setting one!",
                probability: 0, confidence: .low, basedOn: [],
                validUntil: now + 86400 * 7, createdAt: now
            )
        }

        let completionRate: Double
        let total = decisions.count
        let completed = decisions.filter { $0.status == .kept }.count
        completionRate = Double(completed) / Double(max(total, 1))

        let avgDaysActive = decisions.filter { $0.status == .abandoned || $0.status == .regretted }
            .map { Int($0.lastMentioned - $0.firstMentioned) / 86400 }
        let avgAbandonDays = avgDaysActive.isEmpty ? 14 : avgDaysActive.reduce(0, +) / avgDaysActive.count

        let probability = min(0.9, completionRate + (1.0 - Double(min(avgAbandonDays, 30)) / 30.0) * 0.3)
        let confidence: BehaviorPrediction.PredictionConfidence = total >= 10 ? .high : total >= 5 ? .moderate : .low

        let prediction = completionRate > 0.5
            ? "Goal completion rate is strong (\(Int(completionRate * 100))%). Keep setting goals!"
            : "Goal completion rate is \(Int(completionRate * 100))%. Average abandonment at \(avgAbandonDays) days."

        return BehaviorPrediction(
            id: UUID().uuidString, type: .goalCompletion,
            prediction: prediction, probability: probability,
            confidence: confidence,
            basedOn: ["\(completed)/\(total) goals kept", "Avg abandonment: \(avgAbandonDays) days"],
            validUntil: now + 86400 * 14, createdAt: now
        )
    }

    private func predictNextEmotion(entries: [JournalEntry], now: TimeInterval) -> BehaviorPrediction {
        let emotions = entries.compactMap { $0.emotion?.primaryEmotion }
        guard emotions.count >= 5 else {
            return BehaviorPrediction(
                id: UUID().uuidString, type: .nextEmotion,
                prediction: "Not enough emotional data to predict.",
                probability: 0, confidence: .low, basedOn: [],
                validUntil: now + 86400 * 3, createdAt: now
            )
        }

        var counts: [EmotionType: Int] = [:]
        for e in emotions { counts[e, default: 0] += 1 }

        // Weight recent entries more
        let recent = emotions.suffix(min(5, emotions.count))
        for e in recent { counts[e, default: 0] += 2 }

        guard let top = counts.max(by: { $0.value < $1.value }) else {
            return BehaviorPrediction(
                id: UUID().uuidString, type: .nextEmotion,
                prediction: "Unable to determine likely emotion.",
                probability: 0, confidence: .low, basedOn: [],
                validUntil: now + 86400 * 3, createdAt: now
            )
        }

        let total = Double(counts.values.reduce(0, +))
        let probability = Double(top.value) / total
        let confidence: BehaviorPrediction.PredictionConfidence = emotions.count >= 20 ? .high : emotions.count >= 10 ? .moderate : .low

        return BehaviorPrediction(
            id: UUID().uuidString, type: .nextEmotion,
            prediction: "Most likely next emotion: \(top.key.displayName)",
            probability: probability, confidence: confidence,
            basedOn: ["Historical frequency: \(top.key.displayName) (\(Int(probability * 100))%)"],
            validUntil: now + 86400 * 3, createdAt: now
        )
    }

    private func predictAbandonmentRisk(entries: [JournalEntry], decisions: [JournalDecision], now: TimeInterval) -> BehaviorPrediction {
        guard entries.count >= 10 else {
            return BehaviorPrediction(
                id: UUID().uuidString, type: .abandonmentRisk,
                prediction: "Need more entries to assess abandonment risk.",
                probability: 0, confidence: .low, basedOn: [],
                validUntil: now + 86400 * 7, createdAt: now
            )
        }

        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let recent = sorted.suffix(3)

        // Risk signals
        let recentHesitation = recent.compactMap { $0.biomarkers?.hesitationRate }.reduce(0, +) / Double(max(recent.count, 1))
        let recentSentiment = recent.compactMap { $0.emotion?.valence }.reduce(0, +) / Double(max(recent.count, 1))
        let avgHesitationOverall = sorted.compactMap { $0.biomarkers?.hesitationRate }.reduce(0, +) / Double(max(sorted.count, 1))

        let abandonedRecently = decisions.filter { $0.status == .abandoned && $0.lastMentioned > now - 86400 * 30 }.count

        var riskScore = 0.0
        var signals: [String] = []

        if recentHesitation > avgHesitationOverall * 1.3 {
            riskScore += 0.2
            signals.append("Increased hesitation")
        }
        if recentSentiment < -0.3 {
            riskScore += 0.25
            signals.append("Recent negative sentiment")
        }
        if abandonedRecently >= 2 {
            riskScore += 0.3
            signals.append("Recent goal abandonments")
        }
        if sorted.count < 5 || recent.count < 2 {
            riskScore += 0.15
            signals.append("Low engagement")
        }

        let probability = min(0.95, riskScore)
        let confidence: BehaviorPrediction.PredictionConfidence = riskScore > 0.5 ? .moderate : .low

        let prediction = riskScore > 0.5
            ? "Moderate abandonment risk (\(String(format: "%.0f", riskScore * 100))%). \(signals.joined(separator: ", "))."
            : "Low abandonment risk. Keep the momentum going!"

        return BehaviorPrediction(
            id: UUID().uuidString, type: .abandonmentRisk,
            prediction: prediction, probability: probability,
            confidence: confidence, basedOn: signals,
            validUntil: now + 86400 * 7, createdAt: now
        )
    }

    private func predictEmotionalCrisis(entries: [JournalEntry], baselines: BaselineService.FinalizedBaseline?,
                                         now: TimeInterval) -> BehaviorPrediction {
        guard entries.count >= 15 else {
            return BehaviorPrediction(
                id: UUID().uuidString, type: .emotionalCrisis,
                prediction: "Not enough data for crisis prediction.",
                probability: 0, confidence: .low, basedOn: [],
                validUntil: now + 86400 * 7, createdAt: now
            )
        }

        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let recent = sorted.suffix(5)

        var crisisSignals = 0
        var signals: [String] = []

        // Persistently negative sentiment
        let recentValence = recent.compactMap { $0.emotion?.valence }
        if recentValence.count >= 3 {
            let avg = recentValence.reduce(0, +) / Double(recentValence.count)
            if avg < -0.5 { crisisSignals += 2; signals.append("Persistent negative sentiment") }
            else if avg < -0.3 { crisisSignals += 1; signals.append("Leaning negative") }
        }

        // High hesitation + low energy (withdrawal signals)
        let recentBio = recent.compactMap { $0.biomarkers }
        if recentBio.count >= 3 {
            let avgHesitation = recentBio.map { $0.hesitationRate }.reduce(0, +) / Double(recentBio.count)
            let avgEnergy = recentBio.map { $0.vocalEnergy }.reduce(0, +) / Double(recentBio.count)
            if avgHesitation > 0.4 && avgEnergy < 0.3 { crisisSignals += 2; signals.append("Withdrawal pattern detected") }
        }

        // Rapid decline slope
        let allValence = sorted.compactMap { $0.emotion?.valence }
        if allValence.count >= 10 {
            let slope = BiomarkerTrendService.computeSlope(Array(allValence.suffix(10)))
            if slope < -0.1 { crisisSignals += 2; signals.append("Rapid sentiment decline") }
        }

        // Consecutive negative entries
        let negativeStreak = recent.filter { ($0.emotion?.valence ?? 0) < -0.2 }.count
        if negativeStreak >= 3 { crisisSignals += 1; signals.append("\(negativeStreak) consecutive negative entries") }

        let probability = min(0.95, Double(crisisSignals) * 0.15)
        let confidence: BehaviorPrediction.PredictionConfidence = crisisSignals >= 4 ? .moderate : .low

        let prediction = crisisSignals >= 3
            ? "\(crisisSignals) crisis signals detected. Consider checking in with a trusted person."
            : "No crisis signals detected. You're doing well."

        return BehaviorPrediction(
            id: UUID().uuidString, type: .emotionalCrisis,
            prediction: prediction, probability: probability,
            confidence: confidence, basedOn: signals,
            validUntil: now + 86400 * 3, createdAt: now
        )
    }
}
