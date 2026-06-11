import Foundation

struct InsightPrefs: Codable, Sendable {
    var enabled: Bool
    var hour: Int
    var minute: Int
    var types: [InsightType]

    static let `default` = InsightPrefs(
        enabled: true,
        hour: 7,
        minute: 30,
        types: InsightType.allCases
    )
}

enum InsightType: String, Codable, CaseIterable {
    case pattern
    case milestone
    case improvement
    case warning
    case encouragement
    case trend

    var displayName: String {
        switch self {
        case .pattern: return "Pattern Alerts"
        case .milestone: return "Milestones"
        case .improvement: return "Improvements"
        case .warning: return "Warnings"
        case .encouragement: return "Encouragement"
        case .trend: return "Trend Updates"
        }
    }
}
