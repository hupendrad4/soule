import Foundation
import OSLog

final class Logger: @unchecked Sendable {
    static let shared = Logger()

    private let osLog: OSLog

    private init() {
        osLog = OSLog(subsystem: "com.soulo.app", category: "general")
    }

    func info(_ category: String, _ message: String) {
        os_log("[%{public}@] %{public}@", log: osLog, type: .info, category, message)
    }

    func warn(_ category: String, _ message: String) {
        os_log("[%{public}@] %{public}@", log: osLog, type: .error, category, message)
    }

    func error(_ category: String, _ message: String) {
        os_log("[%{public}@] %{public}@", log: osLog, type: .fault, category, message)
    }

    func debug(_ category: String, _ message: String) {
        #if DEBUG
        os_log("[%{public}@] %{public}@", log: osLog, type: .debug, category, message)
        #endif
    }

    func logMetrics(_ category: String, metrics: [String: Any]) {
        let message = metrics.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        info(category, "[METRICS] \(message)")
    }
}
