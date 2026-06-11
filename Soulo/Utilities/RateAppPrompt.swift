import StoreKit
import UIKit

final class RateAppPrompt: Sendable {
    static let shared = RateAppPrompt()

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Configuration

    private var firstEntryDate: TimeInterval? {
        get { defaults.object(forKey: "rate_first_entry_date") as? TimeInterval }
        set { defaults.set(newValue, forKey: "rate_first_entry_date") }
    }

    private var lastPromptDate: TimeInterval? {
        get { defaults.object(forKey: "rate_last_prompt_date") as? TimeInterval }
        set { defaults.set(newValue, forKey: "rate_last_prompt_date") }
    }

    private var hasEverRated: Bool {
        get { defaults.bool(forKey: "rate_has_ever_rated") }
        set { defaults.set(newValue, forKey: "rate_has_ever_rated") }
    }

    private var entryCountAtPrompt: Int {
        get { defaults.integer(forKey: "rate_entry_count_at_prompt") }
        set { defaults.set(newValue, forKey: "rate_entry_count_at_prompt") }
    }

    // MARK: - Conditions

    func shouldPrompt(entryCount: Int, streak: Int, recentSentimentPositive: Bool) -> Bool {
        guard !hasEverRated else { return false }

        let now = Date().timeIntervalSince1970

        // Minimum usage: 5 entries
        guard entryCount >= 5 else { return false }

        // Only prompt if user has a streak or positive sentiment
        guard streak >= 2 || recentSentimentPositive else { return false }

        // Don't prompt more than once every 90 days
        if let lastPrompt = lastPromptDate, now - lastPrompt < 86400 * 90 {
            return false
        }

        // Don't prompt if we already tried at this entry count threshold
        let thresholds = [5, 10, 20, 50, 100]
        let currentThreshold = thresholds.last { $0 <= entryCount } ?? 100
        if entryCountAtPrompt >= currentThreshold {
            return false
        }

        // Minimum 3 days since first entry
        if let firstDate = firstEntryDate, now - firstDate < 86400 * 3 {
            return false
        }

        return true
    }

    // MARK: - Actions

    func recordEntry() {
        if firstEntryDate == nil {
            firstEntryDate = Date().timeIntervalSince1970
        }
    }

    func prompt() {
        guard !hasEverRated else { return }
        lastPromptDate = Date().timeIntervalSince1970
        entryCountAtPrompt = defaults.integer(forKey: "rate_entry_count_at_prompt") + 5

        Task { @MainActor in
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            SKStoreReviewController.requestReview(in: windowScene)
        }
    }

    func didRate() {
        hasEverRated = true
    }
}
