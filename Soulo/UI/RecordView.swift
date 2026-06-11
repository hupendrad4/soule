import SwiftUI

struct RecordView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var journalState: JournalState
    @State private var recordingService = RecordingService.shared
    @State private var showSubscription = false
    @State private var showOnboarding = false
    @State private var transcriptPreview = ""
    @State private var processingStage: ProcessingStage = .idle

    enum ProcessingStage {
        case idle, recording, transcribing, analyzing, done
        var label: String {
            switch self {
            case .idle: return ""
            case .recording: return "Recording..."
            case .transcribing: return "Transcribing..."
            case .analyzing: return "Analyzing biomarkers..."
            case .done: return "Done!"
            }
        }
    }

    @State private var showingQuickEntry = false
    @State private var quickEntryText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !SubscriptionService.shared.canRecord && processingStage == .idle && !showingQuickEntry {
                    freeTrialLimitView
                } else if showingQuickEntry {
                    quickEntryView
                } else {
                    recordingUI
                }
            }
            .navigationTitle("Soulo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if processingStage == .idle && !recordingService.isRecording && !showingQuickEntry {
                        Button("Quick Entry", systemImage: "square.and.pencil") {
                            showingQuickEntry = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showOnboarding) { OnboardingView() }
            .sheet(isPresented: $showSubscription) { SubscriptionView() }
            .onAppear {
                if !appState.hasSeenOnboarding { showOnboarding = true }
            }
        }
    }

    private var quickEntryView: some View {
        VStack(spacing: 16) {
            TextEditor(text: $quickEntryText)
                .font(.body)
                .padding()
                .background(Color.surfaceSecondary)
                .cornerRadius(14)
                .padding(.horizontal)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if quickEntryText.isEmpty {
                        Text("What's on your mind?")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 28)
                            .padding(.top, 28)
                    }
                }

            HStack(spacing: 16) {
                Button("Cancel") {
                    quickEntryText = ""
                    showingQuickEntry = false
                }
                .foregroundColor(.secondary)

                Button("Save Entry") {
                    saveQuickEntry()
                }
                .buttonStyle(.borderedProminent)
                .disabled(quickEntryText.trimmed.isEmpty)
            }
            .padding(.bottom)
        }
    }

    private func saveQuickEntry() {
        let text = quickEntryText.trimmed
        guard !text.isEmpty else { return }

        Task {
            let result = await ProcessingPipelineService.shared.processQuickEntry(text: text)

            await MainActor.run {
                journalState.entries.insert(result.entry, at: 0)
                appState.totalRecordings += 1
                quickEntryText = ""
                showingQuickEntry = false

                if result.failedStages.isEmpty {
                    HapticManager.shared.play(.processingComplete)
                }
            }

            if !result.patterns.isEmpty {
                try? StorageService.shared.savePatterns(result.patterns)
            }
        }
    }

    private var freeTrialLimitView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Free trial limit reached")
                .font(.title2.weight(.medium))
            Text("You've used all 7 free entries. Subscribe to keep journaling.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("View Plans") { showSubscription = true }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var recordingUI: some View {
        VStack(spacing: 24) {
            WaveformView(isRecording: recordingService.isRecording, duration: recordingService.currentDuration)
                .frame(height: 160)
                .padding(.horizontal)

            if !transcriptPreview.isEmpty {
                Text(transcriptPreview)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if processingStage != .idle {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text(processingStage.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(recordingService.isRecording ? "Recording..." : "Tap to record")
                    .font(.title3.weight(.medium))
                    .foregroundColor(recordingService.isRecording ? .red : .primary)

                Text(recordingService.isRecording
                     ? recordingService.currentDuration.formattedMinutes
                     : "Your thoughts are private")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(recordingService.isRecording ? Color.red : Color.accentVoice)
                        .frame(width: 72, height: 72)
                    Image(systemName: recordingService.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                .symbolEffect(.bounce, value: recordingService.isRecording)
            }
            .disabled(processingStage == .transcribing || processingStage == .analyzing)
            .padding(.bottom, 32)

            if !WhisperWrapper.shared.isModelAvailable && processingStage == .idle {
                Text("Transcription model not yet downloaded. Recording will start when complete.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private func toggleRecording() {
        if recordingService.isRecording {
            Task { await stopAndProcess() }
        } else {
            guard SubscriptionService.shared.canRecord else {
                HapticManager.shared.play(.warning)
                showSubscription = true
                return
            }
            do {
                HapticManager.shared.play(.recordStart)
                transcriptPreview = ""
                try recordingService.startRecording()
                processingStage = .recording
            } catch {
                HapticManager.shared.play(.error)
                ErrorHandler.shared.handle(error)
                processingStage = .idle
            }
        }
    }

    private func stopAndProcess() async {
        processingStage = .transcribing
        defer { processingStage = .idle }

        do {
            HapticManager.shared.play(.recordStop)
            let (audioURL, duration) = try await recordingService.stopRecording()

            let result = await ProcessingPipelineService.shared.processRecording(audioURL: audioURL, duration: duration)

            await MainActor.run {
                transcriptPreview = result.entry.transcript ?? ""
                processingStage = result.failedStages.isEmpty ? .done : .idle

                journalState.entries.insert(result.entry, at: 0)
                appState.totalRecordings += 1
                appState.lastRecordingDate = Date()

                RateAppPrompt.shared.recordEntry()
                if RateAppPrompt.shared.shouldPrompt(
                    entryCount: journalState.entries.count,
                    streak: journalState.currentStreak,
                    recentSentimentPositive: result.entry.emotion?.valence ?? 0 > 0.2
                ) {
                    RateAppPrompt.shared.prompt()
                }

                if !result.failedStages.isEmpty {
                    appState.showToast("Processing: \(result.failedStages.count) stage(s) need retry")
                } else {
                    HapticManager.shared.play(.processingComplete)
                }

                if journalState.currentStreak > 0 {
                    Task { await NotificationService.shared.scheduleStreakNotification(days: journalState.currentStreak) }
                }
            }

            if !result.patterns.isEmpty {
                try? StorageService.shared.savePatterns(result.patterns)
            }
        } catch {
            HapticManager.shared.play(.error)
            ErrorHandler.shared.handle(error)
        }
    }
}
