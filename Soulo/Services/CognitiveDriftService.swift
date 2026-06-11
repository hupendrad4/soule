import Foundation

final class CognitiveDriftService: Sendable {
    static let shared = CognitiveDriftService()

    private init() {}

    // MARK: - Drift Detection

    func detectDrift(from entries: [JournalEntry]) async throws -> DriftReport? {
        let dated = entries.compactMap { e -> (TimeInterval, VoiceBiomarkers, EmotionalState?)? in
            guard let b = e.biomarkers else { return nil }
            return (e.timestamp, b, e.emotion)
        }.sorted { $0.0 < $1.0 }

        guard dated.count >= 10 else { return nil }

        return try await Task.detached(priority: .utility) {
            let splitIndex = dated.count / 2
            let early = Array(dated.prefix(splitIndex))
            let late = Array(dated.suffix(splitIndex))

            let metrics: [(BiomarkerMetric, KeyPath<VoiceBiomarkers, Double>)] = [
                (.speechRate, \.speechRate),
                (.hesitationRate, \.hesitationRate),
                (.vocalEnergy, \.vocalEnergy),
                (.pitchInstability, \.pitchInstability),
                (.jitter, \.jitter),
                (.shimmer, \.shimmer),
            ]

            var drifts: [CognitiveDrift] = []
            var trendShiftCount = 0

            for (metric, keyPath) in metrics {
                let earlyVals = early.map { $0.1[keyPath: keyPath] }
                let lateVals = late.map { $0.1[keyPath: keyPath] }

                guard earlyVals.count >= 3, lateVals.count >= 3 else { continue }

                let earlyMean = earlyVals.reduce(0, +) / Double(earlyVals.count)
                let lateMean = lateVals.reduce(0, +) / Double(lateVals.count)

                let earlyVar = earlyVals.map { ($0 - earlyMean) * ($0 - earlyMean) }.reduce(0, +) / Double(earlyVals.count)
                let lateVar = lateVals.map { ($0 - lateMean) * ($0 - lateMean) }.reduce(0, +) / Double(lateVals.count)

                let pooledStd = sqrt((earlyVar + lateVar) / 2)
                let delta = lateMean - earlyMean

                guard pooledStd > 0 else { continue }
                let effectSize = delta / pooledStd

                let direction: TrendDirection = effectSize > 0 ? .increasing : .decreasing
                if abs(effectSize) > 0.3 { trendShiftCount += 1 }

                let significance: DriftSignificance
                switch abs(effectSize) {
                case ..<0.3: significance = .none
                case ..<0.5: significance = .mild
                case ..<0.8: significance = .moderate
                case ..<1.2: significance = .significant
                default: significance = .critical
                }

                let emotionCorr = self.correlateWithEmotion(early: early, late: late, metric: keyPath)

                drifts.append(CognitiveDrift(
                    id: UUID().uuidString,
                    windowStart: early.first!.0,
                    windowEnd: late.last!.0,
                    metric: metric,
                    delta: delta,
                    meanEarly: earlyMean,
                    meanLate: lateMean,
                    direction: direction,
                    significance: significance,
                    correlation: emotionCorr,
                    detectedAt: Date().timeIntervalSince1970
                ))
            }

            let overallSig = drifts.map { $0.significance }.max() ?? .none

            var emotionalCorr: [EmotionType: Double] = [:]
            for drift in drifts {
                for (emotion, corr) in drift.correlation {
                    emotionalCorr[emotion, default: 0] += corr
                }
            }
            if !emotionalCorr.isEmpty {
                let count = Double(drifts.filter { !$0.correlation.isEmpty }.count)
                for (key, val) in emotionalCorr { emotionalCorr[key] = val / max(count, 1) }
            }

            // Gradual vs sudden
            let timeSpan = dated.last!.0 - dated.first!.0
            let avgDaysBetweenEntries = timeSpan / Double(dated.count)
            let hasSuddenShifts = drifts.contains { abs($0.delta) > 0.5 && avgDaysBetweenEntries < 7 }
            let driftType: DriftReport.DriftType = {
                if hasSuddenShifts && trendShiftCount >= 2 { return .mixed }
                if hasSuddenShifts { return .sudden }
                return .gradual
            }()

            let summary = self.generateSummary(drifts: drifts, type: driftType)

            return DriftReport(
                id: UUID().uuidString,
                overallSignificance: overallSig,
                drifts: drifts,
                trendShiftCount: trendShiftCount,
                emotionalCorrelation: emotionalCorr,
                gradualVsSudden: driftType,
                summary: summary,
                detectedAt: Date().timeIntervalSince1970
            )
        }.value
    }

