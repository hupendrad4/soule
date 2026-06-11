import Foundation

final class MemoryManager: @unchecked Sendable {
    static let shared = MemoryManager()

    private var memoryWarningObserver: NSObjectProtocol?
    private var memoryUsage: UInt64 = 0

    private init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    deinit {
        if let obs = memoryWarningObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    var currentMemoryUsageMB: Int {
        Int(memoryUsage / 1024 / 1024)
    }

    func trackMemory() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            memoryUsage = info.phys_footprint
        }
    }

    private func handleMemoryWarning() {
        Logger.shared.warn("Memory", "Memory warning received. Usage: \(currentMemoryUsageMB)MB")
        URLCache.shared.removeAllCachedResponses()
        NotificationCenter.default.post(name: .memoryWarning, object: currentMemoryUsageMB)
    }
}

extension Notification.Name {
    static let memoryWarning = Notification.Name("com.soulo.memoryWarning")
}
