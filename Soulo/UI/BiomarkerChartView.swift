import SwiftUI

struct BiomarkerChartView: View {
    let values: [Double]
    let metric: BiomarkerMetric
    let baseline: UserBaseline?
    var height: CGFloat = 120
    var showLabels: Bool = true

    private let barSpacing: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showLabels {
                HStack {
                    Label(metric.rawValue, systemImage: metric.icon)
                        .font(.caption.weight(.medium))
                    Spacer()
                    if let last = values.last {
                        Text(formatted(last))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    if let b = baseline {
                        Text("baseline: \(formatted(b.mean))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            chartBody
        }
    }

    private var chartBody: some View {
        GeometryReader { geo in
            let chartHeight = geo.size.height - 16
            let maxVal = max(values.max() ?? 1, baseline?.mean ?? 1) * 1.2
            let minVal = min(values.min() ?? 0, baseline?.mean ?? 0) * 0.8
            let range = max(maxVal - minVal, 0.001)

            ZStack(alignment: .leading) {
                baselineLine(chartHeight: chartHeight, minVal: minVal, range: range, geo: geo)
                bars(chartHeight: chartHeight, minVal: minVal, range: range, geo: geo)
            }
        }
        .frame(height: height)
    }

    private func baselineLine(chartHeight: CGFloat, minVal: Double, range: Double, geo: GeometryProxy) -> some View {
        guard let b = baseline else { return AnyView(EmptyView()) }
        let y = chartHeight - CGFloat((b.mean - minVal) / range) * chartHeight
        return AnyView(
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: geo.size.width, height: 1)
                .position(x: geo.size.width / 2, y: y + 8)
        )
    }

    private func bars(chartHeight: CGFloat, minVal: Double, range: Double, geo: GeometryProxy) -> some View {
        let barWidth = max(2, (geo.size.width - CGFloat(values.count) * barSpacing) / CGFloat(values.count))
        return HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(values.indices, id: \.self) { idx in
                let val = values[idx]
                let ratio = CGFloat((val - minVal) / range)
                let barH = max(2, ratio * chartHeight)
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(val))
                    .frame(width: barWidth, height: barH)
                    .frame(maxHeight: chartHeight, alignment: .bottom)
            }
        }
        .padding(.top, 8)
    }

    private func barColor(_ value: Double) -> Color {
        guard values.count >= 5 else { return .accentVoice }
        let recent = values.suffix(3)
        guard recent.count == 3 else { return .accentVoice }
        let avg = recent.reduce(0, +) / Double(recent.count)
        let older = values.prefix(values.count - 3)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        let delta = avg - olderAvg
        if delta > 0.1 * olderAvg { return .orange }
        if delta < -0.1 * olderAvg { return .blue }
        return .accentVoice
    }

    private func formatted(_ val: Double) -> String {
        switch metric {
        case .speechRate: return String(format: "%.1f wps", val)
        case .hesitationRate: return "\(Int(val * 100))%"
        case .vocalEnergy: return String(format: "%.2f", val)
        case .pitchInstability: return "\(Int(val * 100))%"
        case .microBreathCount: return "\(Int(val))"
        case .jitter: return "\(Int(val * 100))%"
        case .shimmer: return "\(Int(val * 100))%"
        }
    }
}

struct TrendCardView: View {
    let trend: BiomarkerTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: trend.metric.icon)
                    .foregroundColor(directionColor)
                Text(trend.metric.rawValue)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: trend.direction.icon)
                    .foregroundColor(directionColor)
                    .font(.caption)
                if trend.isSignificant {
                    Text("\(directionLabel) \(abs(trend.slope7Day) > abs(trend.slope30Day) ? "7d" : "30d")")
                        .font(.caption2)
                        .foregroundColor(directionColor)
                } else {
                    Text("stable")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            BiomarkerChartView(
                values: trend.values30Day.isEmpty ? trend.values7Day : trend.values30Day,
                metric: trend.metric,
                baseline: nil,
                height: 80,
                showLabels: false
            )

            if !trend.values7Day.isEmpty && !trend.values30Day.isEmpty {
                HStack(spacing: 16) {
                    Label("7d: \(String(format: "%.2f", trend.slope7Day))", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Label("30d: \(String(format: "%.2f", trend.slope30Day))", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var directionLabel: String {
        switch trend.direction {
        case .increasing: return "↑ rising"
        case .decreasing: return "↓ falling"
        case .stable: return "→ steady"
        }
    }

    private var directionColor: Color {
        switch trend.direction {
        case .increasing: return .orange
        case .decreasing: return .blue
        case .stable: return .secondary
        }
    }
}
