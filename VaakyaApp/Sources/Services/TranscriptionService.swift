import Foundation
import AVFoundation
import WhisperKit

struct TranscriptSegment: Identifiable, Codable, Sendable {
    let id: String
    let start: Double      // seconds
    let end: Double         // seconds
    let text: String
    var speaker: String?    // filled later by diarization
    var isConfirmed: Bool   // true = confirmed by streaming, false = tentative

    init(start: Double, end: Double, text: String, speaker: String? = nil, isConfirmed: Bool = true) {
        self.id = UUID().uuidString
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.isConfirmed = isConfirmed
    }

    var startFormatted: String { Self.formatTime(start) }
    var endFormatted: String { Self.formatTime(end) }

    private static func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

@MainActor
@Observable
final class TranscriptionService {
    static let shared = TranscriptionService()

    var segments: [TranscriptSegment] = []
    var isTranscribing = false
    var isStreaming = false
    var progress: Double = 0
    var error: String?
    var currentStreamingText: String = ""

    /// The URL of the audio file saved from WhisperKit's buffer after streaming ends.
    /// Use this for playback when AudioRecorder is not running alongside streaming.
    private(set) var lastStreamingAudioURL: URL?

    private var whisperKit: WhisperKit?
    private var streamTranscriber: AudioStreamTranscriber?
    private var streamingTask: Task<Void, Never>?

    #if os(macOS)
    /// System audio capture for recording the other side of calls.
    let systemAudioCapture = SystemAudioCapture()

    /// Mic capture via AVAudioEngine for chunk-based transcription mode.
    let micCapture = MicAudioCapture()

    /// Timer that fires every chunk interval to transcribe mixed audio.
    private var chunkTimer: Timer?

    /// Accumulated duration of all previously transcribed chunks (for timestamp offsets).
    private var chunkTimeOffset: Double = 0

    /// Whether a chunk is currently being transcribed (prevents overlapping).
    private var isTranscribingChunk = false

    /// The interval in seconds between chunk transcriptions.
    private let chunkInterval: TimeInterval = 5.0

