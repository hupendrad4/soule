import Foundation

struct SubscriptionInfo: Codable {
    var status: SubscriptionStatus
    var planType: SubscriptionPlan?
    var originalId: String?
    var currentId: String?
    var expiresAt: TimeInterval?
    var autoRenew: Bool
    var trialStart: TimeInterval?
    var trialEnd: TimeInterval?
    var updatedAt: TimeInterval

    static let `default` = SubscriptionInfo(
        status: .free,
        autoRenew: false,
        updatedAt: Date().timeIntervalSince1970
    )

    var isActive: Bool {
        switch status {
        case .active, .trial: return true
        case .free, .expired, .cancelled: return false
        }
    }
}

enum SubscriptionPlan: String, Codable {
    case monthly = "soulo_monthly"
    case annual = "soulo_annual"
    case family = "soulo_family"

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        case .family: return "Family"
        }
    }

    var price: String {
        switch self {
        case .monthly: return "$9.99/month"
        case .annual: return "$79.99/year"
        case .family: return "$14.99/month"
        }
    }

    var monthlyPrice: Double {
        switch self {
        case .monthly: return 9.99
        case .annual: return 6.67
        case .family: return 14.99
        }
    }
}
