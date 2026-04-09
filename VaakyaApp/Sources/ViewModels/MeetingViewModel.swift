import Foundation
import SwiftUI

@MainActor
@Observable
final class MeetingViewModel {
    // MARK: - Published State

    /// The in-memory meetings list comes from LocalStore. This is a convenience accessor.
    var meetings: [MeetingMetadata] { LocalStore.shared.meetings }

    /// The currently selected meeting document (full data loaded from disk).
    var selectedMeeting: MeetingDocument?

    /// Blocks are embedded in selectedMeeting — this is a convenience accessor.
    var blocks: [BlockData] { selectedMeeting?.blocks ?? [] }

    var isLoadingMeetings: Bool = false
    var isLoadingBlocks: Bool = false
    var errorMessage: String?
    var shareURL: String?
    var showShareSheet: Bool = false
    var newMeetingTitle: String = ""
    var showCreateSheet: Bool = false
    var toggleTranscriptRequest: Bool = false
    var enhanceRequest: Bool = false
    var transcriptionComplete: Bool = false

    // MARK: - On-Device Transcription

    let transcriptionService = TranscriptionService.shared
    let modelManager = ModelManager()

    /// Whether live streaming transcription is active.
    var isStreamingTranscription: Bool { transcriptionService.isStreaming }

    private var transcriptSnapshotTimer: Timer?

    /// Start live streaming transcription. Call when recording begins.
    /// Loads the WhisperKit model if needed, then starts the audio stream transcriber.
    /// Also starts a 30-second periodic snapshot of transcript to LocalStore (WAL) for crash safety.
    func startStreamingTranscription() async {
        // Ensure the transcription model is loaded
        if !transcriptionService.isModelLoaded {
            let modelName = modelManager.currentModel ?? modelManager.recommendedModel
            do {
                try await transcriptionService.loadModel(modelName, directory: modelManager.modelsDirectoryURL)
            } catch {
                errorMessage = "Failed to load Whisper model: \(error.localizedDescription)"
                return
            }
        }

        do {
            try await transcriptionService.startStreaming()
            startTranscriptSnapshotTimer()
        } catch {
            errorMessage = "Failed to start streaming: \(error.localizedDescription)"
        }
    }

