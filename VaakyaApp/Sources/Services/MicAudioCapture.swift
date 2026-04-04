#if os(macOS)
@preconcurrency import AVFoundation
import os

/// Thread-safe audio sample buffer. NOT @MainActor — accessed from RT audio thread.
/// Uses os_unfair_lock for minimal latency on the real-time audio render thread.
final class AudioSampleBuffer: @unchecked Sendable {
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    private var buffer: [Float] = []
    private var fullRecordingBuffer: [Float] = []
    private(set) var currentAmplitude: Float = 0

    init() { lock.initialize(to: os_unfair_lock()) }
    deinit { lock.deallocate() }

    func append(_ samples: [Float]) {
        // Compute RMS amplitude for waveform display
        if !samples.isEmpty {
            var rms: Float = 0
            for s in samples { rms += s * s }
            rms = sqrt(rms / Float(samples.count))
            currentAmplitude = min(1.0, rms * 5.0) // Scale up for visibility
        }
        os_unfair_lock_lock(lock)
        buffer.append(contentsOf: samples)
        fullRecordingBuffer.append(contentsOf: samples)
        os_unfair_lock_unlock(lock)
    }

    func drain() -> [Float] {
        os_unfair_lock_lock(lock)
        let result = buffer
        buffer.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(lock)
        return result
    }

    func allSamples() -> [Float] {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return fullRecordingBuffer
    }

    func reset() {
        os_unfair_lock_lock(lock)
        buffer.removeAll(keepingCapacity: true)
        fullRecordingBuffer.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(lock)
    }
}

/// Captures microphone audio using AVAudioEngine with VoiceProcessingIO enabled.
/// VoiceProcessingIO provides hardware-accelerated AEC, AGC, and noise suppression.
///
/// Key insight: After enabling VP, the input node outputs multi-channel deinterleaved
/// audio (typically 3ch @ 44100Hz). Channel 0 is the echo-cancelled mic signal.
/// We extract channel 0 and resample to 16kHz mono for WhisperKit.
@MainActor
@Observable
final class MicAudioCapture {
    var isCapturing = false

    private var audioEngine: AVAudioEngine?
    private let sampleBuffer = AudioSampleBuffer()
    private var configObserver: Any?

    /// Target sample rate for WhisperKit.
    private let targetSampleRate: Double = 16000.0

    /// Start capturing microphone audio via plain AVAudioEngine.
    /// No VoiceProcessingIO — it ducks other apps' audio and is designed for VoIP, not recording.
    /// Echo handling: mic and system are transcribed separately. Transcript-level dedup
    /// removes echo segments (Jaccard similarity within 3s window). This is the same
    /// approach Granola uses in production.
    func startCapture() throws {
        guard !isCapturing else { return }

        sampleBuffer.reset()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Plain mic capture — no VoiceProcessingIO.
        // VP is wrong for recording apps: it ducks Slack/Zoom/YouTube volume.
        // Echo is handled at transcript level via separate-stream dedup.

        let nativeFormat = inputNode.outputFormat(forBus: 0)
        print("[MicAudioCapture] Mic format: \(nativeFormat) (no VP, no ducking)")

        // 3. Build intermediate mono format at native sample rate (for converter input)
        guard let monoNativeFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: nativeFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("[MicAudioCapture] Failed to create mono native format")
            return
        }

        // 4. Build target format: 16 kHz mono Float32 (what WhisperKit expects)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("[MicAudioCapture] Failed to create target format")
            return
        }

        // 5. Create converter: mono @ VP sample rate → mono @ 16kHz
        //    The converter is STATEFUL — reuse across callbacks for smooth resampling.
        guard let converter = AVAudioConverter(from: monoNativeFormat, to: targetFormat) else {
            print("[MicAudioCapture] Failed to create AVAudioConverter from \(monoNativeFormat) to \(targetFormat)")
            return
        }

        let buffer = sampleBuffer

        // 6. Install tap with nil format — accept whatever VP outputs.
        //    The callback receives the multi-channel deinterleaved buffer.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { pcmBuffer, _ in
            guard pcmBuffer.frameLength > 0,
                  let channelData = pcmBuffer.floatChannelData else { return }

            let frameCount = Int(pcmBuffer.frameLength)

            // 7. Extract channel 0 only — the echo-cancelled mic signal.
            //    Additional channels are internal VP reference signals.
            let channel0 = UnsafeBufferPointer(start: channelData[0], count: frameCount)

            // 8. Create a mono buffer at VP sample rate with channel 0 data
            guard let monoBuf = AVAudioPCMBuffer(
                pcmFormat: monoNativeFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            ) else { return }
            monoBuf.frameLength = AVAudioFrameCount(frameCount)
            if let monoData = monoBuf.floatChannelData {
                guard let srcAddr = channel0.baseAddress else { return }
                monoData[0].initialize(from: srcAddr, count: frameCount)
            }

            // 9. Resample: mono @ VP rate → mono @ 16kHz using AVAudioConverter
            let ratio = 16000.0 / monoNativeFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio) + 1
            guard let outputBuf = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            var hasData = true
            converter.convert(to: outputBuf, error: &error) { _, outStatus in
                if hasData {
                    hasData = false
                    outStatus.pointee = .haveData
                    return monoBuf
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }

            if error != nil { return }

            guard let floatData = outputBuf.floatChannelData,
                  outputBuf.frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(
                start: floatData[0],
                count: Int(outputBuf.frameLength)
            ))
            buffer.append(samples)
        }

        // 10. Observe engine configuration changes — VP can trigger engine reconfig.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak engine] _ in
            guard let engine, !engine.isRunning else { return }
            try? engine.start()
            print("[MicAudioCapture] Engine restarted after configuration change")
        }

        try engine.start()
        audioEngine = engine
        isCapturing = true
        print("[MicAudioCapture] Started capturing (plain AVAudioEngine, \(nativeFormat.sampleRate)Hz → 16kHz, \(nativeFormat.channelCount)ch)")
    }

    /// Stop capturing and release resources.
    func stopCapture() {
        guard isCapturing else { return }
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCapturing = false
        print("[MicAudioCapture] Stopped. Total samples: \(sampleBuffer.allSamples().count) (\(String(format: "%.1f", Double(sampleBuffer.allSamples().count) / targetSampleRate))s)")
    }

    /// Current audio amplitude (0.0-1.0) for waveform display.
    var currentAmplitude: Float { sampleBuffer.currentAmplitude }

    /// Drain chunk samples (cleared after drain).
    func drainSamples() -> [Float] {
        sampleBuffer.drain()
    }

    /// All samples from entire recording (never drained).
    func allSamples() -> [Float] {
        sampleBuffer.allSamples()
    }
}
#endif
