#if os(macOS)
import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

// MARK: - System Audio Capture via ScreenCaptureKit

/// Captures system audio output (what comes through speakers/headphones) using
/// ScreenCaptureKit's SCStream. This is the audio from the OTHER side of a call
/// (Zoom, Slack, Meet, Teams, etc.).
///
/// Requires macOS Screen Recording permission. There is no programmatic prompt —
/// the app must attempt an SCStream and, on failure, direct the user to
/// System Settings > Privacy & Security > Screen Recording.
@MainActor
@Observable
final class SystemAudioCapture: NSObject {
    var isCapturing = false
    var hasPermission = false
    var permissionError: String?

    /// Accumulated 16 kHz mono Float32 samples captured from system audio.
    /// Read (and optionally drain) from the main actor when mixing with mic audio.
    private(set) var audioSamples: [Float] = []

    private var stream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?

    // MARK: - Permission

    /// Check whether Screen Recording permission is granted by attempting to
    /// enumerate shareable content. If the call throws, permission is missing.
    func checkPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.current
            hasPermission = true
            return true
        } catch {
            hasPermission = false
            return false
        }
    }

    /// Open System Settings to the Screen Recording pane so the user can grant
    /// permission manually.
    func requestPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Capture

    /// Start capturing system audio. The stream captures the entire display but
    /// we only care about the audio portion.
    func startCapture() async throws {
        guard !isCapturing else { return }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            hasPermission = false
            permissionError = "Screen Recording permission not granted."
            throw SystemAudioCaptureError.permissionDenied
        }

        hasPermission = true

        guard let display = content.displays.first else {
            throw SystemAudioCaptureError.noDisplay
        }

        // We only need audio — filter to exclude all windows so no actual
        // screen content is captured (privacy).
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        // Audio settings
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1

        // Minimise video capture overhead — we don't need the screen pixels.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps
        config.showsCursor = false

        audioSamples = []
        let output = SystemAudioStreamOutput()
        streamOutput = output

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try scStream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await scStream.startCapture()

        stream = scStream
        isCapturing = true
        permissionError = nil
        print("[SystemAudioCapture] Started capturing system audio")
    }

    /// Stop capturing and flush pending samples.
    func stopCapture() async {
        guard let scStream = stream else { return }
        do {
            try await scStream.stopCapture()
        } catch {
            print("[SystemAudioCapture] Error stopping capture: \(error)")
        }
        stream = nil

        // Drain samples from the output into our buffer
        if let output = streamOutput {
            let pending = output.drainSamples()
            audioSamples.append(contentsOf: pending)
        }
        streamOutput = nil
        isCapturing = false
        print("[SystemAudioCapture] Stopped. Total samples: \(audioSamples.count) (\(String(format: "%.1f", Double(audioSamples.count) / 16000.0))s at 16 kHz)")
    }

    /// Drain all accumulated samples since the last drain. Thread-safe via main
    /// actor isolation on the caller side and a lock inside the stream output.
    func drainSamples() -> [Float] {
        guard let output = streamOutput else { return [] }
        return output.drainSamples()
    }

    /// Get all samples captured during the entire recording session (never drained).
    func allSamples() -> [Float] {
        guard let output = streamOutput else { return audioSamples }
        return output.allSamples()
    }

    // MARK: - Errors

    enum SystemAudioCaptureError: Error, LocalizedError {
        case permissionDenied
        case noDisplay

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Screen Recording permission is required to capture system audio."
            case .noDisplay:
                return "No display found for audio capture."
            }
        }
    }
}

// MARK: - SCStream Output Delegate

