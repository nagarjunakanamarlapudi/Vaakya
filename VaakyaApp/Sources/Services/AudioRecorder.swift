import Foundation
import AVFoundation
import SwiftUI
#if os(iOS)
import UIKit
import MediaPlayer
#endif

@MainActor
@Observable
final class AudioRecorder: NSObject {
    static let shared = AudioRecorder()

    var isRecording: Bool = false
    var recordingDuration: TimeInterval = 0
    var currentAmplitude: Float = 0
    var permissionDenied: Bool = false

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentMeetingId: String?
    private var currentMeetingTitle: String?

    private var recordingsDirectory: URL {
        #if os(macOS)
        let docs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("Vaakya")
            .appendingPathComponent("recordings")
        #else
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vaakya")
            .appendingPathComponent("recordings")
        #endif
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    func requestPermissionAndRecord(meetingId: String, meetingTitle: String? = nil) {
        currentMeetingTitle = meetingTitle
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording(meetingId: meetingId)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted {
                        self.startRecording(meetingId: meetingId)
                    } else {
                        self.permissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
        #else
        // iOS uses AVAudioSession for permission
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            startRecording(meetingId: meetingId)
        case .undetermined:
            session.requestRecordPermission { granted in
                Task { @MainActor in
                    if granted {
                        self.startRecording(meetingId: meetingId)
                    } else {
                        self.permissionDenied = true
                    }
                }
            }
        case .denied:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
        #endif
    }

    private func startRecording(meetingId: String) {
        currentMeetingId = meetingId
        let filename = "\(meetingId)_\(Int(Date().timeIntervalSince1970)).m4a"
        let fileURL = recordingsDirectory.appendingPathComponent(filename)

        #if os(iOS)
        // Configure AVAudioSession for recording (enables background recording
        // when UIBackgroundModes: audio is set in Info.plist)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [.allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("AVAudioSession configuration failed: \(error)")
            #endif
        }
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.record()
            audioRecorder = recorder
            isRecording = true
            recordingDuration = 0

            #if os(iOS)
            // Haptic feedback on record start
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            // Set up lock screen controls
            setupNowPlayingInfo()
            setupRemoteCommandCenter()
            #endif

            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isRecording else { return }
                    self.recordingDuration = self.audioRecorder?.currentTime ?? 0
                    self.audioRecorder?.updateMeters()
                    let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                    self.currentAmplitude = max(0, min(1, (power + 50) / 50))
                    #if os(iOS)
                    self.updateNowPlayingInfo()
                    #endif
                }
            }
            #if DEBUG
            print("Recording started: \(fileURL.path)")
            #endif
        } catch {
            #if DEBUG
            print("Failed to start recording: \(error)")
            #endif
        }
    }

    /// Start the recording timer without actually starting AVAudioRecorder.
    /// Used when WhisperKit handles audio capture but we still need UI timer state.
    /// Reads amplitude from MicAudioCapture for waveform display.
    func startTimerOnly() {
        isRecording = true
        recordingDuration = 0
        let startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let recorder = self as? AudioRecorder else { return }
            Task { @MainActor in
                guard recorder.isRecording else { return }
                recorder.recordingDuration = Date().timeIntervalSince(startDate)
                #if os(macOS)
                recorder.currentAmplitude = TranscriptionService.shared.micCapture.currentAmplitude
                #endif
            }
        }
    }

    /// Stop the recording timer without touching AVAudioRecorder.
    /// Used when WhisperKit handles audio capture.
    func stopTimerOnly() {
        timer?.invalidate()
        timer = nil
        isRecording = false
        currentAmplitude = 0
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil

        guard let recorder = audioRecorder else { return nil }
        let url = recorder.url
        recorder.stop()
        audioRecorder = nil
        isRecording = false
        currentAmplitude = 0

        #if os(iOS)
        // Haptic feedback on record stop
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        // Clear lock screen controls
        clearNowPlayingInfo()
        clearRemoteCommandCenter()
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        #if DEBUG
        print("Recording saved: \(url.path)")
        #endif
        return url
    }

    var formattedDuration: String {
        let mins = Int(recordingDuration) / 60
        let secs = Int(recordingDuration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - iOS Lock Screen Controls

    #if os(iOS)
    private func setupNowPlayingInfo() {
        var nowPlayingInfo: [String: Any] = [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = currentMeetingTitle ?? "Recording"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "Vaakya"
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = recordingDuration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNowPlayingInfo() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            setupNowPlayingInfo()
            return
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = recordingDuration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = self?.stopRecording()
            }
            return .success
        }
        // Disable other commands
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = self?.stopRecording()
            }
            return .success
        }
    }

    private func clearRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.stopCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.stopCommand.isEnabled = false
    }
    #endif
}
