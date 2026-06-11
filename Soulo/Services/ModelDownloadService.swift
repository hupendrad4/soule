import Foundation

final class ModelDownloadService: Sendable {
    static let shared = ModelDownloadService()

    private let fileManager = FileManager.default

    private var modelsDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appending(path: "models")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    enum Model: String, CaseIterable {
        case whisper = "ggml-tiny.en.bin"
        case phi3 = "phi-3-mini-q4.onnx"
        case emotion2vec = "emotion2vec.onnx"

        var remoteURL: String {
            switch self {
            case .whisper:
                return "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"
            case .phi3:
                return "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/resolve/main/phi-3-mini-4k-instruct-q4.onnx"
            case .emotion2vec:
                return "https://huggingface.co/facebook/emotion2vec/resolve/main/emotion2vec.onnx"
            }
        }

        var expectedSize: Int64 {
            switch self {
            case .whisper: return 77_000_000
            case .phi3: return 2_300_000_000
            case .emotion2vec: return 50_000_000
            }
        }

        var isRequired: Bool { self != .phi3 } // phi3 is optional (degraded mode works without)
    }

    // MARK: - Status

    func isModelDownloaded(_ model: Model) -> Bool {
        fileManager.fileExists(atPath: modelsDir.appending(path: model.rawValue).path)
    }

    var allModelsDownloaded: Bool {
        Model.allCases.allSatisfy { isModelDownloaded($0) }
    }

    var hasRequiredModels: Bool {
        Model.allCases.filter(\.isRequired).allSatisfy { isModelDownloaded($0) }
    }

    func modelPath(_ model: Model) -> String {
        modelsDir.appending(path: model.rawValue).path
    }

    // MARK: - Download

    func ensureModelsDownloaded() async throws {
        if !hasRequiredModels {
            for model in Model.allCases where model.isRequired && !isModelDownloaded(model) {
                try await downloadModel(model)
            }
        }
    }

    func downloadModel(_ model: Model) async throws {
        guard let url = URL(string: model.remoteURL) else { throw ModelDownloadError.invalidURL(model.rawValue) }

        let destination = modelsDir.appending(path: model.rawValue)
        let tempDestination = destination.appendingPathExtension("tmp")

        Logger.shared.info("ModelDownload", "Downloading \(model.rawValue)...")

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelDownloadError.downloadFailed(model.rawValue)
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)

        let attributes = try fileManager.attributesOfItem(atPath: destination.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        guard fileSize > model.expectedSize / 2 else {
            try fileManager.removeItem(at: destination)
            throw ModelDownloadError.corruptedDownload(model.rawValue)
        }

        Logger.shared.info("ModelDownload", "\(model.rawValue) downloaded (\(fileSize) bytes)")
    }

    func deleteModel(_ model: Model) throws {
        let url = modelsDir.appending(path: model.rawValue)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func totalDownloadSize() -> Int64 {
        Model.allCases.filter { !isModelDownloaded($0) }.reduce(0) { $0 + $1.expectedSize }
    }
}

enum ModelDownloadError: Error, LocalizedError {
    case invalidURL(String)
    case downloadFailed(String)
    case corruptedDownload(String)
    case insufficientStorage

    var errorDescription: String? {
        switch self {
        case .invalidURL(let name): return "Invalid URL for model: \(name)"
        case .downloadFailed(let name): return "Failed to download model: \(name)"
        case .corruptedDownload(let name): return "Downloaded model is corrupted: \(name)"
        case .insufficientStorage: return "Not enough storage for model download"
        }
    }
}
