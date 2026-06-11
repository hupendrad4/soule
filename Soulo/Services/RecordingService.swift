import Foundation
import AVFoundation

final class RecordingService: @unchecked Sendable {
    static let shared = RecordingService()

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private let audioURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appending(path: "audio_raw")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(UUID().uuidString).wav")
    }()

    private(set) var isRecording = false
    private(set) var currentDuration: TimeInterval = 0
    private var startTime: Date?
    private var timer: Timer?

    private init() {}

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .denied: throw RecordingError.microphonePermissionDenied
        case .undetermined: session.requestRecordPermission { _ in }
        case .granted: break
        @unknown default: break
        }

        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]

        audioFile = try AVAudioFile(forWriting: audioURL, settings: settings, commonFormat: .pcmFormatInt16, interleaved: false)
        startTime = Date()
        isRecording = true

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let start = self?.startTime else { return }
            self?.currentDuration = Date().timeIntervalSince(start)
        }
    }

    func stopRecording() async throws -> (url: URL, duration: TimeInterval) {
        timer?.invalidate()
        timer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        audioFile = nil
        isRecording = false

        let duration = currentDuration
        guard duration >= 1 else {
            try FileManager.default.removeItem(at: audioURL)
            isRecording = false
            throw RecordingError.tooShort
        }
        currentDuration = 0
        return (audioURL, duration)
    }

    func cleanupRawAudio() {
        try? FileManager.default.removeItem(at: audioURL)
    }
}

enum RecordingError: LocalizedError {
    case microphonePermissionDenied
    case tooShort
    case audioEngineError

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied: return "Microphone access denied. Enable in Settings > Privacy."
        case .tooShort: return "Recording too short (minimum 1 second)"
        case .audioEngineError: return "Audio engine failed to start"
        }
    }
}
