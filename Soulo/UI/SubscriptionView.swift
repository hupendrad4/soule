import SwiftUI

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var isLoading = false
    @State private var showRestoreAlert = false
    @State private var restoreMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    trialSection
                    pricingSection
                    featuresSection
                    actionButtons
                    footerText
                }
                .padding()
            }
            .navigationTitle("Soulo Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") { restore() }
                        .disabled(isLoading)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Restore Purchases", isPresented: $showRestoreAlert) {
                Button("OK") {}
            } message: {
                Text(restoreMessage)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.accentVoice)
            Text("Understand Yourself")
                .font(.title2.weight(.bold))
            Text("Soulo analyzes your speech patterns to reveal hidden insights about your emotional well-being.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var trialSection: some View {
        HStack {
            Image(systemName: "gift.fill")
                .foregroundColor(.accentWarm)
            Text("\(SubscriptionService.shared.entriesRemainingInFreeTier) free entries remaining")
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.accentWarm.opacity(0.1))
        .cornerRadius(12)
    }

    private var pricingSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                PricingCard(
                    title: "Monthly",
                    price: "$9.99",
                    period: "per month",
                    features: ["Unlimited entries", "All insights", "Priority support"],
                    isRecommended: false,
                    action: { await purchase(.monthly) }
                )
                PricingCard(
                    title: "Yearly",
                    price: "$79.99",
                    period: "per year",
                    features: ["Unlimited entries", "All insights", "Priority support", "Best value"],
                    isRecommended: true,
                    action: { await purchase(.annual) }
                )
            }

            PricingCard(
                title: "Family",
                price: "$14.99",
                period: "per month",
                features: ["Everything in Premium", "Share with up to 5 family", "Separate private journals"],
                isRecommended: false,
                action: { await purchase(.family) }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What You Get")
                .font(.headline)

            FeatureRow(icon: "mic.fill", title: "Unlimited Journaling", description: "Record as many entries as you want")
            FeatureRow(icon: "chart.bar.fill", title: "Deep Pattern Analysis", description: "Detect broken promises, topic avoidance, sentiment trends, and goal cycles")
            FeatureRow(icon: "lock.shield.fill", title: "100% Private", description: "All processing on your device. Your data never leaves your phone")
            FeatureRow(icon: "brain.head.profile", title: "Voice Biomarkers", description: "Speech rate, pitch, energy, and hesitation analysis")
            FeatureRow(icon: "arrow.up.icloud.fill", title: "iCloud Backup", description: "End-to-end encrypted backups")
            FeatureRow(icon: "square.and.arrow.up", title: "Export", description: "Export your journal as JSON, CSV, or text")
            FeatureRow(icon: "person.2.fill", title: "Family Sharing", description: "Share subscription with up to 5 family members — each with a separate private journal")
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView()
            }
            Divider()
            VStack(spacing: 8) {
                Text("Pay Another Way")
                    .font(.subheadline.weight(.medium))
                Button {
                    Task { await presentStripeCheckout(plan: .annual) }
                } label: {
                    Label("Subscribe via Web (Stripe)", systemImage: "globe")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                Text("Secure payment via Stripe. Your card details are never shared with Soulo.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var footerText: some View {
        VStack(spacing: 4) {
            Text("Subscriptions auto-renew. Cancel anytime in Settings.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text("By subscribing, you agree to the Terms of Service.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func presentStripeCheckout(plan: SubscriptionPlan) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let request: StripeService.CheckoutRequest = plan == .annual
                ? .annual() : .monthly()
            let response = try await StripeService.shared.createCheckoutSession(request: request)
            await StripeService.shared.presentCheckout(url: response.url)
        } catch {
            ErrorHandler.shared.handle(error)
        }
    }

    private func purchase(_ plan: SubscriptionPlan) async {
        isLoading = true
        do {
            try await SubscriptionService.shared.purchase(plan)
            await MainActor.run {
                appState.isSubscribed = true
                dismiss()
            }
        } catch {
            ErrorHandler.shared.handle(error)
        }
        isLoading = false
    }

    private func restore() {
        isLoading = true
        Task {
            do {
                let result = try await SubscriptionService.shared.checkSubscriptionStatus()
                restoreMessage = result ? "Your subscription has been restored." : "No active subscription found."
            } catch {
                restoreMessage = "Could not restore purchases. Try again later."
            }
            showRestoreAlert = true
            isLoading = false
        }
    }
}

struct PricingCard: View {
    let title: String
    let price: String
    let period: String
    let features: [String]
    let isRecommended: Bool
    let action: () async -> Void

    @State private var purchasing = false

    var body: some View {
        Button(action: { Task { purchasing = true; await action(); purchasing = false } }) {
            VStack(spacing: 8) {
                if isRecommended {
                    Text("BEST VALUE")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentVoice)
                        .cornerRadius(4)
                }
                Text(title)
                    .font(.headline)
                Text(price)
                    .font(.title.weight(.bold))
                Text(period)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Divider()
                ForEach(features, id: \.self) { feature in
                    Label(feature, systemImage: "checkmark")
                        .font(.caption2)
                }
                if purchasing { ProgressView().scaleEffect(0.8) }
            }
            .foregroundColor(.primary)
            .padding()
            .frame(maxWidth: .infinity)
            .background(isRecommended ? Color.accentVoice.opacity(0.1) : .ultraThinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isRecommended ? Color.accentVoice : Color.clear, lineWidth: 2)
            )
        }
        .disabled(purchasing)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentVoice)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
