import Foundation
import UIKit

enum AppError: Error, LocalizedError, Identifiable {
    case recording(RecordingError)
    case transcription(TranscriptionError)
    case storage(StorageError)
    case encryption(EncryptionError)
    case modelDownload(ModelDownloadError)
    case patternDetection(PatternError)
    case subscription(SubscriptionError)
    case backup(BackupError)
    case general(String)

    var id: String { errorDescription ?? "unknown" }

    var errorDescription: String? {
        switch self {
        case .recording(let e): return e.localizedDescription
        case .transcription(let e): return e.localizedDescription
        case .storage(let e): return e.localizedDescription
        case .encryption(let e): return e.localizedDescription
        case .modelDownload(let e): return e.localizedDescription
        case .patternDetection(let e): return e.localizedDescription
        case .subscription(let e): return e.localizedDescription
        case .backup(let e): return e.localizedDescription
        case .general(let msg): return msg
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .recording(let e):
            switch e {
            case .microphonePermissionDenied: return "Enable microphone access in Settings > Privacy > Microphone"
            case .audioEngineError: return "Close other apps using audio and try again"
            case .tooShort: return "Recording was too short. Minimum is 1 second"
            }
        case .transcription:
            return "The transcription model may still be downloading. Try again in a few minutes"
        case .storage:
            return "Free up storage space or export old entries"
        case .encryption:
            return "Please re-enter your encryption passphrase. If the problem persists, restore from backup"
        case .modelDownload(let e):
            switch e {
            case .invalidURL: return "Invalid model URL. Please update the app"
            case .insufficientStorage: return "Free up at least 3GB of storage"
            case .downloadFailed: return "Check your internet connection and try again"
            case .corruptedDownload: return "The model file is corrupted. Download it again"
            }
        case .patternDetection:
            return "Pattern detection failed. This doesn't affect your recordings"
        case .subscription(let e):
            switch e {
            case .productNotFound: return "Unable to load subscription options. Try again later"
            case .verificationFailed: return "Purchase verification failed. Please restore purchases"
            case .userCancelled: return nil
            case .pending: return "Your purchase is pending approval"
            case .unknown: return "An unexpected error occurred. Try again"
            }
        case .backup:
            return "Check your iCloud account and try again"
        case .general:
            return nil
        }
    }

    var isUserFacing: Bool {
        switch self {
        case .patternDetection: return false
        case .general(let s) where s.contains("internal"): return false
        default: return true
        }
    }

    var category: ErrorCategory {
        switch self {
        case .recording: return .recoverable
        case .transcription: return .retryable
        case .storage: return .recoverable
        case .encryption: return .recoverable
        case .modelDownload: return .retryable
        case .patternDetection: return .silent
        case .subscription: return .recoverable
        case .backup: return .retryable
        case .general: return .recoverable
        }
    }
}

enum PatternError: LocalizedError {
    case insufficientData
    case analysisFailed(String)

    var errorDescription: String? {
        switch self {
        case .insufficientData: return "Not enough journal entries for pattern detection"
        case .analysisFailed(let msg): return "Pattern analysis failed: \(msg)"
        }
    }
}

enum ErrorCategory {
    case silent
    case retryable
    case recoverable
    case fatal
}

final class ErrorHandler: @unchecked Sendable {
    static let shared = ErrorHandler()

    private init() {}

    func handle(_ error: Error, context: String = #function) {
        let appError: AppError
        if let ae = error as? AppError { appError = ae }
        else { appError = .general(error.localizedDescription) }

        if appError.isUserFacing {
            DispatchQueue.main.async {
                self.showAlert(for: appError)
            }
        }

        Logger.shared.error(context, appError.errorDescription ?? "Unknown error")
    }

    private func showAlert(for error: AppError) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return }

        let alert = UIAlertController(
            title: "Something went wrong",
            message: [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        root.present(alert, animated: true)
    }
}
