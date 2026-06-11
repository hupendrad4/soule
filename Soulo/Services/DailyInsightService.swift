import Foundation
import UserNotifications

final class DailyInsightService: Sendable {
    static let shared = DailyInsightService()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Insight Generation

    struct DailyInsight: Sendable {
        let title: String
        let body: String
        let category: InsightCategory
        let relevanceScore: Int

        enum InsightCategory: String, Sendable {
            case pattern
            case milestone
            case improvement
            case warning
            case encouragement
            case trend
        }
    }

    func generateBestInsight(entries: [JournalEntry], patterns: [DetectedPattern],
                             topicTrends: [TopicTrend], decisionDecisions: [JournalDecision]) -> DailyInsight? {
        guard entries.count >= 3 else {
            return DailyInsight(
                title: "Start Your Journey",
                body: "Record 3 entries to unlock personalized insights about your patterns and growth.",
                category: .encouragement,
                relevanceScore: 10
            )
        }

        let candidates: [DailyInsight] = [
            patternInsight(patterns: patterns),
            streakMilestone(entries: entries),
            improvementInsight(topicTrends: topicTrends),
            warningInsight(topicTrends: topicTrends, patterns: patterns),
            decisionInsight(decisions: decisionDecisions),
            emotionTrendInsight(entries: entries),
            consistencyInsight(entries: entries),
            reflectionPrompt(entries: entries)
        ].compactMap { $0 }

        return candidates.sorted { $0.relevanceScore > $1.relevanceScore }.first
    }

    // MARK: - Specific Insight Generators

    private func patternInsight(patterns: [DetectedPattern]) -> DailyInsight? {
        let active = patterns.filter { !$0.dismissed && $0.severity >= 40 }
        guard let top = active.sorted(by: { $0.severity > $1.severity }).first else { return nil }
        return DailyInsight(
            title: "Pattern: \(top.title)",
            body: top.message,
            category: .pattern,
            relevanceScore: top.severity
        )
    }

    private func streakMilestone(entries: [JournalEntry]) -> DailyInsight? {
        let cal = Calendar.current
        var streak = 0
        var day = cal.startOfDay(for: Date())
        let entryDays = Set(entries.map { cal.startOfDay(for: Date(timeIntervalSince1970: $0.timestamp)) })
        while entryDays.contains(day) { streak += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }

        let milestones = [1, 3, 7, 14, 21, 30, 50, 100]
        guard let next = milestones.first(where: { $0 > streak - 1 }) else {
            return streak >= 100 ? DailyInsight(
                title: "\(streak)-Day Streak!",
                body: "You're a journaling legend. Keep showing up for yourself every day.",
                category: .milestone,
                relevanceScore: 80
            ) : nil
        }

        let remaining = next - streak
        if remaining <= 3 && remaining > 0 {
            return DailyInsight(
                title: "\(next)-Day Streak Approaching",
                body: "Journal today to hit \(remaining == 1 ? "your" : "\(remaining) more") \(remaining > 1 ? "days toward your " : "")\(next)-day milestone!",
                category: .milestone,
                relevanceScore: 70 - (remaining * 5)
            )
        }
        return nil
    }

    private func improvementInsight(topicTrends: [TopicTrend]) -> DailyInsight? {
        let improving = topicTrends.filter { $0.sentimentSlope > 0.1 && $0.mentionCount >= 3 }
        guard let top = improving.sorted(by: { $0.sentimentSlope > $1.sentimentSlope }).first else { return nil }
        return DailyInsight(
            title: "Improving Sentiment: \(top.topic)",
            body: "Your feelings about \(top.topic) are trending positive (\(String(format: "%.1f", top.sentimentSlope)) per mention). This is real progress.",
            category: .improvement,
            relevanceScore: 60 + Int(top.sentimentSlope * 50)
        )
    }

    private func warningInsight(topicTrends: [TopicTrend], patterns: [DetectedPattern]) -> DailyInsight? {
        let declining = topicTrends.filter { $0.sentimentSlope < -0.1 && $0.mentionCount >= 3 }
        let topDecline = declining.sorted(by: { $0.sentimentSlope < $1.sentimentSlope }).first

        let severePattern = patterns.first { $0.severity >= 70 && !$0.dismissed }

        if let severe = severePattern {
            return DailyInsight(
                title: "⚠️ Significant: \(severe.title)",
                body: severe.message,
                category: .warning,
                relevanceScore: severe.severity + 10
            )
        }

        if let decline = topDecline {
            return DailyInsight(
                title: "Declining: \(decline.topic)",
                body: "Your sentiment about \(decline.topic) is dropping. Worth checking in with yourself on why.",
                category: .warning,
                relevanceScore: 50 + Int(abs(decline.sentimentSlope) * 50)
            )
        }

        return nil
    }

