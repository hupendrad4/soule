import Foundation

struct JournalEntry: Identifiable, Codable, Sendable {
    let id: String
    let timestamp: TimeInterval
    let timezoneOffset: Int
    let durationMs: Int

    var audioFormat: String
    var audioEncrypted: Bool
    var audioFileSize: Int?

    var transcript: String?
    var transcriptStatus: ProcessingStatus
    var transcriptError: String?
    var transcriptMs: Int?

    var biomarkersJson: String?
    var biomarkersStatus: ProcessingStatus
    var biomarkersError: String?

    var emotionJson: String?
    var emotionStatus: ProcessingStatus
    var emotionError: String?

    var topicsJson: String?
    var topicsStatus: ProcessingStatus
    var topicsError: String?

    let appVersion: String
    let deviceModel: String?
    let osVersion: String?
    let createdAt: TimeInterval
    var updatedAt: TimeInterval

    init(
        id: String = UUID().uuidString,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 60,
        durationMs: Int,
        audioFormat: String = "aac",
        audioEncrypted: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.timezoneOffset = timezoneOffset
        self.durationMs = durationMs
        self.audioFormat = audioFormat
        self.audioEncrypted = audioEncrypted
        self.transcriptStatus = .pending
        self.biomarkersStatus = .pending
        self.emotionStatus = .pending
        self.topicsStatus = .pending
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        self.deviceModel = Self.deviceModel
        self.osVersion = UIDevice.current.systemVersion
        self.createdAt = Date().timeIntervalSince1970
        self.updatedAt = Date().timeIntervalSince1970
    }

    var biomarkers: VoiceBiomarkers? {
        get {
            guard let data = biomarkersJson?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(VoiceBiomarkers.self, from: data)
        }
        set {
            biomarkersJson = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    var emotion: EmotionalState? {
        get {
            guard let data = emotionJson?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(EmotionalState.self, from: data)
        }
        set {
            emotionJson = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    var topics: [TopicAnalysis]? {
        get {
            guard let data = topicsJson?.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([TopicAnalysis].self, from: data)
        }
        set {
            topicsJson = newValue.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
        }
    }

    private static var deviceModel: String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.compactMap { $0.value as? Int8 }.map { String(UnicodeScalar(UInt8($0))) }.joined()
            .trimmingCharacters(in: .controlCharacters)
    }
}

enum ProcessingStatus: String, Codable {
    case pending, processing, done, failed
}
