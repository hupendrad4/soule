import SwiftUI

struct TopicTrendRow: View {
    let trend: TopicTrend

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(trend.topic)
                    .font(.subheadline.weight(.medium))
                Spacer()
                sentimentBadge
            }

            if !trend.byDate.isEmpty {
                TopicSparkline(data: trend.byDate, height: 36)
                    .frame(height: 36)
            }

            HStack(spacing: 12) {
                Label("\(trend.mentionCount)×", systemImage: "doc.text")
                    .font(.caption2).foregroundColor(.secondary)
                Label("\(trend.daysActive)d", systemImage: "calendar")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text(trend.trendDirection == .increasing ? "↑ improving" :
                     trend.trendDirection == .decreasing ? "↓ declining" : "→ stable")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(trend.trendDirection == .increasing ? .green :
                                     trend.trendDirection == .decreasing ? .red : .secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }

    private var sentimentBadge: some View {
        let label: String
        let color: Color
        if trend.recentSentiment > 0.3 {
            label = "Positive"
            color = .green
        } else if trend.recentSentiment < -0.3 {
            label = "Concern"
            color = .red
        } else {
            label = "Neutral"
            color = .secondary
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.8))
            .cornerRadius(6)
    }
}

struct TopicSparkline: View {
    let data: [TopicDatePoint]
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let values = data.map { $0.sentiment }
            guard let minV = values.min(), let maxV = values.max(), maxV > minV else {
                Rectangle().fill(.tertiary.opacity(0.2)).drawingGroup()
                return
            }

            let step = w / CGFloat(max(values.count - 1, 1))
            let range = maxV - minV

            Path { path in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h - CGFloat((v - minV) / range) * (h - 4) - 2
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(lineWidth: 1.5)
            .fill(.linearGradient(
                colors: [trendColor, trendColor.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .drawingGroup()
        }
        .frame(height: height)
    }

    private var trendColor: Color {
        let recent = data.last?.sentiment ?? 0
        let first = data.first?.sentiment ?? 0
        if recent > first + 0.1 { return .green }
        if recent < first - 0.1 { return .red }
        return .secondary
    }
}
