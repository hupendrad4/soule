import Foundation

final class TopicTrendService: Sendable {
    static let shared = TopicTrendService()

    private init() {}

    func computeTopicTrends(from entries: [JournalEntry]) -> [TopicTrend] {
        let datedEntries = entries
            .filter { $0.topics != nil }
            .sorted { $0.timestamp < $1.timestamp }

        guard datedEntries.count >= 2 else { return [] }

        var topicData: [String: [(date: TimeInterval, sentiment: Double, count: Int)]] = [:]

        for entry in datedEntries {
            guard let topics = entry.topics, !topics.isEmpty else { continue }
            for topic in topics {
                let cleanTopic = topic.topic.lowercased().trimmingCharacters(in: .whitespaces)
                guard !cleanTopic.isEmpty else { continue }
                topicData[cleanTopic, default: []].append((
                    entry.timestamp,
                    topic.sentiment,
                    topic.keywords.count + 1
                ))
            }
        }

        return topicData.compactMap { topic, dataPoints -> TopicTrend? in
            guard dataPoints.count >= 2 else { return nil }

            let sorted = dataPoints.sorted { $0.date < $1.date }
            let totalMentions = sorted.reduce(0) { $0 + $1.count }

            let recent = sorted.suffix(max(1, sorted.count / 2))
            let recentSentiment = recent.map { $0.sentiment }.reduce(0, +) / Double(recent.count)
            let overallSentiment = sorted.map { $0.sentiment }.reduce(0, +) / Double(sorted.count)

            let sentimentSlope = BiomarkerTrendService.computeSlope(sorted.map { $0.sentiment })

            return TopicTrend(
                topic: topic.capitalized,
                mentionCount: sorted.count,
                totalMentions: totalMentions,
                firstMentioned: sorted.first!.date,
                lastMentioned: sorted.last!.date,
                recentSentiment: recentSentiment,
                overallSentiment: overallSentiment,
                sentimentSlope: sentimentSlope,
                byDate: sorted.map { TopicDatePoint(date: $0.date, sentiment: $0.sentiment) }
            )
        }
        .sorted { $0.mentionCount > $1.mentionCount }
    }

    func topTopics(_ trends: [TopicTrend], limit: Int = 10) -> [TopicTrend] {
        Array(trends.prefix(limit))
    }

    func topicsWithSignificantTrend(_ trends: [TopicTrend]) -> [TopicTrend] {
        trends.filter { abs($0.sentimentSlope) > 0.05 && $0.mentionCount >= 3 }
    }

    func topicsBySentiment(_ trends: [TopicTrend]) -> (positive: [TopicTrend], negative: [TopicTrend], neutral: [TopicTrend]) {
        let positive = trends.filter { $0.recentSentiment > 0.2 }
        let negative = trends.filter { $0.recentSentiment < -0.2 }
        let neutral = trends.filter { $0.recentSentiment >= -0.2 && $0.recentSentiment <= 0.2 }
        return (positive, negative, neutral)
    }
}

struct TopicTrend: Identifiable, Sendable {
    let id = UUID()
    let topic: String
    let mentionCount: Int
    let totalMentions: Int
    let firstMentioned: TimeInterval
    let lastMentioned: TimeInterval
    let recentSentiment: Double
    let overallSentiment: Double
    let sentimentSlope: Double
    let byDate: [TopicDatePoint]

    var trendDirection: TrendDirection {
        if abs(sentimentSlope) < 0.05 { return .stable }
        return sentimentSlope > 0 ? .increasing : .decreasing
    }

    var daysActive: Int {
        max(1, Int((lastMentioned - firstMentioned) / 86400))
    }
}

struct TopicDatePoint: Sendable {
    let date: TimeInterval
    let sentiment: Double
}
