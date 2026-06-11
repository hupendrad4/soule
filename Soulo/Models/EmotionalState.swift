import Foundation

struct EmotionalState: Codable, Sendable {
    let primaryEmotion: EmotionType
    let confidence: Double
    let valence: Double
    let arousal: Double
    let allProbabilities: [String: Double]

    init(
        primaryEmotion: EmotionType,
        confidence: Double = 0,
        valence: Double = 0,
        arousal: Double = 0,
        allProbabilities: [String: Double] = [:]
    ) {
        self.primaryEmotion = primaryEmotion
        self.confidence = confidence
        self.valence = valence
        self.arousal = arousal
        self.allProbabilities = allProbabilities
    }
}

enum EmotionType: String, Codable, CaseIterable {
    case neutral = "neutral"
    case joy = "joy"
    case sadness = "sadness"
    case anger = "anger"
    case fear = "fear"
    case surprise = "surprise"
    case disgust = "disgust"
    case anxiety = "anxiety"
    case frustration = "frustration"
    case hope = "hope"
    case gratitude = "gratitude"
    case loneliness = "loneliness"

    var displayName: String { rawValue.capitalized }

    var color: String {
        switch self {
        case .joy: return "yellow"
        case .sadness: return "blue"
        case .anger: return "red"
        case .fear: return "purple"
        case .surprise: return "orange"
        case .disgust: return "green"
        case .neutral: return "gray"
        case .anxiety: return "indigo"
        case .frustration: return "orange"
        case .hope: return "teal"
        case .gratitude: return "pink"
        case .loneliness: return "mint"
        }
    }
}
