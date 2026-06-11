import Foundation

struct CognitiveDrift: Identifiable, Codable, Sendable {
    let id: String
    let windowStart: TimeInterval
    let windowEnd: TimeInterval
    let metric: BiomarkerMetric
    let delta: Double
    let meanEarly: Double
    let meanLate: Double
    let direction: TrendDirection
    let significance: DriftSignificance
    let correlation: [EmotionType: Double]
    let detectedAt: TimeInterval

    var description: String {
        let dir = direction == .increasing ? "increased" : "decreased"
        return "\(metric.rawValue) \(dir) by \(String(format: "%.2f", abs(delta)))"
    }
}

enum DriftSignificance: String, Codable, Comparable {
    case none
    case mild
    case moderate
    case significant
    case critical

    var score: Int {
        switch self {
        case .none: return 0
        case .mild: return 25
        case .moderate: return 50
        case .significant: return 75
        case .critical: return 95
        }
    }

    static func < (lhs: DriftSignificance, rhs: DriftSignificance) -> Bool {
        lhs.score < rhs.score
    }
}

struct DriftReport: Codable, Sendable {
    let id: String
    let overallSignificance: DriftSignificance
    let drifts: [CognitiveDrift]
    let trendShiftCount: Int
    let emotionalCorrelation: [EmotionType: Double]
    let gradualVsSudden: DriftType
    let summary: String
    let detectedAt: TimeInterval

    enum DriftType: String, Codable {
        case gradual
        case sudden
        case mixed
    }
}

struct DailyPattern: Codable, Sendable {
    let metric: String
    let morningAvg: Double
    let afternoonAvg: Double
    let eveningAvg: Double
    let nightAvg: Double
    let morningSampleCount: Int
    let afternoonSampleCount: Int
    let eveningSampleCount: Int
    let nightSampleCount: Int
    let hasSignificantPattern: Bool

    var peakPeriod: String {
        let vals = [(morningAvg, "morning"), (afternoonAvg, "afternoon"),
                    (eveningAvg, "evening"), (nightAvg, "night")]
        return vals.max { $0.0 < $1.0 }?.1 ?? "unknown"
    }

    var troughPeriod: String {
        let vals = [(morningAvg, "morning"), (afternoonAvg, "afternoon"),
                    (eveningAvg, "evening"), (nightAvg, "night")]
        return vals.min { $0.0 < $1.0 }?.1 ?? "unknown"
    }
}
