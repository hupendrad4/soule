import SwiftUI

struct PatternCardView: View {
    let pattern: DetectedPattern
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconFor(pattern.patternType))
                    .foregroundColor(colorFor(pattern.patternType))
                Text(pattern.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                severityBadge
                Button(action: { withAnimation { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(pattern.message)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(expanded ? nil : 2)

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    InfoRow("First detected", Date(timeIntervalSince1970: pattern.firstDetected).relative)
                    InfoRow("Last detected", Date(timeIntervalSince1970: pattern.lastDetected).relative)
                    InfoRow("Occurrences", "\(pattern.occurrenceCount)")
                    InfoRow("Type", pattern.patternType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var severityBadge: some View {
        Text("\(pattern.severity)")
            .font(.caption2.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor)
            .cornerRadius(6)
    }

    private var severityColor: Color {
        if pattern.severity >= 70 { return .red }
        if pattern.severity >= 50 { return .orange }
        if pattern.severity >= 30 { return .yellow }
        return .green
    }

    private func iconFor(_ type: PatternType) -> String {
        switch type {
        case .brokenPromise: return "hand.raised.slash"
        case .topicAvoidance: return "eye.slash"
        case .sentimentDecline: return "arrow.down.heart"
        case .goalAbandonment: return "flag.slash"
        case .contradiction: return "arrow.left.arrow.right"
        case .cognitiveShift: return "brain"
        case .relationshipPattern: return "person.2.slash"
        case .decisionRegret: return "arrow.uturn.backward"
        }
    }

    private func colorFor(_ type: PatternType) -> Color {
        switch type {
        case .brokenPromise: return .red
        case .topicAvoidance: return .orange
        case .sentimentDecline: return .purple
        case .goalAbandonment: return .yellow
        case .contradiction: return .blue
        case .cognitiveShift: return .indigo
        case .relationshipPattern: return .pink
        case .decisionRegret: return .brown
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }
}
