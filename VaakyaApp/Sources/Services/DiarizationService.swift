import AVFoundation
import Foundation
import OnnxRuntimeBindings
import SpeakerKit

// MARK: - Speaker Model

struct Speaker: Identifiable, Codable, Sendable, Hashable {
    let id: String
    var label: String
    var color: String
    var talkTimeSeconds: Double

    static let colors: [String] = [
        "#34A853", "#4285F4", "#EA4335", "#FBBC04",
        "#9C27B0", "#FF6D00", "#00BCD4", "#795548",
    ]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Speaker, rhs: Speaker) -> Bool { lhs.id == rhs.id }
}

// MARK: - Transcript Segment (shared type for diarization alignment)
// This will be merged with Task 4's TranscriptionService definition.
// If TranscriptSegment is already defined elsewhere, remove this duplicate.

struct DiarizationSegment: Identifiable, Codable, Sendable {
    let id: String
    let start: Double
    let end: Double
    let text: String
    var speaker: String?
}

// MARK: - Diarization Backend Protocol

/// Protocol enabling backend swaps: ONNX pyannote, CoreML, energy-based VAD, or stub.
protocol DiarizationBackend: Sendable {
    /// Run speaker segmentation on audio and return speaker turns.
    func segment(audioURL: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerTurn]
}

/// A detected speaker turn from the diarization backend.
struct SpeakerTurn: Sendable {
    let start: Double
    let end: Double
    let speakerId: String
}

// MARK: - DiarizationService

@MainActor
@Observable
final class DiarizationService {
    static let shared = DiarizationService()

    var speakers: [Speaker] = []
    var isDiarizing = false
    var progress: Double = 0

    private var backend: DiarizationBackend
    private var speakerKit: SpeakerKit?

    /// Whether SpeakerKit models have been downloaded and loaded.
    private(set) var isSpeakerKitReady = false

    init(backend: DiarizationBackend? = nil) {
        self.backend = backend ?? EnergyBasedDiarizationBackend()
    }

    /// Download + load SpeakerKit models. Call during app startup.
    /// Falls back to ONNX or energy-based if SpeakerKit init fails.
    func setupSpeakerKit() async {
        do {
            let config = PyannoteConfig(download: true, load: true, verbose: false)
            let kit = try await SpeakerKit(config)
            self.speakerKit = kit
            self.backend = SpeakerKitBackend(speakerKit: kit)
            self.isSpeakerKitReady = true
        } catch {
            print("[DiarizationService] SpeakerKit setup failed, using fallback: \(error)")
            if OnnxPyannoteDiarizationBackend.isModelAvailable() {
                self.backend = OnnxPyannoteDiarizationBackend()
            }
            // else stays on EnergyBasedDiarizationBackend from init
        }
    }

    /// Apply user's backend preference from Settings.
    func applyBackendSetting(_ option: DiarizationBackendOption) async {
        switch option {
        case .speakerKit:
            if let kit = speakerKit {
                backend = SpeakerKitBackend(speakerKit: kit)
            } else {
                await setupSpeakerKit()
            }
        case .onnx:
            if OnnxPyannoteDiarizationBackend.isModelAvailable() {
                backend = OnnxPyannoteDiarizationBackend()
            } else {
                // Download the ONNX model first
                print("[DiarizationService] ONNX model not found, downloading...")
                do {
                    try await OnnxPyannoteDiarizationBackend.downloadModel { _ in }
                    backend = OnnxPyannoteDiarizationBackend()
                } catch {
                    print("[DiarizationService] ONNX model download failed: \(error)")
                }
            }
        case .energy:
            backend = EnergyBasedDiarizationBackend()
        }
        print("[DiarizationService] Backend changed to \(String(describing: type(of: backend)))")
    }

