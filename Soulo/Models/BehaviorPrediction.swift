import Foundation

struct BehaviorPrediction: Identifiable, Codable, Sendable {
    let id: String
    let type: PredictionType
    let prediction: String
    let probability: Double
    let confidence: PredictionConfidence
    let basedOn: [String]
    let validUntil: TimeInterval
    let createdAt: TimeInterval

    enum PredictionType: String, Codable, CaseIterable {
        case journalFrequency
        case sentimentTrajectory
        case goalCompletion
        case nextEmotion
        case abandonmentRisk
        case emotionalCrisis

        var displayName: String {
            switch self {
            case .journalFrequency: return "Journaling Frequency"
            case .sentimentTrajectory: return "Sentiment Trend"
            case .goalCompletion: return "Goal Completion"
            case .nextEmotion: return "Likely Emotion"
            case .abandonmentRisk: return "Abandonment Risk"
            case .emotionalCrisis: return "Emotional Crisis Risk"
            }
        }
    }

    enum PredictionConfidence: String, Codable {
        case low
        case moderate
        case high
        case veryHigh

        var score: Double {
            switch self {
            case .low: return 0.25
            case .moderate: return 0.5
            case .high: return 0.75
            case .veryHigh: return 0.9
            }
        }
    }
}

struct PredictionSummary: Codable, Sendable {
    let predictions: [BehaviorPrediction]
    let topRisk: BehaviorPrediction?
    let topOpportunity: BehaviorPrediction?
    let overallWellbeingTrend: TrendDirection
    let projectionDays: Int
}
