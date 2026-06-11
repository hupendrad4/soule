import SwiftUI
import UserNotifications

@main
struct SouloApp: App {
    @State private var appState = AppState()
    @State private var journalState = JournalState()
    @State private var insightState = InsightState()
    @State private var showOnboarding = false

    var body: some Scene {
        WindowGroup {
            AppTabBar()
                .environmentObject(appState)
                .environmentObject(journalState)
                .environmentObject(insightState)
                .task {
                    await initialize()
                }
                .onAppear {
                    if !appState.hasSeenOnboarding { showOnboarding = true }
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView()
                }
        }
    }

    private func initialize() async {
        do {
            try StorageService.shared.initialize()
            journalState.entries = (try? StorageService.shared.loadEntries()) ?? []
            insightState.patterns = (try? StorageService.shared.loadPatterns(activeOnly: true)) ?? []
            appState.isSubscribed = try await SubscriptionService.shared.checkSubscriptionStatus()
            try await ModelDownloadService.shared.ensureModelsDownloaded()
            appState.modelsDownloaded = WhisperWrapper.shared.isModelAvailable

            // Phase 5: Longitudinal services
            let decisions = (try? StorageService.shared.loadDecisions()) ?? []
            let baselines = try? await BaselineService.shared.computeFinalizedBaseline(from: journalState.entries)
            let predictions = await BehaviorPredictionService.shared.generatePredictions(
                entries: journalState.entries, decisions: decisions, baselines: baselines
            )
            let driftReport = try? await CognitiveDriftService.shared.detectDrift(from: journalState.entries)

            appState.predictions = predictions
            appState.baselineStatus = baselines
            appState.driftReport = driftReport

            PersonalizedInsightService.shared.updateStreakPhase(streak: journalState.currentStreak)

            if appState.notificationsEnabled {
                let granted = try? await NotificationService.shared.requestAuthorization()
                if granted == true {
                    await NotificationService.shared.scheduleDailyReminder()
                    if Bool.defaultValue("daily_insight_enabled", default: true) {
                        let topics = TopicTrendService.shared.computeTopicTrends(from: journalState.entries)
                        await DailyInsightService.shared.scheduleDailyInsight(
                            entries: journalState.entries, patterns: insightState.patterns,
                            topicTrends: topics, decisions: decisions
                        )
                    }
                }
            }

            // Schedule auto-backup
            BackupService.shared.scheduleAutoBackup(password: "")
        } catch {
            ErrorHandler.shared.handle(error)
        }
    }
}

@MainActor
final class AppState {
    var hasSeenOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasSeenOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasSeenOnboarding") }
    }

    var insightThreshold: Int {
        get { UserDefaults.standard.integer(forKey: "insight_threshold").nonZero(default: 30) }
        set { UserDefaults.standard.set(newValue, forKey: "insight_threshold") }
    }

    var isSubscribed = false
    var totalRecordings = 0
    var lastRecordingDate: Date?
    var showWaveform = true
    var audioQuality = 0
    var keepRawAudio = false
    var notificationsEnabled = true
    var modelsDownloaded = false
    var downloadProgress: Double = 0
    var lastError: Error?
    var showToastMessage: String?

    var predictions: PredictionSummary?
    var baselineStatus: BaselineService.FinalizedBaseline?
    var driftReport: DriftReport?
    var decisions: [JournalDecision] = []

    func showToast(_ message: String) {
        showToastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showToastMessage = nil
        }
    }
}

@MainActor
final class JournalState {
    var entries: [JournalEntry] = []

    var currentStreak: Int {
        let cal = Calendar.current
        var streak = 0
        var day = cal.startOfDay(for: Date())
        let entryDays = Set(entries.map { cal.startOfDay(for: Date(timeIntervalSince1970: $0.timestamp)) })
        while entryDays.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }
}

@MainActor
final class InsightState {
    var patterns: [DetectedPattern] = []
    var isLoading = false
    var lastUpdated: Date?
}
