import Foundation

struct JournalDecision: Identifiable, Codable, Sendable {
    let id: String
    let entryId: String
    let decisionText: String
    let category: String?
    let expectedOutcome: String?
    var status: DecisionStatus
    var followUpEntryId: String?
    var followUpSentiment: Double?
    var followUpText: String?
    let firstMentioned: TimeInterval
    var lastMentioned: TimeInterval
    var mentionCount: Int
    let createdAt: TimeInterval

    init(
        id: String = UUID().uuidString,
        entryId: String,
        decisionText: String,
        category: String? = nil,
        expectedOutcome: String? = nil,
        status: DecisionStatus = .active,
        firstMentioned: TimeInterval = Date().timeIntervalSince1970,
        lastMentioned: TimeInterval = Date().timeIntervalSince1970,
        mentionCount: Int = 1
    ) {
        self.id = id
        self.entryId = entryId
        self.decisionText = decisionText
        self.category = category
        self.expectedOutcome = expectedOutcome
        self.status = status
        self.firstMentioned = firstMentioned
        self.lastMentioned = lastMentioned
        self.mentionCount = mentionCount
        self.createdAt = Date().timeIntervalSince1970
    }

    var daysSinceDecision: Int {
        max(0, Int((Date().timeIntervalSince1970 - firstMentioned) / 86400))
    }

    var isOverdue: Bool {
        status == .active && daysSinceDecision > 14
    }
}

enum DecisionStatus: String, Codable, CaseIterable {
    case active
    case kept
    case regretted
    case abandoned
    case pending

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .kept: return "Kept"
        case .regretted: return "Regretted"
        case .abandoned: return "Abandoned"
        case .pending: return "Pending Outcome"
        }
    }
}

struct DecisionOutcome: Codable, Sendable {
    let decisionId: String
    let outcomeStatus: DecisionStatus
    let sentimentAtOutcome: Double
    let timeToOutcome: Int
    let outcomeSummary: String
}