    private func decisionInsight(decisions: [JournalDecision]) -> DailyInsight? {
        let pending = decisions.filter { $0.status == .pending }
        let recentRegret = decisions.filter { $0.status == .regretted && $0.lastMentioned > Date().timeIntervalSince1970 - 86400 * 7 }

        if let regret = recentRegret.sorted(by: { $0.lastMentioned > $1.lastMentioned }).first {
            return DailyInsight(
                title: "Recent Decision Regret",
                body: "You expressed regret about '\(regret.decisionText.prefix(60))'. What would you do differently now?",
                category: .pattern,
                relevanceScore: 65
            )
        }

        if let active = pending.sorted(by: { $0.daysSinceDecision > $1.daysSinceDecision }).first, active.daysSinceDecision > 7 {
            return DailyInsight(
                title: "Pending Decision Check-In",
                body: "\(active.daysSinceDecision) days ago you decided: '\(active.decisionText.prefix(60))'. How's that going?",
                category: .trend,
                relevanceScore: 40 + min(active.daysSinceDecision, 30)
            )
        }

        return nil
    }

    private func emotionTrendInsight(entries: [JournalEntry]) -> DailyInsight? {
        let withEmotion = entries.compactMap { e -> (Date: TimeInterval, valence: Double)? in
            guard let em = e.emotion else { return nil }
            return (e.timestamp, em.valence)
        }.sorted { $0.Date < $1.Date }

        guard withEmotion.count >= 5 else { return nil }

        let recent = withEmotion.suffix(5)
        let recentAvg = recent.map { $0.valence }.reduce(0, +) / Double(recent.count)
        let earlier = withEmotion.prefix(5)
        let earlierAvg = earlier.map { $0.valence }.reduce(0, +) / Double(earlier.count)

        let delta = recentAvg - earlierAvg

        if delta > 0.3 {
            return DailyInsight(
                title: "Mood Improving",
                body: "Your emotional valence has risen \(String(format: "%.1f", delta)) points recently. Things are looking up!",
                category: .improvement,
                relevanceScore: 55
            )
        }
        if delta < -0.3 {
            return DailyInsight(
                title: "Mood Declining",
                body: "Your emotional valence has dropped \(String(format: "%.1f", abs(delta))) points. Consider what might be weighing on you.",
                category: .warning,
                relevanceScore: 60
            )
        }
        return nil
    }

    private func consistencyInsight(entries: [JournalEntry]) -> DailyInsight? {
        guard entries.count >= 7 else { return nil }
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        let gaps = sorted.enumerated().dropFirst().map { i, entry in
            (entry.timestamp - sorted[i - 1].timestamp) / 86400
        }
        let avgGap = gaps.reduce(0, +) / Double(gaps.count)

        if avgGap <= 1.5 {
            return DailyInsight(
                title: "Excellent Consistency",
                body: "You've been journaling almost daily (avg \(String(format: "%.1f", avgGap)) days between entries). This is the key to meaningful insights.",
                category: .milestone,
                relevanceScore: 50
            )
        }
        if avgGap > 5 {
            return DailyInsight(
                title: "Let's Reconnect",
                body: "It's been a while. Your patterns sharpen with more frequent entries. Even 2 minutes helps.",
                category: .encouragement,
                relevanceScore: 35
            )
        }
        return nil
    }

    private func reflectionPrompt(entries: [JournalEntry]) -> DailyInsight? {
        guard entries.count >= 10 else { return nil }
        let topics = TopicAnalysisService.shared.extractEntities(
            from: entries.last?.transcript ?? ""
        )
        guard let entity = topics.last else { return nil }
        return DailyInsight(
            title: "Check In: \(entity.name)",
            body: "You mentioned \(entity.name) recently. How are things with \(entity.name) now?",
            category: .encouragement,
            relevanceScore: 30
        )
    }

    // MARK: - Scheduling

    func scheduleDailyInsight(entries: [JournalEntry], patterns: [DetectedPattern],
                               topicTrends: [TopicTrend], decisions: [JournalDecision],
                               at hour: Int = 7, minute: Int = 30) async {
        guard let insight = generateBestInsight(
            entries: entries, patterns: patterns,
            topicTrends: topicTrends, decisionDecisions: decisions
        ) else { return }

        center.removePendingNotificationRequests(withIdentifiers: ["daily_insight"])

        let content = UNMutableNotificationContent()
        content.title = insight.title
        content.body = insight.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_insight", content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            Logger.shared.error("DailyInsight", "Failed to schedule: \(error.localizedDescription)")
        }
    }

    func cancelDailyInsight() {
        center.removePendingNotificationRequests(withIdentifiers: ["daily_insight"])
    }

    func generateOnDemandInsight(entries: [JournalEntry], patterns: [DetectedPattern],
                                  topicTrends: [TopicTrend], decisions: [JournalDecision]) -> DailyInsight? {
        generateBestInsight(entries: entries, patterns: patterns,
                           topicTrends: topicTrends, decisionDecisions: decisions)
    }
}
