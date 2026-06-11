import SwiftUI

struct WaveformView: View {
    let isRecording: Bool
    let duration: TimeInterval
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.3, count: 60)

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(amplitudes.indices, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barColor(for: idx))
                        .frame(width: max(1, (geo.size.width - CGFloat(amplitudes.count) * 2) / CGFloat(amplitudes.count)),
                               height: max(4, geo.size.height * amplitudes[idx]))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .onChange(of: isRecording) { _, newValue in
                if newValue { startAnimating() }
                else { stopAnimating() }
            }
        }
    }

    @State private var timer: Timer?

    private func startAnimating() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            withAnimation(.interactiveSpring(response: 0.1)) {
                amplitudes = amplitudes.map { _ in
                    CGFloat.random(in: 0.1...1.0) * (0.6 + CGFloat.random(in: 0...0.4))
                }
            }
        }
    }

    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
        withAnimation(.easeOut(duration: 0.3)) {
            amplitudes = Array(repeating: 0.3, count: 60)
        }
    }

    private func barColor(for index: Int) -> Color {
        guard isRecording else { return Color.accentVoice.opacity(0.3) }
        let normalized = amplitudes[index]
        if normalized > 0.7 { return .accentVoice }
        if normalized > 0.4 { return Color.accentVoice.opacity(0.7) }
        return Color.accentVoice.opacity(0.4)
    }
}
