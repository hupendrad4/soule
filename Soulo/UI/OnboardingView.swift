import SwiftUI
import AVFoundation
import UserNotifications

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var micGranted = false
    @State private var notificationsGranted = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadComplete = false

    let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "brain.head.profile",
            title: "Welcome to Soulo",
            description: "Your private AI voice journal. Speak naturally — we analyze your voice patterns to reveal insights about your emotional well-being.",
            color: .accentVoice
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "100% Private. On-Device.",
            description: "Everything stays on your iPhone. Transcription, analysis, pattern detection — all done locally. Your data never leaves your device.",
            color: .green
        ),
        OnboardingPage(
            icon: "mic.fill",
            title: "How It Works",
            description: "Record a voice entry. Soulo transcribes it, analyzes your voice biomarkers (speech rate, pitch, energy), detects emotional state, and identifies behavioral patterns — all automatically.",
            color: .accentVoice
        ),
        OnboardingPage(
            icon: "chart.bar.xaxis",
            title: "Discover Hidden Patterns",
            description: "Get insights about broken promises, topic avoidance, sentiment trends, goal cycles, and cognitive shifts. Soulo shows you what you might miss.",
            color: .orange
        ),
        OnboardingPage(
            icon: "gift.fill",
            title: "Free Trial — 7 Entries",
            description: "Try Soulo free for 7 entries. Unlock unlimited entries, voice biomarkers, pattern detection, and iCloud backup with a subscription.",
            color: .accentWarm
        ),
    ]

    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { idx in
                    OnboardingPageView(page: pages[idx])
                        .tag(idx)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if currentPage == 1 {
                    permissionButtons
                } else if currentPage == 2 && !downloadComplete {
                    modelDownloadButton
                }

                Button(action: advance) {
                    Text(buttonLabel)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentVoice)
                        .cornerRadius(14)
                }
                .disabled(isDownloading)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
    }

    private var buttonLabel: String {
        if currentPage < pages.count - 1 { return "Continue" }
        return "Start Journaling"
    }

    private var permissionButtons: some View {
        VStack(spacing: 8) {
            Button(action: requestMicrophone) {
                HStack {
                    Image(systemName: micGranted ? "checkmark.circle.fill" : "mic.fill")
                        .foregroundColor(micGranted ? .green : .primary)
                    Text(micGranted ? "Microphone Granted" : "Enable Microphone")
                    Spacer()
                    if !micGranted { Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary) }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
            }
            .disabled(micGranted)

            Button(action: requestNotifications) {
                HStack {
                    Image(systemName: notificationsGranted ? "checkmark.circle.fill" : "bell.fill")
                        .foregroundColor(notificationsGranted ? .green : .primary)
                    Text(notificationsGranted ? "Notifications On" : "Enable Reminders")
                    Spacer()
                    if !notificationsGranted { Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary) }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
            }
            .disabled(notificationsGranted)
        }
        .padding(.horizontal, 24)
    }

    private var modelDownloadButton: some View {
        VStack(spacing: 8) {
            if isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 24)
                    Text("Downloading AI model (\(Int(downloadProgress * 100))%)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !downloadComplete {
                Button(action: downloadModels) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download AI Model (77 MB)")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                }
            }
        }
    }

    private func advance() {
        if currentPage < pages.count - 1 {
            withAnimation { currentPage += 1 }
        } else {
            appState.hasSeenOnboarding = true
            dismiss()
        }
    }

    // MARK: - Permissions

    private func requestMicrophone() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            Task { @MainActor in micGranted = granted }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in notificationsGranted = granted }
        }
    }

    // MARK: - Model Download

    private func downloadModels() {
        isDownloading = true
        Task {
            defer { isDownloading = false }
            do {
                try await ModelDownloadService.shared.ensureModelsDownloaded()
                await MainActor.run {
                    downloadComplete = true
                    appState.modelsDownloaded = true
                }
            } catch {
                await MainActor.run {
                    appState.showToast("Download failed. You can retry later.")
                }
            }
        }
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: page.icon)
                .font(.system(size: 72))
                .foregroundColor(page.color)
                .symbolEffect(.bounce, options: .repeating)
            Text(page.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(page.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .padding()
    }
}
