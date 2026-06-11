import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var journalState: JournalState
    @EnvironmentObject var insightState: InsightState
    @State private var showSubscription = false
    @State private var showExport = false
    @State private var showDataDeleted = false
    @State private var deleteConfirm = false
    @State private var reminderTime = Date.from(hour: 20, minute: 0)
    @State private var insightTime = Date.from(hour: 7, minute: 30)

    var body: some View {
        NavigationStack {
            Form {
                journalSection
                subscriptionSection
                dataSection
                recordingSection
                insightsSection
                notificationsSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showSubscription) { SubscriptionView() }
            .sheet(isPresented: $showExport) { ExportView() }
            .alert("Delete All Data?", isPresented: $deleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteAllData() }
            } message: {
                Text("All journal entries, patterns, and data will be permanently deleted. This cannot be undone.")
            }
            .alert("Data Deleted", isPresented: $showDataDeleted) {
                Button("OK") {}
            } message: {
                Text("All your data has been deleted.")
            }
        }
    }

    private var journalSection: some View {
        Section("Journal") {
            StreakCard(streak: journalState.currentStreak)

            Toggle("Daily Reminder", isOn: Binding(
                get: { appState.notificationsEnabled },
                set: { newValue in
                    appState.notificationsEnabled = newValue
                    if newValue {
                        Task {
                            try? await NotificationService.shared.requestAuthorization()
                            await NotificationService.shared.scheduleDailyReminder(
                                at: Calendar.current.component(.hour, from: reminderTime),
                                minute: Calendar.current.component(.minute, from: reminderTime)
                            )
                        }
                    } else {
                        NotificationService.shared.cancelDailyReminder()
                    }
                }
            ))

            if appState.notificationsEnabled {
                DatePicker("Reminder Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .onChange(of: reminderTime) { _, newTime in
                        Task {
                            try? await NotificationService.shared.requestAuthorization()
                            await NotificationService.shared.scheduleDailyReminder(
                                at: Calendar.current.component(.hour, from: newTime),
                                minute: Calendar.current.component(.minute, from: newTime)
                            )
                        }
                    }
            }

            TranscriptionStatusRow()
        }
    }

    private var subscriptionSection: some View {
        Section("Subscription") {
            HStack {
                Label("Status", systemImage: "creditcard")
                Spacer()
                Text(appState.isSubscribed ? "Active" : "Free Trial")
                    .foregroundColor(appState.isSubscribed ? .green : .secondary)
            }
            Button("Manage Subscription") { showSubscription = true }
                .foregroundColor(.accentVoice)
        }
    }

    private var dataSection: some View {
        Section("Data") {
            NavigationLink(destination: ExportView()) {
                Label("Export Data", systemImage: "square.and.arrow.up")
            }
            Button("Backup to iCloud") {
                Task {
                    do {
                        try await BackupService.shared.performBackup(password: "default")
                        await MainActor.run { appState.showToast("Backup completed") }
                    } catch {
                        ErrorHandler.shared.handle(error)
                    }
                }
            }
            Button("Delete All Data", role: .destructive) { deleteConfirm = true }
        }
    }

    private var recordingSection: some View {
        Section("Recording") {
            Toggle("Microphone Animation", isOn: $appState.showWaveform)
            Picker("Audio Quality", selection: $appState.audioQuality) {
                Text("Standard").tag(0)
                Text("High").tag(1)
            }
            Toggle("Save Raw Audio", isOn: $appState.keepRawAudio)
                .disabled(true)
            Text("For privacy, raw audio is deleted after transcription by default.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var insightsSection: some View {
        Section("Insights") {
            VStack(alignment: .leading) {
                Text("Pattern Sensitivity").font(.subheadline)
                Slider(value: Binding(
                    get: { Double(appState.insightThreshold) },
                    set: { appState.insightThreshold = Int($0) }
                ), in: 10...90, step: 10)
                Text("Current: \(appState.insightThreshold) (higher = fewer alerts)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Daily Insight", isOn: Binding(
                get: { Bool.defaultValue("daily_insight_enabled", default: true) },
                set: { newValue in
                    UserDefaults.standard.set(newValue, forKey: "daily_insight_enabled")
                    if newValue {
                        Task {
                            try? await NotificationService.shared.requestAuthorization()
                            let topics = TopicTrendService.shared.computeTopicTrends(from: journalState.entries)
                            let decisions = (try? StorageService.shared.loadDecisions()) ?? []
                            await DailyInsightService.shared.scheduleDailyInsight(
                                entries: journalState.entries, patterns: insightState.patterns,
                                topicTrends: topics, decisions: decisions,
                                at: Calendar.current.component(.hour, from: insightTime),
                                minute: Calendar.current.component(.minute, from: insightTime)
                            )
                        }
                    } else {
                        DailyInsightService.shared.cancelDailyInsight()
                    }
                }
            ))

            if Bool.defaultValue("daily_insight_enabled", default: true) {
                DatePicker("Insight Time", selection: $insightTime, displayedComponents: .hourAndMinute)
                    .onChange(of: insightTime) { _, newTime in
                        Task {
                            try? await NotificationService.shared.requestAuthorization()
                            let topics = TopicTrendService.shared.computeTopicTrends(from: journalState.entries)
                            let decisions = (try? StorageService.shared.loadDecisions()) ?? []
                            await DailyInsightService.shared.scheduleDailyInsight(
                                entries: journalState.entries, patterns: insightState.patterns,
                                topicTrends: topics, decisions: decisions,
                                at: Calendar.current.component(.hour, from: newTime),
                                minute: Calendar.current.component(.minute, from: newTime)
                            )
                        }
                    }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Entries")
                Spacer()
                Text("\(appState.totalRecordings)")
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("Streak")
                Spacer()
                Text("\(journalState.currentStreak) days")
                    .foregroundColor(.secondary)
            }
            Link("Privacy Policy", destination: URL(string: "https://soulo.app/privacy")!)
                .foregroundColor(.accentVoice)
            Link("Terms of Service", destination: URL(string: "https://soulo.app/terms")!)
                .foregroundColor(.accentVoice)
        }
    }

    private func deleteAllData() {
        Task {
            try? StorageService.shared.deleteAll()
            await MainActor.run {
                appState.totalRecordings = 0
                showDataDeleted = true
            }
        }
    }
}

struct StreakCard: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(streak > 0 ? Color.orange.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: streak > 0 ? "flame.fill" : "flame")
                    .font(.title2)
                    .foregroundColor(streak > 0 ? .orange : .gray)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak) Day Streak")
                    .font(.subheadline.weight(.semibold))
                Text(streakMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var streakMessage: String {
        switch streak {
        case 0: return "Record your first entry to start!"
        case 1: return "First entry down!"
        case 2...3: return "Building momentum!"
        case 4...6: return "Great habit forming!"
        case 7...13: return "One week! Insights are unlocking."
        case 14...20: return "Two weeks of self-reflection!"
        case 21...29: return "Three weeks! This is a lifestyle now."
        case 30...: return "\(streak) days! You're in the elite club."
        default: return "Keep going!"
        }
    }
}

struct TranscriptionStatusRow: View {
    @State private var modelAvailable = false

    var body: some View {
        HStack {
            Label("Transcription Model", systemImage: "waveform")
            Spacer()
            if modelAvailable {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Label("Downloading", systemImage: "arrow.down.circle")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Requires Wi-Fi")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            modelAvailable = WhisperWrapper.shared.isModelAvailable
        }
    }
}

extension Date {
    static func from(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }
}