/// Receives CMSampleBuffers from ScreenCaptureKit, converts audio to 16 kHz
/// mono Float32, and accumulates in a thread-safe buffer.
///
/// Uses AVAudioConverter for proper anti-aliased resampling (replaces the old
/// linear-interpolation resampler that caused aliasing artifacts).
final class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    private let lock = NSLock()
    private var buffer: [Float] = []
    private var fullRecordingBuffer: [Float] = []

    /// Target sample rate for WhisperKit.
    private let targetSampleRate: Double = 16000.0

    /// Safety cap: 2 hours at 16 kHz. Recordings shouldn't reach this, but guard against runaway growth.
    private let maxRecordingBufferSize = 16000 * 7200

    /// Cached converter — created lazily on first audio callback once we know the source format.
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }

        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return
        }

        let sourceSampleRate = asbd.mSampleRate
        let sourceChannels = Int(asbd.mChannelsPerFrame)

        // Verify the format is Float32 before binding memory
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        guard isFloat, asbd.mBitsPerChannel == 32 else {
            print("[SystemAudioStreamOutput] Skipping buffer: not Float32 (flags=\(asbd.mFormatFlags), bits=\(asbd.mBitsPerChannel))")
            return
        }

        // Extract float samples from the CMSampleBuffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let rawData = dataPointer else { return }

        let sampleCount = totalLength / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return }

        let floatPointer = UnsafeRawPointer(rawData).bindMemory(to: Float.self, capacity: sampleCount)
        let sourceBuffer = UnsafeBufferPointer(start: floatPointer, count: sampleCount)

        // Convert to mono if multi-channel
        var monoSamples: [Float]
        if sourceChannels > 1 {
            let frameCount = sampleCount / sourceChannels
            monoSamples = [Float](repeating: 0, count: frameCount)
            for frame in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<sourceChannels {
                    sum += sourceBuffer[frame * sourceChannels + ch]
                }
                monoSamples[frame] = sum / Float(sourceChannels)
            }
        } else {
            monoSamples = Array(sourceBuffer)
        }

        // Resample from source rate to 16 kHz if needed using AVAudioConverter
        let resampled: [Float]
        if abs(sourceSampleRate - targetSampleRate) > 1.0 {
            resampled = convertTo16kHzMono(monoSamples, sourceSampleRate: sourceSampleRate)
        } else {
            resampled = monoSamples
        }

        lock.lock()
        buffer.append(contentsOf: resampled)
        fullRecordingBuffer.append(contentsOf: resampled)
        if fullRecordingBuffer.count > maxRecordingBufferSize {
            print("[SystemAudioStreamOutput] WARNING: recording buffer exceeded 2-hour cap — truncating oldest samples")
            fullRecordingBuffer.removeFirst(fullRecordingBuffer.count - maxRecordingBufferSize)
        }
        lock.unlock()
    }

    /// Drain all accumulated samples and clear the internal buffer.
    func drainSamples() -> [Float] {
        lock.lock()
        let result = buffer
        buffer.removeAll(keepingCapacity: true)
        lock.unlock()
        return result
    }

    /// Get all samples captured during the entire recording session (never drained).
    func allSamples() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return fullRecordingBuffer
    }

    /// Resample mono Float32 samples to 16 kHz using AVAudioConverter.
    /// The converter is created lazily and cached for reuse.
    private func convertTo16kHzMono(_ monoSamples: [Float], sourceSampleRate: Double) -> [Float] {
        guard !monoSamples.isEmpty else { return [] }

        // Lazily create the converter on first use
        if converter == nil {
            guard let srcFmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceSampleRate,
                channels: 1,
                interleaved: false
            ), let dstFmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            ), let conv = AVAudioConverter(from: srcFmt, to: dstFmt) else {
                return monoSamples
            }
            converter = conv
            targetFormat = dstFmt
        }

        guard let converter, let targetFormat else { return monoSamples }

        // Create input PCM buffer from our mono samples
        guard let srcFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: 1,
            interleaved: false
        ) else { return monoSamples }

        let frameCount = AVAudioFrameCount(monoSamples.count)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
            return monoSamples
        }
        inputBuffer.frameLength = frameCount
        if let channelData = inputBuffer.floatChannelData {
            monoSamples.withUnsafeBufferPointer { src in
                guard let srcAddr = src.baseAddress else { return }
                channelData[0].initialize(from: srcAddr, count: monoSamples.count)
            }
        }

        let ratio = targetSampleRate / sourceSampleRate
        let outputFrameCount = AVAudioFrameCount(Double(monoSamples.count) * ratio) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return monoSamples
        }

        var error: NSError?
        var hasData = true
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return inputBuffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        if let error {
            print("[SystemAudioStreamOutput] Conversion error: \(error)")
            return monoSamples
        }

        guard let floatData = outputBuffer.floatChannelData else { return monoSamples }
        return Array(UnsafeBufferPointer(start: floatData[0], count: Int(outputBuffer.frameLength)))
    }
}
#endif
