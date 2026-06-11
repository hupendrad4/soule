import Foundation

final class BaselineService: Sendable {
    static let shared = BaselineService()

    private init() {}

    // MARK: - Standard Baseline

    func computeBaselines(from entries: [JournalEntry]) async throws -> [UserBaseline] {
        let biomarkers = entries.compactMap { $0.biomarkers }
        guard biomarkers.count >= 3 else { return [] }

        return try await Task.detached(priority: .utility) {
            let metrics: [(String, KeyPath<VoiceBiomarkers, Double>)] = [
                ("speechRate", \.speechRate),
                ("hesitationRate", \.hesitationRate),
                ("vocalEnergy", \.vocalEnergy),
                ("pitchInstability", \.pitchInstability),
                ("jitter", \.jitter),
                ("shimmer", \.shimmer),
                ("microBreathCount", \.microBreathCount),
            ]

            return metrics.compactMap { name, keyPath -> UserBaseline? in
                let values = biomarkers.map { $0[keyPath: keyPath] }
                return Self.computeBaseline(for: name, values: values)
            }
        }.value
    }

    static func computeBaseline(for metric: String, values: [Double]) -> UserBaseline? {
        guard values.count >= 3 else { return nil }
        let sorted = values.sorted()
        let n = sorted.count

        let mean = sorted.reduce(0, +) / Double(n)
        let variance = sorted.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(n)
        let stddev = sqrt(variance)

        return UserBaseline(
            metric: metric,
            mean: mean,
            stddev: stddev,
            min: sorted.first!,
            max: sorted.last!,
            p5: sorted[max(0, Int(Double(n) * 0.05))],
            p25: sorted[max(0, Int(Double(n) * 0.25))],
            p75: sorted[min(n - 1, Int(Double(n) * 0.75))],
            p95: sorted[min(n - 1, Int(Double(n) * 0.95))],
            sampleCount: n,
            lastUpdated: Date().timeIntervalSince1970
        )
    }

    // MARK: - 30-Day Finalized Baseline

    struct FinalizedBaseline: Codable, Sendable {
        let baselines: [UserBaseline]
        let isMature: Bool
        let daysOfData: Int
        let stabilityScore: Double
        let dailyPatterns: [DailyPattern]
        let lastUpdated: TimeInterval

        var isStable: Bool { stabilityScore > 0.7 && isMature }
    }

    func computeFinalizedBaseline(from entries: [JournalEntry]) async throws -> FinalizedBaseline? {
        guard entries.count >= 5 else { return nil }
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let daysSpan = max(1, Int((sorted.last!.timestamp - sorted.first!.timestamp) / 86400))

        let baselines = try await computeBaselines(from: entries)

        // Stability: compare first half vs second half baselines
        let mid = entries.count / 2
        let earlyEntries = Array(entries.prefix(mid))
        let lateEntries = Array(entries.suffix(mid))
        let earlyBaselines = try await computeBaselines(from: earlyEntries)
        let lateBaselines = try await computeBaselines(from: lateEntries)

        var stabilitySum = 0.0
        var stabilityCount = 0
        for early in earlyBaselines {
            guard let late = lateBaselines.first(where: { $0.metric == early.metric }) else { continue }
            let delta = abs(early.mean - late.mean) / max(early.stddev, 0.001)
            stabilitySum += max(0, 1.0 - min(delta, 1.0))
            stabilityCount += 1
        }
        let stabilityScore = stabilityCount > 0 ? stabilitySum / Double(stabilityCount) : 0.5

        let dailyPatterns = computeDailyPatterns(from: sorted)

        return FinalizedBaseline(
            baselines: baselines,
            isMature: daysSpan >= 30 && entries.count >= 20,
            daysOfData: daysSpan,
            stabilityScore: stabilityScore,
            dailyPatterns: dailyPatterns,
            lastUpdated: Date().timeIntervalSince1970
        )
    }

    // MARK: - Daily Patterns