    /// Run speaker diarization on an audio file, then align results with transcript segments.
    func diarize(audioURL: URL, segments: inout [DiarizationSegment]) async throws {
        isDiarizing = true
        progress = 0
        defer { isDiarizing = false }
        let backendName = String(describing: type(of: backend))
        print("[DiarizationService] Starting diarization (\(backendName)) on \(segments.count) segments...")

        // Step 1: Run diarization backend to get speaker turns
        let turns = try await backend.segment(audioURL: audioURL) { [weak self] p in
            Task { @MainActor in
                self?.progress = p * 0.7
            }
        }
        progress = 0.7

        guard !turns.isEmpty else {
            progress = 1.0
            return
        }

        // Step 2: Build speaker map with labels and colors
        let uniqueSpeakerIds = Array(Set(turns.map(\.speakerId))).sorted()
        var speakerMap: [String: Speaker] = [:]
        for (index, speakerId) in uniqueSpeakerIds.enumerated() {
            let color = Speaker.colors[index % Speaker.colors.count]
            speakerMap[speakerId] = Speaker(
                id: speakerId,
                label: "Speaker \(index + 1)",
                color: color,
                talkTimeSeconds: 0
            )
        }

        // Step 3: Align speaker turns with transcript segments by timestamp midpoint overlap
        for i in segments.indices {
            let segMid = (segments[i].start + segments[i].end) / 2.0
            if let bestTurn = turns.first(where: { segMid >= $0.start && segMid <= $0.end }) {
                segments[i].speaker = speakerMap[bestTurn.speakerId]?.label
                speakerMap[bestTurn.speakerId]?.talkTimeSeconds += (segments[i].end - segments[i].start)
            }
        }

        speakers = Array(speakerMap.values).sorted { $0.talkTimeSeconds > $1.talkTimeSeconds }
        progress = 1.0
        print("[DiarizationService] Complete (\(backendName)) — \(speakers.count) speakers detected: \(speakers.map { "\($0.label) (\(Int($0.talkTimeSeconds))s)" }.joined(separator: ", "))")
    }

    /// Rename a speaker and propagate the change through all transcript segments.
    func renameSpeaker(id: String, newName: String, segments: inout [DiarizationSegment]) {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        let oldLabel = speakers[index].label
        speakers[index].label = newName
        for i in segments.indices where segments[i].speaker == oldLabel {
            segments[i].speaker = newName
        }
    }

    /// Convert speakers to SpeakerInfo for display, computing talk time percentages.
    func speakerInfos(totalDurationSeconds: Double) -> [SpeakerInfo] {
        speakers.map { speaker in
            SpeakerInfo(
                id: speaker.id,
                label: speaker.label,
                color: speaker.color,
                talkTimeSeconds: speaker.talkTimeSeconds,
                talkTimePercent: totalDurationSeconds > 0
                    ? (speaker.talkTimeSeconds / totalDurationSeconds) * 100.0
                    : 0
            )
        }
    }
}

// MARK: - ONNX pyannote Backend

/// Runs the pyannote segmentation-3.0 ONNX model for speaker diarization.
/// Model input: [1, num_samples] float32 (16kHz mono audio)
/// Model output: [1, num_frames, num_speakers] float32 (speaker probabilities per frame)
final class OnnxPyannoteDiarizationBackend: DiarizationBackend, @unchecked Sendable {

    /// pyannote segmentation-3.0 uses 10ms frames at 16kHz (160 samples per frame).
    private let sampleRate: Double = 16000
    private let frameDurationSeconds: Double = 0.01
    private let minimumTurnDuration: Double = 0.5

    func segment(audioURL: URL, onProgress: @Sendable (Double) -> Void) async throws -> [SpeakerTurn] {
        // Step 1: Load and preprocess audio to 16kHz mono float array
        onProgress(0.1)
        let audioSamples = try loadAudioAs16kHzMono(url: audioURL)
        onProgress(0.3)

        // Step 2: Run ONNX inference
        let frameProbabilities = try runOnnxInference(samples: audioSamples)
        onProgress(0.7)

        // Step 3: Post-process frame probabilities into speaker turns
        let turns = postProcess(frameProbabilities: frameProbabilities)
        onProgress(1.0)

        return turns
    }

    // MARK: - Audio Loading

    /// Load an audio file and convert to 16kHz mono Float32 samples.
    private func loadAudioAs16kHzMono(url: URL) throws -> [Float] {
        let sourceFile = try AVAudioFile(forReading: url)
        let sourceFormat = sourceFile.processingFormat

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw DiarizationError.audioFormatError("Cannot create 16kHz mono format")
        }

        // If source is already 16kHz mono, read directly
        if sourceFormat.sampleRate == sampleRate && sourceFormat.channelCount == 1 {
            let frameCount = AVAudioFrameCount(sourceFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
                throw DiarizationError.audioFormatError("Cannot create PCM buffer")
            }
            try sourceFile.read(into: buffer)
            return Array(UnsafeBufferPointer(
                start: buffer.floatChannelData?[0],
                count: Int(buffer.frameLength)
            ))
        }