    /// Whether system audio capture is enabled by the user.
    var systemAudioEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.captureSystemAudio)
    }
    #endif

    private var recordingsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let docs = appSupport.appendingPathComponent("Vaakya")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    private var isLoadingModel = false

    /// Initialize WhisperKit with a specific model. Call once after model is downloaded.
    /// Guards against concurrent loads — second caller waits for the first to finish.
    func loadModel(_ modelName: String, directory: URL) async throws {
        // Already loaded
        if whisperKit != nil {
            print("[TranscriptionService] Model already loaded, skipping")
            return
        }
        // Another call is already loading — wait for it
        if isLoadingModel {
            print("[TranscriptionService] Model already loading, waiting...")
            while isLoadingModel {
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
            if whisperKit != nil { return }
        }

        isLoadingModel = true
        defer { isLoadingModel = false }
        error = nil
        print("[TranscriptionService] Loading model: \(modelName) from \(directory.path)")
        do {
            whisperKit = try await WhisperKit(
                model: modelName,
                downloadBase: directory,
                verbose: true,
                logLevel: .debug,
                load: true,
                download: true
            )
            print("[TranscriptionService] Model loaded successfully: \(modelName)")
        } catch {
            print("[TranscriptionService] Model loading failed: \(error)")
            throw error
        }
    }

    // MARK: - File-Based Transcription (existing)

    /// Transcribe an audio file. Populates `segments` with timestamped results.
    func transcribe(audioURL: URL) async throws {
        guard let kit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        isTranscribing = true
        progress = 0
        segments = []
        error = nil
        defer { isTranscribing = false }

        do {
            let results: [TranscriptionResult] = try await kit.transcribe(audioPath: audioURL.path)

            for result in results {
                for segment in result.segments {
                    let cleanedText = Self.stripWhisperTokens(segment.text)
                    guard !cleanedText.isEmpty else { continue }
                    let seg = TranscriptSegment(
                        start: Double(segment.start),
                        end: Double(segment.end),
                        text: cleanedText,
                        isConfirmed: true
                    )
                    segments.append(seg)
                }
            }

            progress = 1.0
        } catch {
            self.error = "Transcription failed: \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - Streaming Transcription

    /// Configure the audio session for streaming.
    /// WhisperKit's AudioProcessor uses AVAudioEngine, which requires .playAndRecord on iOS.
    /// This MUST be called before starting the stream, and AudioRecorder must NOT be running.
    private func configureAudioSessionForStreaming() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("[TranscriptionService] iOS audio session configured for streaming (.playAndRecord)")
        } catch {
            print("[TranscriptionService] Failed to configure audio session: \(error)")
        }
        #endif
    }

    /// Start live streaming transcription.
    ///
    /// When system audio is enabled (macOS), uses a chunk-based approach:
    /// mic + system audio are captured separately, mixed every ~5 seconds,
    /// and fed to WhisperKit's `transcribe(audioArray:)` for batch transcription.
    /// This ensures BOTH sides of a call are transcribed.
    ///
    /// When system audio is NOT enabled, falls back to WhisperKit's
    /// AudioStreamTranscriber which provides true real-time streaming from the mic.
    ///
    /// IMPORTANT: Do NOT run AudioRecorder (AVAudioRecorder) simultaneously.
    func startStreaming() async throws {
        guard whisperKit != nil else {
            print("[TranscriptionService] ❌ Cannot start streaming: model not loaded")
            throw TranscriptionError.modelNotLoaded
        }

        segments = []
        currentStreamingText = ""
        lastStreamingAudioURL = nil
        error = nil

        #if os(macOS)
        if systemAudioEnabled {
            print("[TranscriptionService] 🎤🔊 Starting CHUNK-BASED streaming (mic + system audio)")
            try await startChunkBasedStreaming()
            return
        }
        #endif

        print("[TranscriptionService] 🎤 Starting AudioStreamTranscriber (mic only)")
        try await startAudioStreamTranscriber()
    }

    // MARK: - Chunk-Based Streaming (mic + system audio)

    #if os(macOS)
    /// Start chunk-based streaming that captures both mic and system audio,
    /// mixes them, and transcribes every `chunkInterval` seconds.
    private func startChunkBasedStreaming() async throws {
        guard whisperKit != nil else {
            throw TranscriptionError.modelNotLoaded
        }

        configureAudioSessionForStreaming()

        chunkTimeOffset = 0
        isTranscribingChunk = false

        // 1. Start mic capture via our own AVAudioEngine
        var hasMic = false
        do {
            try micCapture.startCapture()
            hasMic = true
        } catch {
            print("[TranscriptionService] Mic capture failed (no mic connected?), continuing with system audio only: \(error)")
        }

        // 2. Start system audio capture via ScreenCaptureKit
        var hasSystemAudio = false
        do {
            try await systemAudioCapture.startCapture()
            hasSystemAudio = true
            print("[TranscriptionService] Chunk-based streaming: \(hasMic ? "mic + " : "")system audio started")
        } catch {
            print("[TranscriptionService] System audio capture failed: \(error)")
        }

        guard hasMic || hasSystemAudio else {
            throw TranscriptionError.noAudioSource
        }

        isStreaming = true

        // 3. Schedule periodic chunk transcription
        let timer = Timer(timeInterval: chunkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.transcribeCurrentChunk()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        chunkTimer = timer

        print("[TranscriptionService] Chunk-based streaming started (interval: \(chunkInterval)s)")
    }

    /// Drain mic + system buffers, mix, and transcribe the current chunk.
    private func transcribeCurrentChunk() async {
        guard !isTranscribingChunk else {
            print("[TranscriptionService] Chunk transcription still in progress, skipping")
            return
        }
        guard let kit = whisperKit else { return }

        isTranscribingChunk = true
        defer { isTranscribingChunk = false }

        // Drain samples from both sources.
        // Mic samples are already echo-cancelled by VoiceProcessingIO (hardware AEC).
        let micSamples = micCapture.drainSamples()
        let systemSamples = systemAudioCapture.drainSamples()

        guard !micSamples.isEmpty || !systemSamples.isEmpty else { return }

        let micDuration = Double(micSamples.count) / Double(WhisperKit.sampleRate)
        let sysDuration = Double(systemSamples.count) / Double(WhisperKit.sampleRate)
        print("[TranscriptionService] Transcribing chunk: mic=\(micSamples.count)(\(String(format: "%.1f", micDuration))s) sys=\(systemSamples.count)(\(String(format: "%.1f", sysDuration))s), offset=\(String(format: "%.1f", chunkTimeOffset))s [VoiceProcessingIO AEC]")

        currentStreamingText = "Processing..."

        let decodingOptions = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: "en",
            temperature: 0.0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 3,
            sampleLength: 224,
            topK: 5,
            usePrefillPrompt: true,
            usePrefillCache: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false,
            clipTimestamps: [],
            windowClipTime: 0,
            suppressBlank: false,
            supressTokens: [-1],
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6,
            concurrentWorkerCount: 0
        )

        do {
            // Transcribe mic and system audio SEPARATELY so both voices are captured
            // Then interleave segments with speaker labels

            var newSegments: [TranscriptSegment] = []

            // Transcribe mic audio (your voice)
            if !micSamples.isEmpty {
                let micResults: [TranscriptionResult] = try await kit.transcribe(
                    audioArray: micSamples,
                    decodeOptions: decodingOptions
                )
                for result in micResults {
                    for segment in result.segments {
                        let cleanedText = Self.stripWhisperTokens(segment.text)
                        guard !cleanedText.isEmpty else { continue }
                        newSegments.append(TranscriptSegment(
                            start: Double(segment.start) + chunkTimeOffset,
                            end: Double(segment.end) + chunkTimeOffset,
                            text: cleanedText,
                            speaker: "You",
                            isConfirmed: true
                        ))
                    }
                }
            }

            // Transcribe system audio (other person's voice)
            if !systemSamples.isEmpty {
                let sysResults: [TranscriptionResult] = try await kit.transcribe(
                    audioArray: systemSamples,
                    decodeOptions: decodingOptions
                )
                for result in sysResults {
                    for segment in result.segments {
                        let cleanedText = Self.stripWhisperTokens(segment.text)
                        guard !cleanedText.isEmpty else { continue }
                        newSegments.append(TranscriptSegment(
                            start: Double(segment.start) + chunkTimeOffset,
                            end: Double(segment.end) + chunkTimeOffset,
                            text: cleanedText,
                            speaker: "Remote",
                            isConfirmed: true
                        ))
                    }
                }
            }

            // Deduplicate: if mic and system produce similar text at similar timestamps,
            // keep only the system version (higher quality, no room noise).
            // This handles headphone bleed and speaker echo.
            let micSegs = newSegments.filter { $0.speaker == "You" }
            let sysSegs = newSegments.filter { $0.speaker == "Remote" }
            var deduped = sysSegs // Always keep system segments

            for micSeg in micSegs {
                let isDuplicate = sysSegs.contains { sysSeg in
                    // Same timeframe (within 3 seconds) AND similar text (>60% overlap)
                    abs(micSeg.start - sysSeg.start) < 3.0 &&
                    Self.textSimilarity(micSeg.text, sysSeg.text) > 0.6
                }
                if !isDuplicate {
                    deduped.append(micSeg) // Unique mic content — user was actually speaking
                } else {
                    print("[TranscriptionService] Dedup: dropped mic segment (echo/bleed): \"\(micSeg.text.prefix(50))\"")
                }
            }

            deduped.sort { $0.start < $1.start }
            segments.append(contentsOf: deduped)

            // Advance the time offset by the longer of the two sources
            let chunkDuration = max(micDuration, sysDuration)
            chunkTimeOffset += chunkDuration
            currentStreamingText = ""

            print("[TranscriptionService] Chunk transcribed. Total segments: \(segments.count)")
        } catch {
            print("[TranscriptionService] Chunk transcription error: \(error)")
            currentStreamingText = ""
            // Don't fail the whole stream; we'll try again next chunk.
            // Still advance the offset so timestamps stay in sync.
            chunkTimeOffset += max(micDuration, sysDuration)
        }
    }
    #endif

    // MARK: - AudioStreamTranscriber (mic-only fallback)

    /// Start streaming using WhisperKit's AudioStreamTranscriber.
    /// This provides true real-time streaming but only captures mic audio.
    private func startAudioStreamTranscriber() async throws {
        guard let kit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }
        guard let tokenizer = kit.tokenizer else {
            print("[TranscriptionService] Cannot start streaming: tokenizer not available")
            throw TranscriptionError.modelNotLoaded
        }

        configureAudioSessionForStreaming()

        print("[TranscriptionService] Creating AudioStreamTranscriber (mic-only mode)...")

        let transcriber = AudioStreamTranscriber(
            audioEncoder: kit.audioEncoder,
            featureExtractor: kit.featureExtractor,
            segmentSeeker: kit.segmentSeeker,
            textDecoder: kit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: kit.audioProcessor,
            decodingOptions: DecodingOptions(
                verbose: true,
                task: .transcribe,
                language: "en",
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 3,
                sampleLength: 224,
                topK: 5,
                usePrefillPrompt: true,
                usePrefillCache: true,
                detectLanguage: false,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                wordTimestamps: false,
                clipTimestamps: [],
                windowClipTime: 0,
                suppressBlank: false,
                supressTokens: [-1],
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                firstTokenLogProbThreshold: -1.5,
                noSpeechThreshold: 0.6,
                concurrentWorkerCount: 0
            ),
            requiredSegmentsForConfirmation: 2,
            silenceThreshold: 0.3,
            compressionCheckWindow: 60,
            useVAD: true,
            stateChangeCallback: { [weak self] oldState, newState in
                let confirmedCount = newState.confirmedSegments.count
                let unconfirmedCount = newState.unconfirmedSegments.count
                let bufferSize = newState.lastBufferSize
                let currentText = newState.currentText
                print("[TranscriptionService] Stream state: \(confirmedCount) confirmed, \(unconfirmedCount) unconfirmed, buffer=\(bufferSize), current=\"\(currentText.prefix(80))\"")
                Task { @MainActor [weak self] in
                    self?.handleStreamStateChange(oldState: oldState, newState: newState)
                }
            }
        )

        streamTranscriber = transcriber
        isStreaming = true

        print("[TranscriptionService] AudioStreamTranscriber created, starting stream...")

        // Start the streaming transcription in a background task.
        streamingTask = Task.detached { [transcriber] in
            do {
                try await transcriber.startStreamTranscription()
                print("[TranscriptionService] Stream transcription loop ended normally")
            } catch {
                print("[TranscriptionService] Streaming error: \(error)")
                Task { @MainActor [weak self] in
                    self?.error = "Streaming failed: \(error.localizedDescription)"
                    self?.isStreaming = false
                }
            }
        }
    }

    /// Stop live streaming and finalize all segments as confirmed.
    /// After stopping, saves the captured audio buffer to an M4A file.
    func stopStreaming(meetingId: String) async -> URL? {
        print("[TranscriptionService] Stopping streaming...")

        #if os(macOS)
        // Check if we were in chunk-based mode
        if chunkTimer != nil {
            return await stopChunkBasedStreaming(meetingId: meetingId)
        }
        #endif

        return await stopAudioStreamTranscriberStreaming(meetingId: meetingId)
    }

    #if os(macOS)
    /// Stop chunk-based streaming, transcribe any remaining audio, and save.
    private func stopChunkBasedStreaming(meetingId: String) async -> URL? {
        // Stop the chunk timer first
        chunkTimer?.invalidate()
        chunkTimer = nil

        // Transcribe any remaining audio in the buffers
        await transcribeCurrentChunk()

        // Collect ALL samples from the entire recording session (not just remainders)
        let allMicSamples = micCapture.allSamples()
        micCapture.stopCapture()

        let allSystemSamples = systemAudioCapture.allSamples()
        await systemAudioCapture.stopCapture()

        // Mix the full recording for saving
        var finalSamples: [Float] = []
        if !allMicSamples.isEmpty || !allSystemSamples.isEmpty {
            finalSamples = AudioMixer.mix(mic: allMicSamples, system: allSystemSamples)
        }

        isStreaming = false
        currentStreamingText = ""
        isTranscribingChunk = false

        // Mark all segments as confirmed
        segments = segments.map { seg in
            if !seg.isConfirmed {
                return TranscriptSegment(
                    start: seg.start, end: seg.end, text: seg.text,
                    speaker: seg.speaker, isConfirmed: true
                )
            }
            return seg
        }

        print("[TranscriptionService] Chunk-based streaming stopped. \(segments.count) total segments.")

        // Save any remaining audio (note: most audio was consumed by chunk transcription)
        if !finalSamples.isEmpty {
            let audioURL = saveAudioSamples(finalSamples, meetingId: meetingId)
            lastStreamingAudioURL = audioURL
            return audioURL
        }

        return nil
    }
    #endif

    /// Stop AudioStreamTranscriber-based streaming and save audio.
    private func stopAudioStreamTranscriberStreaming(meetingId: String) async -> URL? {
        // Grab the mic audio samples BEFORE stopping (stopStreamTranscription clears state)
        var micSamples: [Float] = whisperKit.map { Array($0.audioProcessor.audioSamples) } ?? []
        let micCount = micSamples.count
        print("[TranscriptionService] Captured \(micCount) mic samples (\(String(format: "%.1f", Double(micCount) / Double(WhisperKit.sampleRate)))s)")

        #if os(macOS)
        // Stop system audio capture and mix with mic audio
        if systemAudioCapture.isCapturing {
            await systemAudioCapture.stopCapture()
            let systemSamples = systemAudioCapture.audioSamples
            print("[TranscriptionService] Captured \(systemSamples.count) system audio samples")

            if !systemSamples.isEmpty {
                micSamples = AudioMixer.mix(mic: micSamples, system: systemSamples)
                print("[TranscriptionService] Mixed audio: \(micSamples.count) samples (\(String(format: "%.1f", Double(micSamples.count) / 16000.0))s)")
            }
        }
        #endif

        let audioSamples: [Float]? = micSamples.isEmpty ? nil : micSamples
        let sampleCount = audioSamples?.count ?? 0
        print("[TranscriptionService] Final audio: \(sampleCount) samples (\(String(format: "%.1f", Double(sampleCount) / Double(WhisperKit.sampleRate)))s)")

        await streamTranscriber?.stopStreamTranscription()
        streamingTask?.cancel()
        streamingTask = nil
        streamTranscriber = nil
        isStreaming = false
        currentStreamingText = ""

        // Mark all remaining segments as confirmed
        segments = segments.map { seg in
            if !seg.isConfirmed {
                return TranscriptSegment(
                    start: seg.start, end: seg.end, text: seg.text,
                    speaker: seg.speaker, isConfirmed: true
                )
            }
            return seg
        }

        print("[TranscriptionService] Streaming stopped. \(segments.count) total segments.")

        // Save captured audio to M4A file for playback
        if let samples = audioSamples, !samples.isEmpty {
            let audioURL = saveAudioSamples(samples, meetingId: meetingId)
            lastStreamingAudioURL = audioURL
            return audioURL
        }

        #if os(iOS)
        // Deactivate audio session after streaming ends
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        return nil
    }

    /// Legacy stop without saving audio — kept for backward compatibility.
    func stopStreaming() async {
        _ = await stopStreaming(meetingId: "unknown")
    }

    /// Save raw 16kHz float32 mono samples to an M4A file.
    private func saveAudioSamples(_ samples: [Float], meetingId: String) -> URL? {
        // Save directly into the meeting's LocalStore directory
        let meetingDir = recordingsDirectory
            .appendingPathComponent("meetings")
            .appendingPathComponent(meetingId)
        try? FileManager.default.createDirectory(at: meetingDir, withIntermediateDirectories: true)
        let fileURL = meetingDir.appendingPathComponent("audio.m4a")

        // Create an AVAudioPCMBuffer from the float samples
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(WhisperKit.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            print("[TranscriptionService] Failed to create audio format for saving")
            return nil
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            print("[TranscriptionService] Failed to create PCM buffer for saving")
            return nil
        }
        buffer.frameLength = frameCount

        // Copy samples into the buffer
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                guard let srcAddr = src.baseAddress else { return }
                channelData[0].initialize(from: srcAddr, count: samples.count)
            }
        }

        // Write to M4A using AVAudioFile
        do {
            let outputSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: Double(WhisperKit.sampleRate),
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: outputSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try audioFile.write(from: buffer)
            print("[TranscriptionService] Audio saved: \(fileURL.path) (\(String(format: "%.1f", Double(samples.count) / Double(WhisperKit.sampleRate)))s)")
            return fileURL
        } catch {
            print("[TranscriptionService] Failed to save audio: \(error)")
            return nil
        }
    }

    /// Handle state changes from AudioStreamTranscriber callback.
    private func handleStreamStateChange(oldState: AudioStreamTranscriber.State, newState: AudioStreamTranscriber.State) {
        // Build confirmed segments from the stream state
        var updatedSegments: [TranscriptSegment] = []

        for segment in newState.confirmedSegments {
            let cleanedText = Self.stripWhisperTokens(segment.text)
            guard !cleanedText.isEmpty else { continue }
            updatedSegments.append(TranscriptSegment(
                start: Double(segment.start),
                end: Double(segment.end),
                text: cleanedText,
                isConfirmed: true
            ))
        }

        // Add unconfirmed segments (shown dimmed in UI)
        for segment in newState.unconfirmedSegments {
            let cleanedText = Self.stripWhisperTokens(segment.text)
            guard !cleanedText.isEmpty else { continue }
            updatedSegments.append(TranscriptSegment(
                start: Double(segment.start),
                end: Double(segment.end),
                text: cleanedText,
                isConfirmed: false
            ))
        }

        segments = updatedSegments

        // Update the current in-progress text
        let cleanedCurrent = Self.stripWhisperTokens(newState.currentText)
        currentStreamingText = cleanedCurrent
    }

    // MARK: - Utilities

    /// Convert all segments to plain text for API storage/sync.
    func transcriptText() -> String {
        segments.map { seg in
            let speaker = seg.speaker.map { "[\($0)] " } ?? ""
            return "[\(seg.startFormatted)] \(speaker)\(seg.text)"
        }.joined(separator: "\n")
    }

    /// Whether a model is loaded and ready for transcription.
    var isModelLoaded: Bool {
        whisperKit != nil
    }

    /// Unload the current model to free memory.
    func unloadModel() {
        whisperKit = nil
    }

    /// Strip WhisperKit special tokens from segment text.
    static func stripWhisperTokens(_ text: String) -> String {
        var cleaned = text
        // Remove all <|...|> tokens (timestamps, language, task markers)
        cleaned = cleaned.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Word-level similarity between two texts (0.0 = completely different, 1.0 = identical).
    /// Used to detect duplicate transcriptions from mic bleed / echo.
    static func textSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(separator: " "))
        let wordsB = Set(b.lowercased().split(separator: " "))
        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 1.0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union) // Jaccard similarity
    }

    enum TranscriptionError: Error, LocalizedError {
        case modelNotLoaded
        case noAudioSource

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Whisper model not loaded. Download a model in Settings."
            case .noAudioSource:
                return "No audio source available. Connect a microphone or enable system audio capture in Settings."
            }
        }
    }
}
