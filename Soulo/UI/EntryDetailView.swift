import SwiftUI

struct EntryDetailView: View {
    let entry: JournalEntry
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showTherapistShare = false
    @State private var therapistShareText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    Divider()
                    if let transcript = entry.transcript, !transcript.isEmpty { transcriptSection(transcript) }
                    if let biomarkers = entry.biomarkers { biomarkersSection(biomarkers) }
                    if let emotion = entry.emotion { emotionSection(emotion) }
                    if let topics = entry.topics, !topics.isEmpty { topicsSection(topics) }
                }
                .padding()
            }
            .navigationTitle(Date(timeIntervalSince1970: entry.timestamp).entryDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Share with Therapist", systemImage: "heart.text.clipboard") {
                            generateTherapistShare()
                        }
                        Button("Delete", role: .destructive, systemImage: "trash") {
                            showDeleteConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Delete Entry?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        try? StorageService.shared.deleteEntry(entry.id)
                        dismiss()
                    }
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $showTherapistShare) {
                NavigationStack {
                    ScrollView {
                        Text(therapistShareText)
                            .font(.caption)
                            .lineSpacing(4)
                            .padding()
                    }
                    .navigationTitle("Share with Therapist")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Copy") {
                                UIPasteboard.general.string = therapistShareText
                            }
                        }
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showTherapistShare = false }
                        }
                    }
                }
            }
        }
    }

    private func generateTherapistShare() {
        let entries = [entry]
        let text = TherapistShareService.shared.generateShareText(
            entries: entries, patterns: [], decisions: []
        )
        therapistShareText = text
        showTherapistShare = true
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date(timeIntervalSince1970: entry.timestamp).dayOfWeek)
                    .font(.title2.weight(.semibold))
                Text(Date(timeIntervalSince1970: entry.timestamp).entryTime)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if entry.audioEncrypted {
                    Text("Duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text((Double(entry.durationMs) / 1000).formattedMinutes)
                        .font(.title3.weight(.medium))
                } else {
                    Text("Quick Entry")
                        .font(.caption)
                        .foregroundColor(.accentVoice)
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                        .foregroundColor(.accentVoice)
                }
            }
        }
    }

    private func transcriptSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Transcript", systemImage: "text.quote")
                .font(.headline)
            Text(text)
                .font(.body)
                .lineSpacing(4)
            Text("\(text.wordCount) words")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func biomarkersSection(_ biomarkers: VoiceBiomarkers) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Voice Biomarkers", systemImage: "waveform.path")
                .font(.headline)

            VStack(spacing: 8) {
                MetricRow(label: "Speech Rate", value: "\(String(format: "%.1f", biomarkers.speechRate)) wps")
                MetricRow(label: "Vocal Energy", value: "\(String(format: "%.2f", biomarkers.vocalEnergy))")
                MetricRow(label: "Pitch Instability", value: "\(Int(biomarkers.pitchInstability * 100))%")
                MetricRow(label: "Hesitations", value: "\(Int(biomarkers.hesitationRate * 100))%")
                MetricRow(label: "Micro-breaths", value: "\(biomarkers.microBreathCount)")
                MetricRow(label: "Jitter", value: "\(Int(biomarkers.jitter * 100))%")
                MetricRow(label: "Shimmer", value: "\(Int(biomarkers.shimmer * 100))%")
            }

            if !biomarkers.isDefault {
                Divider()
                biomarkerChartSection(biomarkers)
            }
        }
    }

    private func biomarkerChartSection(_ biomarkers: VoiceBiomarkers) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Biomarker Profile")
                .font(.subheadline.weight(.medium))

            let metrics: [(BiomarkerMetric, Double)] = [
                (.speechRate, biomarkers.speechRate / 5.0),
                (.hesitationRate, biomarkers.hesitationRate),
                (.vocalEnergy, biomarkers.vocalEnergy),
                (.pitchInstability, min(biomarkers.pitchInstability, 1.0)),
                (.microBreathCount, Double(biomarkers.microBreathCount) / 30.0),
                (.jitter, min(biomarkers.jitter, 1.0)),
                (.shimmer, min(biomarkers.shimmer, 1.0)),
            ]

            HStack(spacing: 6) {
                ForEach(metrics, id: \.0) { metric, value in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.quaternary)
                                .frame(width: 16, height: 60)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barTint(for: metric.0, value: value))
                                .frame(width: 16, height: max(4, CGFloat(value) * 60))
                        }
                        Image(systemName: metric.0.icon)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func barTint(for metric: BiomarkerMetric, value: Double) -> Color {
        if value > 0.7 { return metric == .vocalEnergy ? .green : .orange }
        if value > 0.4 { return .accentVoice }
        return .accentVoice.opacity(0.4)
    }

    private func emotionSection(_ emotion: EmotionalState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Emotional State", systemImage: "face.smiling")
                .font(.headline)
            HStack {
                Text(emotion.primaryEmotion.displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(emotionColor(emotion.primaryEmotion))
                if emotion.confidence > 0 {
                    Text("(\(Int(emotion.confidence * 100))% confidence)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            HStack(spacing: 16) {
                Label("Valence: \(String(format: "%.1f", emotion.valence))", systemImage: "heart")
                    .font(.caption)
                Label("Arousal: \(String(format: "%.1f", emotion.arousal))", systemImage: "bolt")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
    }

    private func topicsSection(_ topics: [TopicAnalysis]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Topics", systemImage: "tag")
                .font(.headline)
            ForEach(topics) { topic in
                HStack {
                    Text(topic.topic)
                    Spacer()
                    Text(sentimentIcon(topic.sentiment))
                    Text(String(format: "%.1f", topic.sentiment))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
        }
    }

    private func emotionColor(_ emotion: EmotionType) -> Color {
        switch emotion {
        case .joy: return .yellow
        case .sadness: return .blue
        case .anger: return .red
        case .fear: return .purple
        case .surprise: return .orange
        case .disgust: return .green
        case .neutral: return .gray
        case .anxiety: return .indigo
        case .frustration: return .orange
        case .hope: return .teal
        case .gratitude: return .pink
        case .loneliness: return .mint
        }
    }

    private func sentimentIcon(_ value: Double) -> String {
        if value > 0.5 { return "😊" }
        if value > 0 { return "🙂" }
        if value > -0.5 { return "😐" }
        return "😞"
    }
}

extension VoiceBiomarkers {
    var isDefault: Bool {
        speechRate == 0 && hesitationRate == 0 && vocalEnergy == 0
    }
}