        // Otherwise, use AVAudioConverter to resample
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw DiarizationError.audioFormatError("Cannot create audio converter from \(sourceFormat) to \(targetFormat)")
        }

        let ratio = sampleRate / sourceFormat.sampleRate
        let estimatedOutputFrames = AVAudioFrameCount(Double(sourceFile.length) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedOutputFrames) else {
            throw DiarizationError.audioFormatError("Cannot create output buffer")
        }

        let inputBlockSize: AVAudioFrameCount = 4096
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputBlockSize) else {
            throw DiarizationError.audioFormatError("Cannot create input buffer")
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            do {
                try sourceFile.read(into: inputBuffer)
                if inputBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return inputBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        if let error = error {
            throw DiarizationError.audioFormatError("Conversion error: \(error.localizedDescription)")
        }
        guard status != .error else {
            throw DiarizationError.audioFormatError("Audio converter returned error status")
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw DiarizationError.audioFormatError("No channel data in output buffer")
        }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
    }

    // MARK: - ONNX Inference

    /// Run the pyannote ONNX model and return frame-level speaker probabilities.
    /// Returns: Array of frames, each frame is an array of speaker probabilities.
    private func runOnnxInference(samples: [Float]) throws -> [[Float]] {
        // Locate the ONNX model in the app bundle or models directory
        let modelPath = try resolveModelPath()

        // Create ONNX Runtime environment and session
        let env = try ORTEnv(loggingLevel: .warning)
        let sessionOptions = try ORTSessionOptions()
        try sessionOptions.setGraphOptimizationLevel(.all)

        let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: sessionOptions)

        // Prepare input tensor: shape [1, num_samples]
        let numSamples = samples.count
        var inputData = samples
        let inputMutableData = NSMutableData(
            bytes: &inputData,
            length: numSamples * MemoryLayout<Float>.size
        )
        let inputTensor = try ORTValue(
            tensorData: inputMutableData,
            elementType: .float,
            shape: [1, NSNumber(value: numSamples)]
        )

        // Run inference
        let outputNames: Set<String> = ["output"]
        let outputs = try session.run(
            withInputs: ["input": inputTensor],
            outputNames: outputNames,
            runOptions: nil
        )

        guard let outputValue = outputs["output"] else {
            throw DiarizationError.inferenceError("No output tensor returned")
        }

        // Parse output tensor: shape [1, num_frames, num_speakers]
        let shapeInfo = try outputValue.tensorTypeAndShapeInfo()
        let shape = shapeInfo.shape.map { $0.intValue }
        guard shape.count == 3 else {
            throw DiarizationError.inferenceError("Unexpected output shape: \(shape)")
        }
        let numFrames = shape[1]
        let numSpeakers = shape[2]

        let outputData = try outputValue.tensorData()
        let floatCount = outputData.length / MemoryLayout<Float>.size
        var outputFloats = [Float](repeating: 0, count: floatCount)
        outputData.getBytes(&outputFloats, length: outputData.length)

        // Reshape into [numFrames][numSpeakers]
        var frameProbabilities: [[Float]] = []
        for f in 0..<numFrames {
            let offset = f * numSpeakers
            let frame = Array(outputFloats[offset..<(offset + numSpeakers)])
            frameProbabilities.append(frame)
        }

        return frameProbabilities
    }

    /// Resolve the path to the pyannote segmentation ONNX model.
    /// Checks app bundle first, then downloaded models directory.
    private func resolveModelPath() throws -> String {
        // Check app bundle
        if let bundlePath = Bundle.main.path(forResource: "segmentation-3.0", ofType: "onnx") {
            return bundlePath
        }

        // Check downloaded models directory
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DiarizationError.modelNotFound("Application Support directory not found")
        }
        let modelsDir = appSupport.appendingPathComponent("Vaakya/Models", isDirectory: true)
        let modelFile = modelsDir.appendingPathComponent("segmentation-3.0.onnx")
        if FileManager.default.fileExists(atPath: modelFile.path) {
            return modelFile.path
        }

        throw DiarizationError.modelNotFound(
            "pyannote segmentation-3.0.onnx not found. "
            + "Download from https://huggingface.co/pyannote/segmentation-3.0 "
            + "and place in app bundle or ~/Library/Application Support/Vaakya/Models/"
        )
    }

    // MARK: - Post-Processing

    /// Convert frame-level speaker probabilities into discrete speaker turns.
    /// For each frame, assigns the highest-probability speaker, merges consecutive
    /// same-speaker frames, and applies a minimum duration threshold.
    private func postProcess(frameProbabilities: [[Float]]) -> [SpeakerTurn] {
        guard !frameProbabilities.isEmpty else { return [] }

        // Step 1: For each frame, assign the speaker with highest probability
        var frameAssignments: [(speakerIndex: Int, isActive: Bool)] = []
        for frame in frameProbabilities {
            guard let maxProb = frame.max(), maxProb > 0.5 else {
                // Below activation threshold -- no speaker active
                frameAssignments.append((speakerIndex: -1, isActive: false))
                continue
            }
            let bestIdx = frame.firstIndex(of: maxProb) ?? 0
            frameAssignments.append((speakerIndex: bestIdx, isActive: true))
        }

        // Step 2: Merge consecutive frames with same speaker into turns
        var rawTurns: [(speakerIndex: Int, startFrame: Int, endFrame: Int)] = []
        var currentSpeaker = -1
        var currentStart = 0

        for (idx, assignment) in frameAssignments.enumerated() {
            let speaker = assignment.isActive ? assignment.speakerIndex : -1
            if speaker != currentSpeaker {
                if currentSpeaker >= 0 {
                    rawTurns.append((speakerIndex: currentSpeaker, startFrame: currentStart, endFrame: idx))
                }
                currentSpeaker = speaker
                currentStart = idx
            }
        }
        // Final turn
        if currentSpeaker >= 0 {
            rawTurns.append((speakerIndex: currentSpeaker, startFrame: currentStart, endFrame: frameAssignments.count))
        }

        // Step 3: Convert frame indices to time and apply minimum duration threshold
        var speakerTurns: [SpeakerTurn] = []
        for turn in rawTurns {
            let startTime = Double(turn.startFrame) * frameDurationSeconds
            let endTime = Double(turn.endFrame) * frameDurationSeconds
            let duration = endTime - startTime

            guard duration >= minimumTurnDuration else { continue }

            speakerTurns.append(SpeakerTurn(
                start: startTime,
                end: endTime,
                speakerId: "speaker_\(turn.speakerIndex)"
            ))
        }

        return speakerTurns
    }

    // MARK: - Model availability + download

    private static let modelFileName = "segmentation-3.0.onnx"
    private static let modelDownloadURL = "https://huggingface.co/pyannote/segmentation-3.0/resolve/main/onnx/model.onnx"

    static func modelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Vaakya/Models", isDirectory: true)
    }

    static func isModelAvailable() -> Bool {
        if Bundle.main.path(forResource: "segmentation-3.0", ofType: "onnx") != nil { return true }
        let modelFile = modelsDirectory().appendingPathComponent(modelFileName)
        return FileManager.default.fileExists(atPath: modelFile.path)
    }

    /// Download the pyannote segmentation model from HuggingFace with progress.
    static func downloadModel(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let dir = modelsDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destURL = dir.appendingPathComponent(modelFileName)

        guard let url = URL(string: modelDownloadURL) else {
            throw DiarizationError.modelNotFound("Invalid download URL")
        }

        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, _) = try await session.download(from: url)
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        onProgress(1.0)
        session.invalidateAndCancel()
    }
}

