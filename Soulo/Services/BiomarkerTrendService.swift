import Foundation

final class BiomarkerTrendService: Sendable {
    static let shared = BiomarkerTrendService()

    private init() {}

    func computeTrends(from entries: [JournalEntry]) async throws -> [BiomarkerTrend] {
        let dated = entries
            .compactMap { entry -> (Date, VoiceBiomarkers)? in
                guard let b = entry.biomarkers else { return nil }
                return (Date(timeIntervalSince1970: entry.timestamp), b)
            }
            .sorted { $0.0 < $1.0 }

        guard dated.count >= 3 else { return [] }

        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-86400 * 7)
        let thirtyDaysAgo = now.addingTimeInterval(-86400 * 30)

        return try await Task.detached(priority: .utility) {
            let extractors: [(BiomarkerMetric, (VoiceBiomarkers) -> Double)] = [
                (.speechRate, { $0.speechRate }),
                (.hesitationRate, { $0.hesitationRate }),
                (.vocalEnergy, { $0.vocalEnergy }),
                (.pitchInstability, { $0.pitchInstability }),
                (.microBreathCount, { Double($0.microBreathCount) }),
                (.jitter, { $0.jitter }),
                (.shimmer, { $0.shimmer }),
            ]

            return extractors.compactMap { metric, extractor -> BiomarkerTrend? in
                let all = dated.map { extractor($0.1) }
                let recent7 = dated.filter { $0.0 >= sevenDaysAgo }.map { extractor($0.1) }
                let recent30 = dated.filter { $0.0 >= thirtyDaysAgo }.map { extractor($0.1) }

                let slope7 = recent7.count >= 3 ? Self.computeSlope(recent7) : 0
                let slope30 = recent30.count >= 5 ? Self.computeSlope(recent30) : 0

                let direction: TrendDirection = {
                    if abs(slope7) < 0.03 && abs(slope30) < 0.02 { return .stable }
                    let primary = abs(slope7) >= 0.05 ? slope7 : slope30
                    return primary > 0 ? .increasing : .decreasing
                }()

                return BiomarkerTrend(
                    metric: metric,
                    values7Day: recent7,
                    values30Day: recent30,
                    slope7Day: slope7,
                    slope30Day: slope30,
                    direction: direction
                )
            }
        }.value
    }

    static func computeSlope(_ values: [Double]) -> Double {
        let n = Double(values.count)
        let sumX = (0..<values.count).reduce(0, +)
        let sumY = values.reduce(0, +)
        let sumXY = values.enumerated().map { Double($0.offset) * $0.element }.reduce(0, +)
        let sumX2 = (0..<values.count).map { Double($0 * $0) }.reduce(0, +)
        return (n * sumXY - Double(sumX) * sumY) / (n * sumX2 - Double(sumX) * Double(sumX))
    }

    static func rollingAverage(_ values: [Double], window: Int) -> [Double] {
        guard values.count >= window else { return values }
        var result: [Double] = []
        for i in 0...(values.count - window) {
            let avg = values[i..<i + window].reduce(0, +) / Double(window)
            result.append(avg)
        }
        return result
    }
}
