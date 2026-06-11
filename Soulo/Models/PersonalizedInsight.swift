import Foundation

struct InsightEngagement: Codable, Sendable {
    let insightType: String
    var impressionCount: Int
    var expandCount: Int
    var dismissCount: Int
    var averageRelevanceScore: Double

    var engagementRate: Double {
        guard impressionCount > 0 else { return 0 }
        return Double(expandCount + dismissCount) / Double(impressionCount)
    }

    var netPositive: Bool {
        expandCount > dismissCount
    }
}

struct UserInsightProfile: Codable, Sendable {
    var preferredTypes: [String]
    var preferredTimeHour: Int
    var sensitivityLevel: Int
    var streakPhase: StreakPhase
    var recentEngagements: [InsightEngagement]
    var lastUpdated: TimeInterval

    enum StreakPhase: String, Codable {
        case cold
        case building
        case maintaining
        case thriving

        var minStreak: Int {
            switch self {
            case .cold: return 0
            case .building: return 3
            case .maintaining: return 7
            case .thriving: return 21
            }
        }
    }
}

struct RankedInsight: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let body: String
    let category: String
    let baseScore: Int
    let personalizationBoost: Int
    let finalScore: Int
    let reason: String

    var isPersonalized: Bool { personalizationBoost > 0 }
}
