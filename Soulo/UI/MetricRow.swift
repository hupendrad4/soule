import SwiftUI

struct MetricRow: View {
    let label: String
    let value: String
    var icon: String?

    var body: some View {
        HStack {
            if let icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            }
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
    }
}

struct StreakIndicator: View {
    let days: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(days > 0 ? .orange : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(days) entries")
                    .font(.subheadline.weight(.semibold))
                Text(days > 1 ? "Keep going!" : "Start your journey!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SkeletonLoader: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<3) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(height: 60)
                    .shimmering()
            }
        }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(0.5),
                            .clear,
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: -geo.size.width + phase * geo.size.width * 2)
                    .blendMode(.screen)
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            )
            .clipped()
    }
}
