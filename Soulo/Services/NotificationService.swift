import Foundation
import UserNotifications

final class NotificationService: Sendable {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    var isAuthorized: Bool {
        get async {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleDailyReminder(at hour: Int = 20, minute: Int = 0) async {
        center.removePendingNotificationRequests(withIdentifiers: ["daily_journal"])

        let content = UNMutableNotificationContent()
        content.title = "Soulo"
        content.body = randomPrompt()
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_journal", content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            Logger.shared.error("Notifications", "Failed to schedule: \(error.localizedDescription)")
        }
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: ["daily_journal"])
    }

    func scheduleStreakNotification(days: Int) {
        guard days > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "🔥 \(days)-Day Streak!"
        content.body = streakMessage(for: days)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "streak_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)

        Task {
            try? await center.add(request)
        }
    }

    private func randomPrompt() -> String {
        let prompts = [
            "It's been a while. What's on your mind today?",
            "How are you feeling right now? Take a moment to reflect.",
            "What was the best part of your day?",
            "Is there something you've been avoiding thinking about?",
            "What would you like to remember about today?",
            "How are things going with the people close to you?",
            "What's one thing you wish you'd done differently today?",
            "Describe a moment today that made you feel something.",
            "What are you looking forward to tomorrow?",
            "Is there a thought that keeps coming back to you?"
        ]
        return prompts.randomElement() ?? prompts[0]
    }

    private func streakMessage(for days: Int) -> String {
        switch days {
        case 1: return "You started your journaling journey! First entry done."
        case 2: return "Two days in a row! You're building a habit."
        case 3: return "3-day streak! Patterns start to emerge at this point."
        case 5: return "5 days! You're in the top 10% of journal keepers."
        case 7: return "One week! You now have enough data for your first insights."
        case 10: return "10 days! Your baseline is becoming meaningful."
        case 14: return "Two weeks! You're building serious self-awareness."
        case 21: return "21 days! They say that's how long it takes to form a habit."
        case 30: return "30 days! You have a month of self-reflection. Incredible."
        case 50: return "50 entries! You're more self-aware than most people."
        case 100: return "100 entries! This is a genuine commitment to yourself."
        default: return "You've journaled \(days) times. Keep the momentum going!"
        }
    }
}
