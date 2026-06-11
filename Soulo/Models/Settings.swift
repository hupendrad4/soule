import Foundation

struct AppSettings: Codable {
    var dailyReminderTime: String = "20:00"
    var dailyReminderEnabled: Bool = true
    var insightSeverityThreshold: Int = 50
    var darkMode: Bool = true
    var biometricLock: Bool = true
    var backupEnabled: Bool = false
    var backupFrequency: BackupFrequency = .weekly
    var exportIncludeAudio: Bool = false
    var onboardingCompleted: Bool = false
    var entriesUntilPaywall: Int = 7
    var subscriptionStatus: String = "free"

    static let `default` = AppSettings()
}

enum BackupFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}
