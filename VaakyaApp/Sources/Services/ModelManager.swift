import Foundation
import WhisperKit

struct WhisperModelOption: Identifiable {
    let id: String       // e.g. "openai_whisper-large-v3_turbo"
    let displayName: String
    let size: String
    let quality: String  // "Best", "Good", "Fast"
    let isRecommended: Bool

    static let all: [WhisperModelOption] = [
        WhisperModelOption(id: "openai_whisper-large-v3_turbo", displayName: "Large V3 Turbo", size: "1.6 GB", quality: "Best", isRecommended: true),
        WhisperModelOption(id: "openai_whisper-small", displayName: "Small", size: "466 MB", quality: "Good", isRecommended: false),
        WhisperModelOption(id: "openai_whisper-base", displayName: "Base", size: "142 MB", quality: "Fast", isRecommended: false),
    ]
}

@MainActor
@Observable
final class ModelManager {
    var availableModels: [String] = []
    var downloadedModels: [String] = []
    var downloadProgress: Double = 0
    var isDownloading = false
    private static let modelKey = "vaakya_current_whisper_model"

    var currentModel: String? {
        didSet {
            UserDefaults.standard.set(currentModel, forKey: Self.modelKey)
            UserDefaults.standard.synchronize()
        }
    }
    var error: String?

    init() {
        self.currentModel = UserDefaults.standard.string(forKey: Self.modelKey)
    }

    private let modelsDirectory: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vaakya/Models")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Recommend a model based on device RAM and platform.
    var recommendedModel: String {
        let ram = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024) // GB
        #if os(macOS)
        return ram >= 16 ? "openai_whisper-large-v3_turbo" : "openai_whisper-base"
        #else
        return ram >= 8 ? "openai_whisper-small" : "openai_whisper-base"
        #endif
    }

    var recommendedModelSize: String {
        switch recommendedModel {
        case "openai_whisper-large-v3_turbo": return "1.6 GB"
        case "openai_whisper-small": return "466 MB"
        case "openai_whisper-base": return "142 MB"
        default: return "Unknown"
        }
    }

    /// Fetch the list of models available for download from WhisperKit's model hub.
    func loadAvailableModels() async {
        do {
            availableModels = try await WhisperKit.fetchAvailableModels()
        } catch {
            #if DEBUG
            print("Failed to fetch available models: \(error)")
            #endif
            // Fallback list when offline or API unreachable
            availableModels = ["openai_whisper-large-v3_turbo", "openai_whisper-base", "openai_whisper-small"]
        }
        refreshDownloaded()
    }

    /// Download a model using WhisperKit. This will download and prepare the model files.
    func downloadModel(_ modelName: String) async throws {
        isDownloading = true
        downloadProgress = 0
        error = nil
        defer { isDownloading = false }

        do {
            // WhisperKit handles download and caching internally.
            // Initializing with a model name triggers the download if not already present.
            let _ = try await WhisperKit(
                model: modelName,
                downloadBase: modelsDirectory,
                verbose: false,
                logLevel: .error,
                load: false,
                download: true
            )
            currentModel = modelName
            downloadProgress = 1.0
            refreshDownloaded()
        } catch {
            self.error = "Download failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Select a model. If not downloaded, triggers download automatically.
    /// On download failure, reverts to the previous model.
    func selectModel(_ modelName: String) async {
        let previousModel = currentModel
        currentModel = modelName

        if downloadedModels.contains(where: { $0 == modelName }) {
            // Already downloaded — just switch
            return
        }

        // Not downloaded — auto-download
        do {
            try await downloadModel(modelName)
        } catch {
            // Revert on failure
            currentModel = previousModel
            self.error = "Download failed — check your connection"
            // Auto-dismiss error after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                if self.error == "Download failed — check your connection" {
                    self.error = nil
                }
            }
        }
    }

    /// Delete a downloaded model from disk.
    func deleteModel(_ modelName: String) throws {
        // WhisperKit stores models in subdirectories named after the model
        let modelPath = modelsDirectory.appendingPathComponent(modelName)
        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }
        // Also check for the openai_ prefixed variant that WhisperKit uses
        let openaiPath = modelsDirectory.appendingPathComponent("openai_whisper-\(modelName)")
        if FileManager.default.fileExists(atPath: openaiPath.path) {
            try FileManager.default.removeItem(at: openaiPath)
        }
        refreshDownloaded()
        if currentModel == modelName { currentModel = nil }
    }

    /// Total disk space used by downloaded models.
    func diskUsage() -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return "0 MB" }

        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                totalBytes += Int64(size)
            }
        }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    /// The URL where models are stored on disk.
    var modelsDirectoryURL: URL { modelsDirectory }

    private func refreshDownloaded() {
        // WhisperKit stores models under models/argmaxinc/whisperkit-coreml/
        let whisperKitDir = modelsDirectory
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        downloadedModels = (try? FileManager.default.contentsOfDirectory(atPath: whisperKitDir.path))?.filter {
            !$0.hasPrefix(".")
        } ?? []
    }
}
