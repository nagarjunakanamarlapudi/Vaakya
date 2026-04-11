import AVFoundation
import Foundation

@MainActor
@Observable
final class AudioPlayer: NSObject {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Double = 0
    var playbackSpeed: Float = 1.0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var formattedCurrentTime: String { formatTime(currentTime) }
    var formattedDuration: String { formatTime(duration) }

    func load(url: URL) {
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.enableRate = true
            p.prepareToPlay()
            player = p
            duration = p.duration
            currentTime = 0
            progress = 0
            playbackSpeed = 1.0
        } catch {
            print("AudioPlayer: failed to load \(url.path): \(error)")
        }
    }

    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        player?.rate = speed
    }

    var isDownloadingAudio = false

    func loadForMeeting(meetingId: String) {
        // Primary: LocalStore meeting directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let localStoreAudio = appSupport
            .appendingPathComponent("Vaakya/meetings/\(meetingId)/audio.m4a")
        if FileManager.default.fileExists(atPath: localStoreAudio.path) {
            load(url: localStoreAudio)
            return
        }

        // Fallback: legacy recordings directory
        #if os(macOS)
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Vaakya/recordings")
        #else
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vaakya/recordings")
        #endif
        if let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) {
            let matching = files
                .filter { $0.lastPathComponent.hasPrefix(meetingId) && $0.pathExtension == "m4a" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            if let latest = matching.first {
                load(url: latest)
                return
            }
        }

        // On-demand: fetch from S3 via SyncService
        isDownloadingAudio = true
        Task {
            do {
                try await SyncService.shared.pullAudio(meetingId: meetingId)
                if FileManager.default.fileExists(atPath: localStoreAudio.path) {
                    load(url: localStoreAudio)
                }
            } catch {
                print("AudioPlayer: remote audio fetch failed for \(meetingId): \(error)")
            }
            isDownloadingAudio = false
        }
    }

    func play() {
        guard let p = player else { return }
        p.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func seek(to fraction: Double) {
        guard let p = player else { return }
        let time = p.duration * fraction
        p.currentTime = time
        currentTime = time
        progress = fraction
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        progress = 0
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
                self.duration = p.duration
                self.progress = p.duration > 0 ? p.currentTime / p.duration : 0
                if !p.isPlaying {
                    self.isPlaying = false
                    self.timer?.invalidate()
                    self.timer = nil
                }
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