    /// Periodically save in-progress transcript to LocalStore via WAL (crash safety).
    private func startTranscriptSnapshotTimer() {
        transcriptSnapshotTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.snapshotTranscriptToLocalStore()
            }
        }
    }

    /// Snapshot current transcript segments into the meeting document via LocalStore.
    private func snapshotTranscriptToLocalStore() {
        guard let meetingId = selectedMeeting?.id else { return }
        let segments = transcriptionService.segments
        guard !segments.isEmpty else { return }

        if var doc = LocalStore.shared.loadMeeting(id: meetingId) {
            doc.transcript = segments.map { seg in
                TranscriptSegmentData(
                    start: seg.start,
                    end: seg.end,
                    text: seg.text,
                    speaker: seg.speaker,
                    isConfirmed: seg.isConfirmed
                )
            }
            if let last = segments.last {
                doc.durationSeconds = Int(last.end)
            }
            LocalStore.shared.updateMeeting(doc)
            print("[MeetingViewModel] Transcript snapshot: \(segments.count) segments saved to WAL")
        }
    }

    /// Stop live streaming transcription. Call when recording stops.
    /// Finalizes all segments, saves captured audio, and saves transcript to the local meeting document.
    /// Returns the audio URL saved from WhisperKit's buffer (for playback).
    @discardableResult
    func stopStreamingTranscription(meetingId: String) async -> URL? {
        // Stop the periodic transcript snapshot timer
        transcriptSnapshotTimer?.invalidate()
        transcriptSnapshotTimer = nil

        let audioURL = await transcriptionService.stopStreaming(meetingId: meetingId)

        // Convert TranscriptionService segments to TranscriptSegmentData and save locally
        let segments = transcriptionService.segments
        guard !segments.isEmpty else { return audioURL }

        if var doc = LocalStore.shared.loadMeeting(id: meetingId) {
            doc.transcript = segments.map { seg in
                TranscriptSegmentData(
                    start: seg.start,
                    end: seg.end,
                    text: seg.text,
                    speaker: seg.speaker,
                    isConfirmed: seg.isConfirmed
                )
            }
            // Update duration from recording
            if let first = segments.first, let last = segments.last {
                doc.durationSeconds = Int(last.end - first.start)
            }
            LocalStore.shared.updateMeeting(doc)
            selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)
            transcriptionComplete = true

            // Auto-sync to cloud if signed in
            if KeychainService.load(key: "access_token") != nil {
                Task {
                    do {
                        try await SyncService.shared.pushMeeting(id: meetingId)
                        try await SyncService.shared.pushIndex()
                    } catch {
                        print("[Sync] Push failed for \(meetingId): \(error)")
                    }
                }
            }
        }

        // Audio is already saved directly to meetings/{id}/audio.m4a by TranscriptionService.
        // Refresh the selected meeting to pick up the audio flag.
        if audioURL != nil {
            selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)
        }

        return audioURL
    }

    // MARK: - Select Meeting

    func selectMeeting(_ metadata: MeetingMetadata) {
        selectedMeeting = LocalStore.shared.loadMeeting(id: metadata.id)
    }

    func selectMeeting(id: String) {
        selectedMeeting = LocalStore.shared.loadMeeting(id: id)
    }

    // MARK: - CRUD (all via LocalStore)

    func createMeeting(title: String) {
        guard !title.isEmpty else { return }
        let doc = MeetingDocument(title: title)
        LocalStore.shared.createMeeting(doc)
        selectedMeeting = doc
    }

    func deleteMeeting(_ metadata: MeetingMetadata) {
        LocalStore.shared.deleteMeeting(id: metadata.id)
        if selectedMeeting?.id == metadata.id {
            selectedMeeting = nil
        }
    }

    func updateMeetingTitle(meetingId: String, title: String) {
        guard var doc = LocalStore.shared.loadMeeting(id: meetingId) else { return }
        doc.title = title
        LocalStore.shared.updateMeeting(doc)
        selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)
    }

    /// Write diarization results back to the meeting transcript + speakers.
    func updateTranscriptSpeakers(meetingId: String, diarizedSegments: [DiarizationSegment], speakers: [Speaker]) {
        guard var doc = LocalStore.shared.loadMeeting(id: meetingId) else { return }

        // Update each transcript segment's speaker label from diarization
        for diarized in diarizedSegments {
            if let idx = doc.transcript.firstIndex(where: { $0.id == diarized.id }),
               let speaker = diarized.speaker {
                doc.transcript[idx].speaker = speaker
            }
        }

        // Save speaker metadata (names, colors, talk times)
        doc.speakers = speakers.map { speaker in
            SpeakerData(id: speaker.id, label: speaker.label, color: speaker.color, talkTimeSeconds: speaker.talkTimeSeconds)
        }
        doc.speakerCount = speakers.count

        LocalStore.shared.updateMeeting(doc)
        selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)

        // Sync immediately
        Task {
            do {
                try await SyncService.shared.pushMeeting(id: meetingId)
                try await SyncService.shared.pushIndex()
            } catch {
                print("[Sync] Push failed for \(meetingId): \(error)")
            }
        }
    }

    // MARK: - Block Operations (embedded in MeetingDocument)

    func toggleBlock(meetingId: String, blockId: String, checked: Bool) {
        guard var doc = LocalStore.shared.loadMeeting(id: meetingId) else { return }
        if let idx = doc.blocks.firstIndex(where: { $0.id == blockId }) {
            doc.blocks[idx].isChecked = checked
            LocalStore.shared.updateMeeting(doc)
            selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)
        }
    }

    func createBlock(meetingId: String, type: String, content: String, speaker: String? = nil) {
        guard var doc = LocalStore.shared.loadMeeting(id: meetingId) else { return }
        let block = BlockData(
            type: type,
            content: content,
            speaker: speaker,
            position: doc.blocks.count
        )
        doc.blocks.append(block)
        LocalStore.shared.updateMeeting(doc)
        selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)
    }

    func deleteBlock(meetingId: String, blockId: String) {
        guard var doc = LocalStore.shared.loadMeeting(id: meetingId) else { return }
        doc.blocks.removeAll { $0.id == blockId }
        LocalStore.shared.updateMeeting(doc)
        selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)
    }

    func updateBlockContent(meetingId: String, blockId: String, content: String) {
        guard var doc = LocalStore.shared.loadMeeting(id: meetingId) else { return }
        if let idx = doc.blocks.firstIndex(where: { $0.id == blockId }) {
            doc.blocks[idx].content = content
            LocalStore.shared.updateMeeting(doc)
            selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)
        }
    }

    // MARK: - AI Enhancement (via AIService)

    var isTranslating = false

    func enhanceMeeting(meetingId: String, template: String? = nil, userNotes: String = "", language: String? = nil) async {
        guard var doc = LocalStore.shared.loadMeeting(id: meetingId) else {
            errorMessage = "Meeting not found"
            return
        }
        let settings = LocalStore.shared.loadSettings()
        let tmpl = template ?? settings.defaultTemplate
        let lang = language ?? settings.notesLanguage
        isLoadingBlocks = true

        do {
            let enhancedBlocks = try await AIService.shared.enhance(
                transcript: doc.transcript,
                userNotes: userNotes.isEmpty ? doc.userNotes : userNotes,
                template: tmpl,
                settings: settings,
                language: lang
            )
            doc.enhancedBlocks[lang] = enhancedBlocks
            doc.blocks = enhancedBlocks  // keep legacy field in sync
            doc.isEnhanced = true
            doc.notesLanguage = lang
            doc.aiProvider = settings.aiProvider
            LocalStore.shared.updateMeeting(doc)
            selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)

            // Auto-sync to cloud if signed in
            if KeychainService.load(key: "access_token") != nil {
                Task {
                    do {
                        try await SyncService.shared.pushMeeting(id: meetingId)
                        try await SyncService.shared.pushIndex()
                    } catch {
                        print("[Sync] Push failed for \(meetingId): \(error)")
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingBlocks = false
    }

    func translateTranscript(meetingId: String, targetLanguage: String, force: Bool = false) async {
        guard var doc = LocalStore.shared.loadMeeting(id: meetingId) else {
            errorMessage = "Meeting not found"
            return
        }

        if !force && doc.translatedTranscripts[targetLanguage] != nil { return }

        let settings = LocalStore.shared.loadSettings()
        isTranslating = true

        do {
            let translated = try await AIService.shared.translateTranscript(
                transcript: doc.transcript,
                targetLanguage: targetLanguage,
                settings: settings
            )
            doc.translatedTranscripts[targetLanguage] = translated
            LocalStore.shared.updateMeeting(doc)
            selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)
        } catch {
            errorMessage = "Translation failed: \(error.localizedDescription)"
        }

        isTranslating = false
    }

    // MARK: - Share (requires sign-in, uses APIClient)

    func shareMeeting(meetingId: String) async {
        // Sharing requires server — only works when signed in
        guard KeychainService.load(key: "access_token") != nil else {
            errorMessage = "Sign in to share meetings"
            return
        }

        do {
            // Push meeting to S3 first so the share link can resolve it
            do {
                try await SyncService.shared.pushMeeting(id: meetingId)
                try await SyncService.shared.pushIndex()
            } catch {
                print("[Sync] Pre-share push failed for \(meetingId): \(error)")
            }

            let response = try await APIClient.shared.shareMeeting(id: meetingId)
            if response.url.hasPrefix("/") {
                shareURL = "\(APIClient.shared.baseURL)\(response.url)"
            } else {
                shareURL = response.url
            }
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Transcription (file-based fallback)

    func transcribeMeeting(meetingId: String, audioURL: URL) async {
        isLoadingBlocks = true
        transcriptionComplete = false

        // Ensure the transcription model is loaded
        if !transcriptionService.isModelLoaded {
            let modelName = modelManager.currentModel ?? modelManager.recommendedModel
            do {
                try await transcriptionService.loadModel(modelName, directory: modelManager.modelsDirectoryURL)
            } catch {
                errorMessage = "Failed to load Whisper model: \(error.localizedDescription)"
                isLoadingBlocks = false
                return
            }
        }

        // Run on-device transcription
        do {
            try await transcriptionService.transcribe(audioURL: audioURL)
            let segments = transcriptionService.segments

            // Save transcript segments into the meeting document locally
            if var doc = LocalStore.shared.loadMeeting(id: meetingId) {
                doc.transcript = segments.map { seg in
                    TranscriptSegmentData(
                        start: seg.start,
                        end: seg.end,
                        text: seg.text,
                        speaker: seg.speaker,
                        isConfirmed: seg.isConfirmed
                    )
                }
                LocalStore.shared.updateMeeting(doc)
                selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)
            }

            transcriptionComplete = true
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }

        isLoadingBlocks = false
    }

    // MARK: - Dashboard Stats (from LocalStore)

    var isLoadingDashboardStats: Bool = false

    var meetingsThisWeek: Int { LocalStore.shared.meetingsThisWeek }
    var totalCapturedSeconds: Int { LocalStore.shared.totalCapturedSeconds }
    var pendingActionItemCount: Int { LocalStore.shared.pendingActionItems }
    var aiEnhancedMeetingCount: Int { LocalStore.shared.aiEnhancedCount }

    /// Recently enhanced meetings from the local store.
    func recentlyEnhancedMeetings(limit: Int = 5) -> [MeetingMetadata] {
        LocalStore.shared.meetings
            .filter(\.isEnhanced)
            .prefix(limit)
            .map { $0 }
    }
}
