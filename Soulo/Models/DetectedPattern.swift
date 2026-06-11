import Foundation

struct DetectedPattern: Identifiable, Codable, Sendable {
    let id: String
    var patternType: PatternType
    var severity: Int
    var title: String
    var message: String
    var dataJson: String?
    var firstDetected: TimeInterval
    var lastDetected: TimeInterval
    var occurrenceCount: Int
    var dismissed: Bool
    var createdAt: TimeInterval
    var updatedAt: TimeInterval

    init(
        id: String = UUID().uuidString,
        patternType: PatternType,
        severity: Int,
        title: String,
        message: String,
        dataJson: String? = nil,
        firstDetected: TimeInterval = Date().timeIntervalSince1970,
        lastDetected: TimeInterval = Date().timeIntervalSince1970,
        occurrenceCount: Int = 1
    ) {
        self.id = id
        self.patternType = patternType
        self.severity = severity
        self.title = title
        self.message = message
        self.dataJson = dataJson
        self.firstDetected = firstDetected
        self.lastDetected = lastDetected
        self.occurrenceCount = occurrenceCount
        self.dismissed = false
        self.createdAt = Date().timeIntervalSince1970
        self.updatedAt = Date().timeIntervalSince1970
    }
}

enum PatternType: String, Codable, CaseIterable {
    case brokenPromise
    case topicAvoidance
    case sentimentDecline
    case goalAbandonment
    case contradiction
    case cognitiveShift
    case relationshipPattern
    case decisionRegret

    var displayName: String {
        switch self {
        case .brokenPromise: return "Broken Promise"
        case .topicAvoidance: return "Topic Avoidance"
        case .sentimentDecline: return "Declining Sentiment"
        case .goalAbandonment: return "Goal Abandonment"
        case .contradiction: return "Contradiction"
        case .cognitiveShift: return "Cognitive Shift"
        case .relationshipPattern: return "Relationship Pattern"
        case .decisionRegret: return "Decision Regret"
        }
    }

    var icon: String {
        switch self {
        case .brokenPromise: return "hand.raised.slash"
        case .topicAvoidance: return "arrow.turn.down.left"
        case .sentimentDecline: return "arrow.down.right"
        case .goalAbandonment: return "flag.slash"
        case .contradiction: return "arrow.left.arrow.right"
        case .cognitiveShift: return "brain"
        case .relationshipPattern: return "person.2"
        case .decisionRegret: return "arrow.uturn.backward"
        }
    }
}

struct PatternEvidence: Codable {
    let patternId: String
    let entryId: String
    let relevance: Double
    let createdAt: TimeInterval
}
