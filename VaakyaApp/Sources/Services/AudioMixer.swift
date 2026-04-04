#if os(macOS)
import Foundation
import Accelerate

// MARK: - Audio Mixer

/// Mixes microphone and system audio sample buffers into a single stream
/// suitable for WhisperKit transcription (16 kHz mono Float32).
enum AudioMixer {

    /// Mix two mono Float32 audio buffers. If they differ in length the shorter
    /// one is zero-padded. The result is normalised so it stays within [-1, 1].
    ///
    /// - Parameters:
    ///   - mic: Microphone audio samples (16 kHz mono Float32).
    ///   - system: System audio samples (16 kHz mono Float32).
    ///   - micGain: Gain applied to mic samples before mixing (default 1.0).
    ///   - systemGain: Gain applied to system samples before mixing (default 1.0).
    /// - Returns: Mixed audio samples.
    static func mix(
        mic: [Float],
        system: [Float],
        micGain: Float = 1.0,
        systemGain: Float = 1.0
    ) -> [Float] {
        guard !mic.isEmpty || !system.isEmpty else { return [] }

        let length = max(mic.count, system.count)
        var result = [Float](repeating: 0, count: length)

        // Add mic samples with gain
        if !mic.isEmpty {
            var gain = micGain
            var scaledMic = [Float](repeating: 0, count: mic.count)
            vDSP_vsmul(mic, 1, &gain, &scaledMic, 1, vDSP_Length(mic.count))
            vDSP_vadd(result, 1, scaledMic, 1, &result, 1, vDSP_Length(mic.count))
        }

        // Add system samples with gain
        if !system.isEmpty {
            var gain = systemGain
            var scaledSys = [Float](repeating: 0, count: system.count)
            vDSP_vsmul(system, 1, &gain, &scaledSys, 1, vDSP_Length(system.count))
            vDSP_vadd(result, 1, scaledSys, 1, &result, 1, vDSP_Length(system.count))
        }

        // Normalise to prevent clipping: find the peak amplitude and scale down
        // if it exceeds 1.0.
        var peak: Float = 0
        vDSP_maxmgv(result, 1, &peak, vDSP_Length(length))

        if peak > 1.0 {
            var scale = 1.0 / peak
            vDSP_vsmul(result, 1, &scale, &result, 1, vDSP_Length(length))
        }

        return result
    }
}
#endif
