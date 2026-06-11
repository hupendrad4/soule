import UIKit

final class HapticManager: Sendable {
    static let shared = HapticManager()

    private init() {}

    func play(_ feedback: FeedbackType) {
        Task { @MainActor in
            switch feedback {
            case .recordStart:
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.prepare()
                impact.impactOccurred()
            case .recordStop:
                let impact = UIImpactFeedbackGenerator(style: .heavy)
                impact.prepare()
                impact.impactOccurred()
            case .success:
                let notification = UINotificationFeedbackGenerator()
                notification.prepare()
                notification.notificationOccurred(.success)
            case .error:
                let notification = UINotificationFeedbackGenerator()
                notification.prepare()
                notification.notificationOccurred(.error)
            case .selection:
                let selection = UISelectionFeedbackGenerator()
                selection.prepare()
                selection.selectionChanged()
            case .warning:
                let notification = UINotificationFeedbackGenerator()
                notification.prepare()
                notification.notificationOccurred(.warning)
            case .processingComplete:
                let impact = UIImpactFeedbackGenerator(style: .soft)
                impact.prepare()
                impact.impactOccurred()
                let notification = UINotificationFeedbackGenerator()
                notification.prepare()
                notification.notificationOccurred(.success)
            }
        }
    }

    enum FeedbackType {
        case recordStart
        case recordStop
        case success
        case error
        case selection
        case warning
        case processingComplete
    }
}
