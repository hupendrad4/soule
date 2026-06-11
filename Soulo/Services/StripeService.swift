import Foundation
import SafariServices

final class StripeService: NSObject, Sendable {
    static let shared = StripeService()

    private let session: URLSession
    private var callbackHandler: ((Result<Void, StripeError>) -> Void)?

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "stripe_backend_url")
            ?? "https://api.soulo.app/stripe"
    }

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        super.init()
    }

    // MARK: - Checkout Session

    struct CheckoutRequest: Encodable {
        let priceId: String
        let customerEmail: String?
        let successUrl: String
        let cancelUrl: String
        let metadata: [String: String]

        static func monthly(email: String? = nil) -> CheckoutRequest {
            CheckoutRequest(
                priceId: "price_monthly_9_99",
                customerEmail: email,
                successUrl: "soulo://payment/success",
                cancelUrl: "soulo://payment/cancel",
                metadata: ["plan": "monthly", "source": "ios_app"]
            )
        }

        static func annual(email: String? = nil) -> CheckoutRequest {
            CheckoutRequest(
                priceId: "price_annual_79_99",
                customerEmail: email,
                successUrl: "soulo://payment/success",
                cancelUrl: "soulo://payment/cancel",
                metadata: ["plan": "annual", "source": "ios_app"]
            )
        }
    }

    struct CheckoutResponse: Decodable {
        let sessionId: String
        let url: String
        let expiresAt: TimeInterval
    }

    func createCheckoutSession(request: CheckoutRequest) async throws -> CheckoutResponse {
        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/create-checkout-session")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StripeError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        return try JSONDecoder().decode(CheckoutResponse.self, from: data)
    }

    // MARK: - Present Checkout

    @MainActor
    func presentCheckout(url: String) {
        guard let checkoutURL = URL(string: url) else { return }
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = false
        let safari = SFSafariViewController(url: checkoutURL, configuration: config)
        safari.modalPresentationStyle = .formSheet

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return }
        root.present(safari, animated: true)
    }

    // MARK: - Handle Callback

    func handleCallback(url: URL) {
        guard url.scheme == "soulo" else { return }

        if url.host == "payment" && url.lastPathComponent == "success" {
            Task {
                try? await SubscriptionService.shared.checkSubscriptionStatus()
            }
        }
    }

    // MARK: - Verify Session

    func verifySession(sessionId: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(baseURL)/verify-session/\(sessionId)")!)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return false
        }

        struct VerifyResponse: Decodable {
            let paid: Bool
            let plan: String?
        }
        let result = try JSONDecoder().decode(VerifyResponse.self, from: data)
        return result.paid
    }

    // MARK: - Customer Portal

    func createCustomerPortal(customerId: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/customer-portal")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["customerId": customerId])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StripeError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        struct PortalResponse: Decodable {
            let url: String
        }
        let portal = try JSONDecoder().decode(PortalResponse.self, from: data)
        return portal.url
    }

    // MARK: - Configuration

    func setBackendURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "stripe_backend_url")
    }
}

enum StripeError: Error, LocalizedError {
    case serverError(statusCode: Int)
    case invalidResponse
    case paymentFailed(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .serverError(let code): return "Stripe server error (HTTP \(code))"
        case .invalidResponse: return "Invalid response from Stripe server"
        case .paymentFailed(let msg): return "Payment failed: \(msg)"
        case .notConfigured: return "Stripe backend URL not configured"
        }
    }
}
