import Foundation

struct VoiceBiomarkers: Codable, Sendable {
    var speechRate: Double
    var hesitationRate: Double
    var vocalEnergy: Double
    var pitchInstability: Double
    var microBreathCount: Int
    var jitter: Double
    var shimmer: Double

    init(
        speechRate: Double = 0,
        hesitationRate: Double = 0,
        vocalEnergy: Double = 0,
        pitchInstability: Double = 0,
        microBreathCount: Int = 0,
        jitter: Double = 0,
        shimmer: Double = 0
    ) {
        self.speechRate = speechRate
        self.hesitationRate = hesitationRate
        self.vocalEnergy = vocalEnergy
        self.pitchInstability = pitchInstability
        self.microBreathCount = microBreathCount
        self.jitter = jitter
        self.shimmer = shimmer
    }
}

struct UserBaseline: Codable {
    let metric: String
    let mean: Double
    let stddev: Double
    let min: Double
    let max: Double
    let p5: Double
    let p25: Double
    let p75: Double
    let p95: Double
    let sampleCount: Int
    let lastUpdated: TimeInterval

    func zScore(for value: Double) -> Double {
        guard stddev > 0 else { return 0 }
        return (value - mean) / stddev
    }

    func isAnomaly(_ value: Double, threshold: Double = 2.0) -> Bool {
        return abs(zScore(for: value)) > threshold
    }

    func percentileRank(for value: Double) -> Double {
        if value <= min { return 0 }
        if value >= max { return 1 }
        if value <= p25 { return 0.25 * (value - min) / max(p25 - min, 0.001) }
        if value <= p75 { return 0.25 + 0.5 * (value - p25) / max(p75 - p25, 0.001) }
        return 0.75 + 0.25 * (value - p75) / max(max - p75, 0.001)
    }

    var range: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        let lo = formatter.string(from: NSNumber(value: p5)) ?? "0"
        let hi = formatter.string(from: NSNumber(value: p95)) ?? "0"
        return "\(lo) – \(hi)"
    }
}

struct BiomarkerTrend: Codable {
    let metric: BiomarkerMetric
    let values7Day: [Double]
    let values30Day: [Double]
    let slope7Day: Double
    let slope30Day: Double
    let direction: TrendDirection

    var isSignificant: Bool { abs(slope7Day) > 0.05 || abs(slope30Day) > 0.03 }
}

enum BiomarkerMetric: String, Codable, CaseIterable {
    case speechRate = "Speech Rate"
    case hesitationRate = "Hesitations"
    case vocalEnergy = "Vocal Energy"
    case pitchInstability = "Pitch Instability"
    case microBreathCount = "Micro-Breaths"
    case jitter = "Jitter"
    case shimmer = "Shimmer"

    var unit: String {
        switch self {
        case .speechRate: return "wps"
        case .hesitationRate: return "%"
        case .vocalEnergy: return ""
        case .pitchInstability: return "%"
        case .microBreathCount: return "count"
        case .jitter: return "%"
        case .shimmer: return "%"
        }
    }

    var icon: String {
        switch self {
        case .speechRate: return "speaker.wave.2"
        case .hesitationRate: return "pause"
        case .vocalEnergy: return "bolt"
        case .pitchInstability: return "waveform.path.ecg"
        case .microBreathCount: return "lungs"
        case .jitter: return "waveform"
        case .shimmer: return "sparkles"
        }
    }
}

enum TrendDirection: String, Codable {
    case increasing, decreasing, stable

    var icon: String {
        switch self {
        case .increasing: return "arrow.up"
        case .decreasing: return "arrow.down"
        case .stable: return "minus"
        }
    }

    var color: String {
        switch self {
        case .increasing: return "orange"
        case .decreasing: return "blue"
        case .stable: return "gray"
        }
    }
}