    func computeDailyPatterns(from entries: [JournalEntry]) -> [DailyPattern] {
        let metrics: [(String, KeyPath<VoiceBiomarkers, Double>)] = [
            ("speechRate", \.speechRate),
            ("hesitationRate", \.hesitationRate),
            ("vocalEnergy", \.vocalEnergy),
            ("pitchInstability", \.pitchInstability),
        ]

        return metrics.compactMap { name, keyPath -> DailyPattern? in
            var morning: [Double] = []
            var afternoon: [Double] = []
            var evening: [Double] = []
            var night: [Double] = []

            for entry in entries {
                guard let b = entry.biomarkers else { continue }
                let hour = Date(timeIntervalSince1970: entry.timestamp).hourValue
                let val = b[keyPath: keyPath]
                switch hour {
                case 5..<12: morning.append(val)
                case 12..<17: afternoon.append(val)
                case 17..<22: evening.append(val)
                default: night.append(val)
                }
            }

            let avg: ([Double]) -> Double = { vals in
                vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
            }

            let m = avg(morning), a = avg(afternoon), e = avg(evening), n = avg(night)
            let all = [m, a, e, n].filter { $0 != 0 }
            let overall = all.isEmpty ? 0 : all.reduce(0, +) / Double(all.count)
            let hasSig = !all.isEmpty && all.contains { abs($0 - overall) > overall * 0.15 }

            return DailyPattern(
                metric: name,
                morningAvg: m, afternoonAvg: a, eveningAvg: e, nightAvg: n,
                morningSampleCount: morning.count,
                afternoonSampleCount: afternoon.count,
                eveningSampleCount: evening.count,
                nightSampleCount: night.count,
                hasSignificantPattern: hasSig && morning.count + afternoon.count + evening.count + night.count >= 10
            )
        }
    }

    // MARK: - Anomaly Detection

    func detectAnomalies(entry: JournalEntry, baselines: [UserBaseline]) -> [BiomarkerAnomaly] {
        guard let biomarkers = entry.biomarkers else { return [] }

        let checks: [(String, Double)] = [
            ("speechRate", biomarkers.speechRate),
            ("hesitationRate", biomarkers.hesitationRate),
            ("vocalEnergy", biomarkers.vocalEnergy),
            ("pitchInstability", biomarkers.pitchInstability),
            ("jitter", biomarkers.jitter),
            ("shimmer", biomarkers.shimmer),
        ]

        var anomalies: [BiomarkerAnomaly] = []
        for (metric, value) in checks {
            guard let baseline = baselines.first(where: { $0.metric == metric }) else { continue }
            let z = baseline.zScore(for: value)
            if abs(z) > 2.0 {
                anomalies.append(BiomarkerAnomaly(
                    metric: metric,
                    value: value,
                    zScore: z,
                    percentileRank: baseline.percentileRank(for: value),
                    direction: z > 0 ? .above : .below
                ))
            }
        }
        return anomalies
    }

    // MARK: - Weighted Baseline (newer entries matter more)

    func computeWeightedBaseline(from entries: [JournalEntry]) -> [UserBaseline] {
        let dated = entries.compactMap { e -> (TimeInterval, VoiceBiomarkers)? in
            guard let b = e.biomarkers else { return nil }
            return (e.timestamp, b)
        }.sorted { $0.0 < $1.0 }

        guard dated.count >= 3 else { return [] }

        let now = Date().timeIntervalSince1970
        let oldest = dated.first!.0
        let span = max(86400, now - oldest)

        let metrics: [(String, KeyPath<VoiceBiomarkers, Double>)] = [
            ("speechRate", \.speechRate),
            ("hesitationRate", \.hesitationRate),
            ("vocalEnergy", \.vocalEnergy),
            ("pitchInstability", \.pitchInstability),
            ("jitter", \.jitter),
            ("shimmer", \.shimmer),
            ("microBreathCount", \.microBreathCount),
        ]

        return metrics.compactMap { name, keyPath -> UserBaseline? in
            var weightedSum = 0.0
            var weightSum = 0.0
            var values: [Double] = []

            for (timestamp, bio) in dated {
                let age = (now - timestamp) / span
                let weight = exp(-age * 3)
                let val = bio[keyPath: keyPath]
                weightedSum += val * weight
                weightSum += weight
                values.append(val)
            }

            guard weightSum > 0, values.count >= 3 else { return nil }
            let mean = weightedSum / weightSum
            let sorted = values.sorted()
            let n = sorted.count

            let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(n)
            let stddev = sqrt(variance)

            return UserBaseline(
                metric: name,
                mean: mean,
                stddev: stddev,
                min: sorted.first!,
                max: sorted.last!,
                p5: sorted[max(0, Int(Double(n) * 0.05))],
                p25: sorted[max(0, Int(Double(n) * 0.25))],
                p75: sorted[min(n - 1, Int(Double(n) * 0.75))],
                p95: sorted[min(n - 1, Int(Double(n) * 0.95))],
                sampleCount: n,
                lastUpdated: Date().timeIntervalSince1970
            )
        }
    }
}
