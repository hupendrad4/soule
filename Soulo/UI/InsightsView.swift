import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var insightState: InsightState
    @EnvironmentObject var journalState: JournalState
    @State private var trends: [BiomarkerTrend] = []
    @State private var baselines: [UserBaseline] = []
    @State private var topicTrends: [TopicTrend] = []
    @State private var selectedTrend: BiomarkerTrend?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if journalState.entries.count < 3 {
                        ContentUnavailableView(
                            "More Entries Needed",
                            systemImage: "chart.bar.xaxis",
                            description: Text("Record at least 3 entries to start seeing insights.")
                        )
                    } else {
                        streakSection
                        summarySection
                        if !trends.isEmpty { biomarkerTrendsSection }
                        if !topicTrends.isEmpty { topicTrendsSection }
                        if !insightState.patterns.isEmpty { patternsSection }
                    }
                }
                .padding()
            }
            .navigationTitle("Insights")
            .refreshable { await loadData() }
            .task { await loadData() }
        }
    }

    private var streakSection: some View {
        VStack(spacing: 8) {
            HStack {
                StreakIndicator(days: journalState.entries.count)
                Spacer()
            }
            if let last = journalState.entries.first {
                HStack {
                    Text("Last entry: \(Date(timeIntervalSince1970: last.timestamp).relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .cardStyle()
    }

    private var summarySection: some View {
        VStack(spacing: 16) {
            Text("Overview")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            let totalDuration = journalState.entries.map { $0.durationMs }.reduce(0, +)
            let avgDuration = journalState.entries.isEmpty ? 0 : Double(totalDuration) / Double(journalState.entries.count) / 1000
            let totalWords = journalState.entries.compactMap { $0.transcript?.wordCount }.reduce(0, +)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatBox(value: "\(journalState.entries.count)", label: "Entries", icon: "mic.fill")
                StatBox(value: avgDuration.formattedMinutes, label: "Avg Duration", icon: "timer")
                StatBox(value: "\(totalWords)", label: "Total Words", icon: "text.word.count")
                StatBox(value: "\(insightState.patterns.count)", label: "Patterns", icon: "brain.head.profile")
                StatBox(value: "\(trends.filter { $0.isSignificant }.count)", label: "Active Trends", icon: "chart.line.uptrend.xyaw")
                StatBox(value: journalState.entries.first.map { Date(timeIntervalSince1970: $0.timestamp).relative } ?? "N/A", label: "Last Entry", icon: "calendar")
            }
        }
        .cardStyle()
    }

    private var biomarkerTrendsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Voice Biomarker Trends")
                    .font(.headline)
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.7) }
            }

            ForEach(trends.filter { $0.values30Day.count >= 3 }.prefix(5)) { trend in
                TrendCardView(trend: trend)
            }

            if trends.allSatisfy({ $0.values30Day.count < 3 }) && trends.count >= 3 {
                Text("More entries needed for 30-day trends. Showing 7-day data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(trends.filter { $0.values7Day.count >= 3 }.prefix(5)) { trend in
                    TrendCardView(trend: trend)
                }
            }
        }
        .cardStyle()
    }

    private var topicTrendsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Topic Trends")
                    .font(.headline)
                Spacer()
                if !topicTrends.isEmpty {
                    Text("\(topicTrends.count) topics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            let sorted = topicTrends.sorted { $0.mentionCount > $1.mentionCount }.prefix(8)

            ForEach(Array(sorted)) { trend in
                TopicTrendRow(trend: trend)
            }
        }
        .cardStyle()
    }

    private var patternsSection: some View {
        VStack(spacing: 12) {
            Text("Detected Patterns")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if insightState.patterns.isEmpty {
                Text("No patterns detected yet. Keep journaling!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(insightState.patterns) { pattern in
                    PatternCardView(pattern: pattern)
                }
            }
        }
        .cardStyle()
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let service = BiomarkerTrendService.shared
            trends = try await service.computeTrends(from: journalState.entries)

            let baselineService = BaselineService.shared
            baselines = try await baselineService.computeBaselines(from: journalState.entries)

            let topicService = TopicTrendService.shared
            topicTrends = topicService.computeTopicTrends(from: journalState.entries)

            let patterns = try await PatternDetectionService().detectPatterns(in: journalState.entries)
            await MainActor.run {
                insightState.patterns = patterns
                insightState.lastUpdated = Date()
            }
        } catch {
            ErrorHandler.shared.handle(error)
        }
    }
}

struct StatBox: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentVoice)
            Text(value)
                .font(.title3.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }
}