// MARK: - Download Progress Delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Handled by the async download call
    }
}

// MARK: - Energy-Based VAD Fallback Backend

/// Simple energy-based voice activity detection that detects speaker changes
/// by audio energy patterns and silence gaps. Less accurate than pyannote but
/// has zero dependencies beyond AVFoundation.
final class EnergyBasedDiarizationBackend: DiarizationBackend, @unchecked Sendable {

    private let sampleRate: Double = 16000
    private let frameSize: Int = 1600  // 100ms frames at 16kHz
    private let silenceThreshold: Float = 0.01
    private let minimumSpeechDuration: Double = 0.5
    private let minimumSilenceForSplit: Double = 0.3

    func segment(audioURL: URL, onProgress: @Sendable (Double) -> Void) async throws -> [SpeakerTurn] {
        onProgress(0.1)

        // Load audio (reuse the same approach as ONNX backend)
        let sourceFile = try AVAudioFile(forReading: audioURL)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw DiarizationError.audioFormatError("Cannot create format")
        }

        let frameCount = AVAudioFrameCount(sourceFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw DiarizationError.audioFormatError("Cannot create buffer")
        }
        try sourceFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw DiarizationError.audioFormatError("No channel data")
        }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        onProgress(0.3)

        // Compute RMS energy per frame
        let totalFrames = samples.count / frameSize
        var energies: [Float] = []
        for i in 0..<totalFrames {
            let start = i * frameSize
            let end = min(start + frameSize, samples.count)
            let slice = samples[start..<end]
            let rms = sqrt(slice.map { $0 * $0 }.reduce(0, +) / Float(slice.count))
            energies.append(rms)
        }
        onProgress(0.5)

        // Detect speech regions (energy above silence threshold)
        var speechRegions: [(start: Int, end: Int)] = []
        var inSpeech = false
        var regionStart = 0

        for (i, energy) in energies.enumerated() {
            if energy > silenceThreshold {
                if !inSpeech {
                    regionStart = i
                    inSpeech = true
                }
            } else {
                if inSpeech {
                    speechRegions.append((start: regionStart, end: i))
                    inSpeech = false
                }
            }
        }
        if inSpeech {
            speechRegions.append((start: regionStart, end: energies.count))
        }
        onProgress(0.7)

        // Merge close regions and assign alternating speaker IDs based on silence gaps
        var turns: [SpeakerTurn] = []
        var currentSpeakerId = 0

        for (idx, region) in speechRegions.enumerated() {
            let startTime = Double(region.start * frameSize) / sampleRate
            let endTime = Double(region.end * frameSize) / sampleRate
            let duration = endTime - startTime

            guard duration >= minimumSpeechDuration else { continue }

            // Check if there's a significant gap from the previous region
            if idx > 0 {
                let prevEnd = Double(speechRegions[idx - 1].end * frameSize) / sampleRate
                let gap = startTime - prevEnd
                if gap >= minimumSilenceForSplit {
                    // Alternate speaker on significant silence gaps
                    currentSpeakerId = (currentSpeakerId + 1) % 2
                }
            }

            turns.append(SpeakerTurn(
                start: startTime,
                end: endTime,
                speakerId: "speaker_\(currentSpeakerId)"
            ))
        }

        onProgress(1.0)
        return turns
    }
}

