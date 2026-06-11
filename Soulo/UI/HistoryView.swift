import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var journalState: JournalState
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedEntry: JournalEntry?
    @State private var showExport = false
    @State private var isRefreshing = false

    var filteredEntries: [JournalEntry] {
        if searchText.isEmpty { return journalState.entries }
        return journalState.entries.filter { entry in
            if entry.transcript?.localizedCaseInsensitiveContains(searchText) == true { return true }
            if entry.topics?.contains(where: { $0.topic.localizedCaseInsensitiveContains(searchText) }) == true { return true }
            if let transcript = entry.transcript {
                let entities = TopicAnalysisService.shared.extractEntities(from: transcript)
                if entities.contains(where: { $0.name.localizedCaseInsensitiveContains(searchText) }) { return true }
            }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if journalState.entries.isEmpty {
                    ContentUnavailableView(
                        "No Entries Yet",
                        systemImage: "mic.slash",
                        description: Text("Record your first voice journal entry to see it here")
                    )
                } else {
                    List {
                        ForEach(groupedEntries.keys.sorted(by: >), id: \.self) { date in
                            Section(date.formatted(date: .abbreviated, time: .omitted)) {
                                ForEach(groupedEntries[date] ?? []) { entry in
                                    EntryRow(entry: entry)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedEntry = entry }
                                        .swipeActions(edge: .trailing) {
                                            Button("Delete", role: .destructive) {
                                                Task {
                                                    try? StorageService.shared.deleteEntry(entry.id)
                                                    await MainActor.run {
                                                        journalState.entries.removeAll { $0.id == entry.id }
                                                        HapticManager.shared.play(.selection)
                                                    }
                                                }
                                            }
                                        }
                                }
                                .onDelete { offsets in
                                    deleteEntries(at: offsets, from: date)
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search entries...")
                    .refreshable {
                        await refreshEntries()
                    }
                    .overlay {
                        if isRefreshing {
                            ProgressView("Refreshing...")
                                .padding()
                                .background(.ultraThinMaterial)
                                .cornerRadius(12)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export", systemImage: "square.and.arrow.up") {
                        showExport = true
                    }
                    .disabled(journalState.entries.isEmpty)
                }
            }
            .sheet(item: $selectedEntry) { entry in
                EntryDetailView(entry: entry)
            }
            .sheet(isPresented: $showExport) {
                ExportView()
            }
        }
    }

    private var groupedEntries: [Date: [JournalEntry]] {
        Dictionary(grouping: filteredEntries) { entry in
            Date(timeIntervalSince1970: entry.timestamp).startOfDay
        }
    }

    private func refreshEntries() async {
        isRefreshing = true
        defer { isRefreshing = false }
        journalState.entries = (try? StorageService.shared.loadEntries()) ?? []
    }

    private func deleteEntries(at offsets: IndexSet, from date: Date) {
        guard var entries = groupedEntries[date] else { return }
        for index in offsets {
            let entry = entries[index]
            Task {
                try? StorageService.shared.deleteEntry(entry.id)
                await MainActor.run {
                    journalState.entries.removeAll { $0.id == entry.id }
                }
            }
        }
    }
}

struct EntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Date(timeIntervalSince1970: entry.timestamp).entryTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if !entry.audioEncrypted {
                    Text("Text")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.accentVoice)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentVoice.opacity(0.1))
                        .cornerRadius(4)
                }
                if let emotion = entry.emotion {
                    Text(emotion.primaryEmotion.rawValue.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(emotionColor(emotion.primaryEmotion).opacity(0.2))
                        .cornerRadius(4)
                }
                if entry.audioEncrypted {
                    Text((Double(entry.durationMs) / 1000).formattedMinutes)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                processingIndicator
            }
            if let transcript = entry.transcript {
                Text(transcript.prefix(120) + (transcript.count > 120 ? "..." : ""))
                    .font(.subheadline)
                    .lineLimit(2)
            }
            if let topics = entry.topics, !topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(topics.prefix(3)) { topic in
                            Text(topic.topic)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentVoice.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var processingIndicator: some View {
        let statuses = [entry.transcriptStatus, entry.biomarkersStatus, entry.emotionStatus, entry.topicsStatus]
        let hasProcessing = statuses.contains(.processing)
        let hasFailed = statuses.contains(.failed)

        if hasProcessing {
            return AnyView(ProgressView().scaleEffect(0.6))
        } else if hasFailed {
            return AnyView(Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.warning))
        }
        return AnyView(EmptyView())
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
}
