import Foundation

final class PersonalizedInsightService: Sendable {
    static let shared = PersonalizedInsightService()

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Profile Management

    func loadProfile() -> UserInsightProfile {
        guard let data = defaults.data(forKey: "insight_profile"),
              let profile = try? JSONDecoder().decode(UserInsightProfile.self, from: data) else {
            return UserInsightProfile(
                preferredTypes: InsightType.allCases.map { $0.rawValue },
                preferredTimeHour: 7,
                sensitivityLevel: 50,
                streakPhase: .cold,
                recentEngagements: [],
                lastUpdated: Date().timeIntervalSince1970
            )
        }
        return profile
    }

    func saveProfile(_ profile: UserInsightProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: "insight_profile")
    }

    func updateStreakPhase(streak: Int) {
        var profile = loadProfile()
        let phase: UserInsightProfile.StreakPhase
        switch streak {
        case 0..<3: phase = .cold
        case 3..<7: phase = .building
        case 7..<21: phase = .maintaining
        default: phase = .thriving
        }
        profile.streakPhase = phase
        profile.lastUpdated = Date().timeIntervalSince1970
        saveProfile(profile)
    }

    // MARK: - Engagement Tracking

    func recordImpression(for type: String) {
        var profile = loadProfile()
        if let idx = profile.recentEngagements.firstIndex(where: { $0.insightType == type }) {
            var eng = profile.recentEngagements[idx]
            eng.impressionCount += 1
            profile.recentEngagements[idx] = eng
        } else {
            profile.recentEngagements.append(InsightEngagement(
                insightType: type, impressionCount: 1, expandCount: 0,
                dismissCount: 0, averageRelevanceScore: 0
            ))
        }
        saveProfile(profile)
    }

    func recordExpand(for type: String) {
        var profile = loadProfile()
        if let idx = profile.recentEngagements.firstIndex(where: { $0.insightType == type }) {
            var eng = profile.recentEngagements[idx]
            eng.expandCount += 1
            profile.recentEngagements[idx] = eng
        }
        saveProfile(profile)
    }

    func recordDismiss(for type: String) {
        var profile = loadProfile()
        if let idx = profile.recentEngagements.firstIndex(where: { $0.insightType == type }) {
            var eng = profile.recentEngagements[idx]
            eng.dismissCount += 1
            profile.recentEngagements[idx] = eng
        }
        saveProfile(profile)
    }

    // MARK: - Insight Ranking

    func rankInsights(_ insights: [DailyInsightService.DailyInsight],
                      profile: UserInsightProfile) -> [RankedInsight] {
        let sortedByEngagement = profile.recentEngagements
            .sorted { $0.engagementRate > $1.engagementRate }
            .map { $0.insightType }

        return insights.map { insight in
            let baseScore = insight.relevanceScore
            var boost = 0

            // Boost for preferred types
            if profile.preferredTypes.contains(insight.category.rawValue) {
                boost += 10
            }

            // Boost for types user engages with
            if sortedByEngagement.first == insight.category.rawValue {
                boost += 15
            }

            // Boost based on streak phase
            switch profile.streakPhase {
            case .cold: boost += insight.category == .encouragement ? 10 : 0
            case .building: boost += insight.category == .milestone ? 10 : 0
            case .maintaining: boost += insight.category == .pattern || insight.category == .trend ? 10 : 0
            case .thriving: boost += insight.category == .warning || insight.category == .improvement ? 10 : 0
            }

            // Penalize for frequently dismissed types
            if let engagement = profile.recentEngagements.first(where: { $0.insightType == insight.category.rawValue }) {
                if engagement.dismissCount > engagement.expandCount * 2 {
                    boost -= 20
                }
            }

            let reason: String = boost > 0 ? "Personalized based on your engagement" : "Standard ranking"

            return RankedInsight(
                id: UUID().uuidString,
                title: insight.title,
                body: insight.body,
                category: insight.category.rawValue,
                baseScore: baseScore,
                personalizationBoost: boost,
                finalScore: max(0, baseScore + boost),
                reason: reason
            )
        }
        .sorted { $0.finalScore > $1.finalScore }
    }

    // MARK: - Sensitivity Adjustment

    func recommendedSensitivity(streak: Int, entries: Int, patternsActive: Int) -> Int {
        let base = 50
        let streakAdjust = min(streak, 30) - 15
        let entryAdjust = min(entries, 100) / 10
        let patternAdjust = patternsActive * 5
        return max(10, min(90, base - streakAdjust + entryAdjust + patternAdjust))
    }
}