// MARK: - SpeakerKit Backend (wraps WhisperKit's SpeakerKit into our DiarizationBackend protocol)

final class SpeakerKitBackend: DiarizationBackend, @unchecked Sendable {
    private let speakerKit: SpeakerKit

    init(speakerKit: SpeakerKit) {
        self.speakerKit = speakerKit
    }

    func segment(audioURL: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerTurn] {
        onProgress(0.1)

        // Load audio as 16kHz mono
        let sourceFile = try AVAudioFile(forReading: audioURL)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw DiarizationError.audioFormatError("Cannot create 16kHz format")
        }

        let converter = AVAudioConverter(from: sourceFile.processingFormat, to: format)
        let ratio = 16000.0 / sourceFile.processingFormat.sampleRate
        let outputFrames = AVAudioFrameCount(Double(sourceFile.length) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrames) else {
            throw DiarizationError.audioFormatError("Cannot create buffer")
        }

        if sourceFile.processingFormat.sampleRate == 16000 && sourceFile.processingFormat.channelCount == 1 {
            try sourceFile.read(into: outputBuffer)
        } else {
            guard let converter else { throw DiarizationError.audioFormatError("Cannot create converter") }
            let inputBlockSize: AVAudioFrameCount = 4096
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: inputBlockSize) else {
                throw DiarizationError.audioFormatError("Cannot create input buffer")
            }
            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                do {
                    try sourceFile.read(into: inputBuffer)
                    if inputBuffer.frameLength == 0 { outStatus.pointee = .endOfStream; return nil }
                    outStatus.pointee = .haveData
                    return inputBuffer
                } catch { outStatus.pointee = .endOfStream; return nil }
            }
            if let error { throw DiarizationError.audioFormatError("Conversion: \(error)") }
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw DiarizationError.audioFormatError("No channel data")
        }
        let audioArray = Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
        onProgress(0.3)

        // Run SpeakerKit diarization
        let result = try await speakerKit.diarize(audioArray: audioArray) { progress in
            let fraction = 0.3 + (progress.fractionCompleted * 0.7)
            onProgress(fraction)
        }
        onProgress(1.0)

        // Convert SpeakerKit segments to our SpeakerTurn format
        return result.segments.map { segment in
            SpeakerTurn(
                start: Double(segment.startTime),
                end: Double(segment.endTime),
                speakerId: "speaker_\(segment.speaker.speakerId ?? 0)"
            )
        }
    }
}

// MARK: - Errors

enum DiarizationError: LocalizedError {
    case modelNotFound(String)
    case audioFormatError(String)
    case inferenceError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let msg): return "Model not found: \(msg)"
        case .audioFormatError(let msg): return "Audio format error: \(msg)"
        case .inferenceError(let msg): return "Inference error: \(msg)"
        }
    }
}