    // MARK: - Emotion Correlation

    private static func correlateWithEmotion(early: [(TimeInterval, VoiceBiomarkers, EmotionalState?)],
                                              late: [(TimeInterval, VoiceBiomarkers, EmotionalState?)],
                                              metric: KeyPath<VoiceBiomarkers, Double>) -> [EmotionType: Double] {
        let all = early + late
        let withEmotion = all.compactMap { (_, bio, emotion) -> (Double, EmotionType)? in
            guard let e = emotion else { return nil }
            return (bio[keyPath: metric], e.primaryEmotion)
        }

        var grouped: [EmotionType: [Double]] = [:]
        for (val, emotion) in withEmotion {
            grouped[emotion, default: []].append(val)
        }

        let overallMean = withEmotion.map { $0.0 }.reduce(0, +) / Double(max(withEmotion.count, 1))
        var correlations: [EmotionType: Double] = [:]
        for (emotion, vals) in grouped where vals.count >= 2 {
            let emMean = vals.reduce(0, +) / Double(vals.count)
            correlations[emotion] = (emMean - overallMean) / max(overallMean, 0.001)
        }
        return correlations
    }

    // MARK: - Summary

    private func generateSummary(drifts: [CognitiveDrift], type: DriftReport.DriftType) -> String {
        let significant = drifts.filter { $0.significance >= .moderate }
        guard !significant.isEmpty else { return "No significant cognitive drift detected." }

        let metrics = significant.map { $0.metric.rawValue.lowercased() }.joined(separator: ", ")
        let typeDesc = type == .gradual ? "gradual" : type == .sudden ? "sudden" : "mixed gradual and sudden"

        return "\(typeDesc.capitalized) cognitive drift detected in \(significant.count) metrics: \(metrics)."
    }

    // MARK: - Drift-Based Patterns

    func detectDriftPatterns(in entries: [JournalEntry]) async throws -> [DetectedPattern] {
        guard let report = try await detectDrift(from: entries) else { return [] }
        guard report.overallSignificance >= .moderate else { return [] }

        var patterns: [DetectedPattern] = []

        if report.overallSignificance >= .significant {
            let severity = report.overallSignificance.score
            patterns.append(DetectedPattern(
                patternType: .cognitiveShift,
                severity: severity,
                title: "Significant Cognitive Drift",
                message: report.summary,
                firstDetected: report.detectedAt,
                lastDetected: report.detectedAt,
                occurrenceCount: report.trendShiftCount
            ))
        }

        for drift in report.drifts where drift.significance >= .moderate {
            let severity = drift.significance.score
            let direction = drift.direction == .increasing ? "increased" : "decreased"
            patterns.append(DetectedPattern(
                patternType: .cognitiveShift,
                severity: severity,
                title: "\(drift.metric.rawValue) Shift",
                message: "Your \(drift.metric.rawValue.lowercased()) has \(direction) by \(String(format: "%.2f", abs(drift.delta))).",
                firstDetected: drift.detectedAt,
                lastDetected: drift.detectedAt,
                occurrenceCount: 1
            ))
        }

        return patterns
    }
}
