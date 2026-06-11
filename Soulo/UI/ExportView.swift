import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    @EnvironmentObject var journalState: JournalState
    @EnvironmentObject var insightState: InsightState
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var exportFormat: ExportFormat = .json
    @State private var includeDecisions = true
    @State private var includeStats = true
    @State private var shareURL: URL?

    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv = "CSV"
        case text = "Text"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                }

                Section("Options") {
                    Toggle("Include Decisions", isOn: $includeDecisions)
                    Toggle("Include Statistics", isOn: $includeStats)
                }

                Section("Contents") {
                    HStack {
                        Text("Entries")
                        Spacer()
                        Text("\(journalState.entries.count)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Patterns")
                        Spacer()
                        Text("\(insightState.patterns.count)").foregroundColor(.secondary)
                    }
                    if includeDecisions {
                        HStack {
                            Text("Decisions")
                            Spacer()
                            Text("\((try? StorageService.shared.loadDecisions(activeOnly: false))?.count ?? 0)").foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button(action: export) {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                            } else {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isExporting || journalState.entries.isEmpty)
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: { if !$0 { shareURL = nil } }
            )) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func export() {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let url: URL
                switch exportFormat {
                case .json: url = try exportJSON()
                case .csv: url = try exportCSV()
                case .text: url = try exportText()
                }
                await MainActor.run { shareURL = url }
            } catch {
                await MainActor.run { ErrorHandler.shared.handle(error) }
            }
        }
    }

    private func statsSummary() -> String {
        let entries = journalState.entries
        guard !entries.isEmpty else { return "" }

        let emotions = entries.compactMap { $0.emotion }
        let avgValence = emotions.map { $0.valence }.reduce(0, +) / Double(max(emotions.count, 1))
        let avgArousal = emotions.map { $0.arousal }.reduce(0, +) / Double(max(emotions.count, 1))

        let topEmotion = Dictionary(grouping: emotions, by: { $0.primaryEmotion })
            .sorted { $0.value.count > $1.value.count }.first?.key.rawValue ?? "unknown"

        let bioCount = entries.compactMap { $0.biomarkers }.count
        let decisions = (try? StorageService.shared.loadDecisions(activeOnly: false)) ?? []
        let kept = decisions.filter { $0.status == .kept }.count
        let regretted = decisions.filter { $0.status == .regretted }.count

        return """
        --- Statistics Summary ---
        Total Entries: \(entries.count)
        Date Range: \(Date(timeIntervalSince1970: entries.map { $0.timestamp }.min() ?? 0).entryDate) — \(Date(timeIntervalSince1970: entries.map { $0.timestamp }.max() ?? 0).entryDate)
        Avg Valence: \(String(format: "%.2f", avgValence))
        Avg Arousal: \(String(format: "%.2f", avgArousal))
        Top Emotion: \(topEmotion.capitalized)
        Entries with Biomarkers: \(bioCount)
        Decisions Kept: \(kept)
        Decisions Regretted: \(regretted)
        Patterns Detected: \(insightState.patterns.count)
        """
    }

    // MARK: - JSON Export

    private func exportJSON() throws -> URL {
        var exportData: [String: Any] = [
            "app": "Soulo",
            "version": "1.0.0",
            "exportedAt": Date().timeIntervalSince1970,
            "entries": journalState.entries.map { entry -> [String: Any] in
                var dict: [String: Any] = [
                    "id": entry.id,
                    "timestamp": entry.timestamp,
                    "durationMs": entry.durationMs,
                    "transcript": entry.transcript ?? "",
                ]
                if let b = entry.biomarkers {
                    dict["biomarkers"] = [
                        "speechRate": b.speechRate, "vocalEnergy": b.vocalEnergy,
                        "pitchInstability": b.pitchInstability, "hesitationRate": b.hesitationRate,
                        "microBreathCount": b.microBreathCount, "jitter": b.jitter, "shimmer": b.shimmer,
                    ] as [String: Any]
                }
                if let e = entry.emotion {
                    dict["emotion"] = [
                        "primary": e.primaryEmotion.rawValue, "confidence": e.confidence,
                        "valence": e.valence, "arousal": e.arousal,
                    ] as [String: Any]
                }
                if let topics = entry.topics {
                    dict["topics"] = topics.map { ["topic": $0.topic, "sentiment": $0.sentiment, "confidence": $0.confidence] }
                }
                return dict
            },
        ]

        if includeDecisions, let decisions = try? StorageService.shared.loadDecisions(activeOnly: false) {
            exportData["decisions"] = decisions.map { d -> [String: Any] in
                [
                    "decisionText": d.decisionText, "category": d.category ?? "",
                    "status": d.status.rawValue, "daysSinceDecision": d.daysSinceDecision,
                    "followUpSentiment": d.followUpSentiment ?? 0,
                ] as [String: Any]
            }
        }

        if includeStats {
            exportData["statistics"] = statsSummary()
        }

        let json = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Soulo_Export_\(Int(Date().timeIntervalSince1970)).json")
        try json.write(to: url)
        return url
    }

    // MARK: - CSV Export

    private func exportCSV() throws -> URL {
        var csv = "id,timestamp,duration_ms,transcript,emotion,valence,arousal,speech_rate,vocal_energy,pitch_instability,hesitation_rate,topics\n"

        for entry in journalState.entries {
            let timestamp = Date(timeIntervalSince1970: entry.timestamp).entryDate
            let transcript = (entry.transcript ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let emotion = entry.emotion?.primaryEmotion.rawValue ?? ""
            let valence = entry.emotion?.valence ?? 0
            let arousal = entry.emotion?.arousal ?? 0
            let speechRate = entry.biomarkers?.speechRate ?? 0
            let vocalEnergy = entry.biomarkers?.vocalEnergy ?? 0
            let pitchInstability = entry.biomarkers?.pitchInstability ?? 0
            let hesitationRate = entry.biomarkers?.hesitationRate ?? 0
            let topics = entry.topics?.map { $0.topic }.joined(separator: ";") ?? ""

            csv += "\(entry.id),\(timestamp),\(entry.durationMs),\"\(transcript)\",\(emotion),\(String(format: "%.3f", valence)),\(String(format: "%.3f", arousal)),\(String(format: "%.3f", speechRate)),\(String(format: "%.3f", vocalEnergy)),\(String(format: "%.3f", pitchInstability)),\(String(format: "%.3f", hesitationRate)),\"\(topics)\"\n"
        }

        if includeDecisions, let decisions = try? StorageService.shared.loadDecisions(activeOnly: false) {
            csv += "\n\n--- Decisions ---\n"
            csv += "decision_text,category,status,days_since_decision,follow_up_sentiment\n"
            for d in decisions {
                csv += "\"\(d.decisionText)\",\(d.category ?? ""),\(d.status.rawValue),\(d.daysSinceDecision),\(d.followUpSentiment ?? 0)\n"
            }
        }

        if includeStats {
            csv += "\n\n\(statsSummary())"
        }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "Soulo_Export_\(Int(Date().timeIntervalSince1970)).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Text Export

    private func exportText() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var text = "Soulo Journal Export\n"
        text += "Exported: \(formatter.string(from: Date()))\n"
        text += String(repeating: "=", count: 50) + "\n\n"

        for entry in journalState.entries {
            text += "Date: \(formatter.string(from: Date(timeIntervalSince1970: entry.timestamp)))\n"
            text += "Duration: \((Double(entry.durationMs) / 1000).formattedMinutes)\n"

            if let emotion = entry.emotion {
                text += "Emotion: \(emotion.primaryEmotion.rawValue.capitalized) (valence: \(String(format: "%.2f", emotion.valence)), arousal: \(String(format: "%.2f", emotion.arousal)))\n"
            }

            if let biomarkers = entry.biomarkers {
                text += "Speech Rate: \(String(format: "%.1f", biomarkers.speechRate)) wps\n"
                text += "Vocal Energy: \(biomarkers.vocalEnergy.percentage)\n"
                text += "Hesitations: \(Int(biomarkers.hesitationRate * 100))% | Jitter: \(Int(biomarkers.jitter * 100))% | Shimmer: \(Int(biomarkers.shimmer * 100))%\n"
            }

            if let topics = entry.topics, !topics.isEmpty {
                text += "Topics: \(topics.map { "\($0.topic)(\(String(format: "%.1f", $0.sentiment)))" }.joined(separator: ", "))\n"
            }

            text += "Transcript:\n\(entry.transcript ?? "No transcription")\n"
            text += String(repeating: "-", count: 40) + "\n\n"
        }

        if includeDecisions, let decisions = try? StorageService.shared.loadDecisions(activeOnly: false), !decisions.isEmpty {
            text += "--- Decisions ---\n\n"
            for d in decisions {
                text += "• \(d.decisionText) [\(d.status.rawValue)]"
                if d.daysSinceDecision > 0 { text += " (\(d.daysSinceDecision)d ago)" }
                if let sentiment = d.followUpSentiment { text += " sentiment: \(String(format: "%.1f", sentiment))" }
                text += "\n"
            }
            text += "\n"
        }

        if includeStats {
            text += "\n\(statsSummary())\n"
        }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "Soulo_Export_\(Int(Date().timeIntervalSince1970)).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
