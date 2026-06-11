import Foundation
import StoreKit

final class SubscriptionService: NSObject, @unchecked Sendable {
    static let shared = SubscriptionService()

    private var updateListenerTask: Task<Void, Never>?

    override init() {
        super.init()
        updateListenerTask = listenForTransactions()
    }

    deinit { updateListenerTask?.cancel() }

    var subscriptionInfo: SubscriptionInfo {
        (try? StorageService.shared.getSubscription()) ?? .default
    }

    func checkSubscriptionStatus() async throws -> Bool {
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID.starts(with: "soulo_") {
                    let info = SubscriptionInfo(
                        status: .active,
                        planType: SubscriptionPlan(rawValue: transaction.productID),
                        originalId: String(transaction.originalID),
                        currentId: String(transaction.id),
                        expiresAt: transaction.expirationDate?.timeIntervalSince1970,
                        autoRenew: transaction.revocationDate == nil,
                        updatedAt: Date().timeIntervalSince1970
                    )
                    try StorageService.shared.saveSubscription(info)
                    return true
                }
            case .unverified:
                try StorageService.shared.saveSubscription(.init(status: .expired, autoRenew: false, updatedAt: Date().timeIntervalSince1970))
                return false
            }
        }
        return false
    }

    func purchase(_ plan: SubscriptionPlan) async throws {
        guard let product = try await Product.products(for: [plan.rawValue]).first else {
            throw SubscriptionError.productNotFound
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                let info = SubscriptionInfo(
                    status: .active,
                    planType: plan,
                    originalId: String(transaction.originalID),
                    currentId: String(transaction.id),
                    expiresAt: transaction.expirationDate?.timeIntervalSince1970,
                    autoRenew: true,
                    trialStart: transaction.purchaseDate,
                    updatedAt: Date().timeIntervalSince1970
                )
                try StorageService.shared.saveSubscription(info)
                await transaction.finish()
            case .unverified:
                throw SubscriptionError.verificationFailed
            }
        case .userCancelled:
            throw SubscriptionError.userCancelled
        case .pending:
            throw SubscriptionError.pending
        @unknown default:
            throw SubscriptionError.unknown
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        _ = try await checkSubscriptionStatus()
    }

    func manageSubscription() {
        Task { @MainActor in
            guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            try? await AppStore.showManageSubscriptions(in: windowScene)
        }
    }

    var isFamilyShared: Bool {
        get async {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                   transaction.productID == SubscriptionPlan.family.rawValue {
                    return true
                }
            }
            return false
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await self.checkSubscriptionStatus()
                case .unverified:
                    break
                }
            }
        }
    }

    var canRecord: Bool {
        let info = subscriptionInfo
        guard !info.isActive else { return true }
        let entryCount = (try? StorageService.shared.loadEntries().count) ?? 0
        return entryCount < 7
    }

    var entriesRemainingInFreeTier: Int {
        let entryCount = (try? StorageService.shared.loadEntries().count) ?? 0
        return max(0, 7 - entryCount)
    }
}

enum SubscriptionError: Error, LocalizedError {
    case productNotFound
    case verificationFailed
    case userCancelled
    case pending
    case unknown

    var errorDescription: String? {
        switch self {
        case .productNotFound: return "Subscription product not found"
        case .verificationFailed: return "Transaction verification failed"
        case .userCancelled: return "Purchase was cancelled"
        case .pending: return "Purchase is pending"
        case .unknown: return "An unknown error occurred"
        }
    }
}
