import Foundation

/// Shared state for the recording session — accessible across NSPanel and main window
@MainActor
@Observable
final class RecordingSession {
    static let shared = RecordingSession()

    var notes: String = ""
    var meetingId: String?
    var meetingTitle: String = ""
    var isActive: Bool = false
    /// Latest speaker label from diarization (e.g. "Speaker 1"). Empty when diarization is off.
    var currentSpeakerName: String = ""

    func start(meetingId: String, title: String) {
        self.meetingId = meetingId
        self.meetingTitle = title
        self.notes = ""
        self.isActive = true
    }

    func end() {
        isActive = false
    }
}
