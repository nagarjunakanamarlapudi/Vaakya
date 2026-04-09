#if os(macOS)
import SwiftUI

struct MeetingDetailView: View {
    @Environment(MeetingViewModel.self) private var meetingVM
    @State private var newBlockContent: String = ""
    @State private var newBlockType: String = "summary"
    @State private var showTranscript: Bool = false
    @State private var showFloatingNotepad: Bool = false
    @State private var floatingNotes: String = ""
    @State private var showRegenerateConfirm: Bool = false
    @State private var showProjectPicker: Bool = false
    @State private var showCreateProject: Bool = false
    @State private var showNewTag: Bool = false
    @State private var newTagName: String = ""
    @State private var tagMeetingId: String? = nil
    @State private var editingTitle: String = ""
    @State private var showSlashMenu: Bool = false
    @State private var diarizationSpeakers: [Speaker] = []
    private var diarizationService: DiarizationService { DiarizationService.shared }
    @State private var showSpeakerMatching = false
    @State private var lastRecordingURL: URL?
    @State private var selectedTranscriptLang: String = "original"
    @State private var showTranscriptLangPicker: Bool = false
    @State private var selectedNotesLang: String = "en"
    @State private var showNotesLangPicker: Bool = false

    let recorder: AudioRecorder

    private let speakerColors: [Color] = [
        Color.accent,
        DesignTokens.BlockColor.summary,
        DesignTokens.BlockColor.decision,
        DesignTokens.BlockColor.action,
        Color(red: 0.85, green: 0.65, blue: 0.3),
        Color(red: 0.7, green: 0.5, blue: 0.9),
    ]

    // Extract unique speakers from blocks
    private var speakers: [String] {
        var set: Set<String> = []
        for block in meetingVM.blocks {
            if let s = block.speaker, !s.isEmpty { set.insert(s) }
        }
        if let meeting = meetingVM.selectedMeeting {
            for seg in meeting.transcript {
                if let speaker = seg.speaker, !speaker.isEmpty {
                    set.insert(speaker)
                }
            }
        }
        return Array(set).sorted()
    }

    // Active blocks for the selected notes language
    private var activeBlocks: [BlockData] {
        meetingVM.selectedMeeting?.activeBlocks(language: selectedNotesLang) ?? []
    }

    // Group blocks by type
    private var summaryBlocks: [BlockData] { activeBlocks.filter { $0.type.lowercased() == "summary" } }
    private var decisionBlocks: [BlockData] { activeBlocks.filter { $0.type.lowercased() == "decision" } }
    private var actionBlocks: [BlockData] { activeBlocks.filter { $0.type.lowercased() == "action" } }
    private var quoteBlocks: [BlockData] { activeBlocks.filter { $0.type.lowercased() == "quote" } }
    private var otherBlocks: [BlockData] {
        activeBlocks.filter {
            let t = $0.type.lowercased()
            return t != "summary" && t != "decision" && t != "action" && t != "quote"
        }
    }

    var body: some View {
        @Bindable var vm = meetingVM
        @Bindable var rec = recorder

        HStack(spacing: 0) {
            // Main content
            VStack(spacing: 0) {
                if let meeting = meetingVM.selectedMeeting {
                    // Header
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                        // Title
                        TextField("Meeting title", text: $editingTitle)
                            .textFieldStyle(.plain)
                            .font(DesignTokens.Typography.pageTitle)
                            .foregroundStyle(Color.textPrimary)
                            .onAppear { editingTitle = meeting.title }
                            .onChange(of: meeting.id) { _, _ in editingTitle = meeting.title }
                            .onSubmit {
                                guard editingTitle != meeting.title, !editingTitle.isEmpty else { return }
                                meetingVM.updateMeetingTitle(meetingId: meeting.id, title: editingTitle)
                            }

                        // Toolbar row
                        HStack(spacing: DesignTokens.Spacing.space2) {
                            if recorder.isRecording {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.blockRed).frame(width: 8, height: 8)
                                    Text(recorder.formattedDuration)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.blockRed)
                                }
                                .padding(.horizontal, DesignTokens.Spacing.space3).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(Color.blockRed.opacity(0.08)))

                                headerButton(icon: "stop.fill", label: "Stop", color: Color.blockRed, bgColor: Color.bgCard) {
                                    stopRecordingFlow()
                                }
                            } else {
                                headerButton(icon: "record.circle", label: "Record", color: Color.blockRed, bgColor: Color.bgCard) {
                                    startRecordingFlow(meetingId: meeting.id)
                                }
                            }

                            headerButton(icon: "sparkles", label: "Enhance", color: recorder.isRecording ? Color.textTertiary : Color.accent, bgColor: Color.accent.opacity(0.10)) {
                                let settings = LocalStore.shared.loadSettings()
                                Task { await meetingVM.enhanceMeeting(meetingId: meeting.id, userNotes: floatingNotes, language: settings.notesLanguage) }
                            }
                            .disabled(recorder.isRecording)

                            headerButton(icon: "arrow.triangle.2.circlepath", label: "Regenerate", color: recorder.isRecording ? Color.textTertiary : Color.blockRed, bgColor: Color.blockRed.opacity(0.08)) {
                                showRegenerateConfirm = true
                            }
                            .disabled(recorder.isRecording)

                            headerButton(icon: "square.and.arrow.up", label: "Share", color: Color.textSecondary, bgColor: Color.bgCard) {
                                Task { await meetingVM.shareMeeting(meetingId: meeting.id) }
                            }

                            headerButton(icon: "text.quote", label: "Transcript", color: showTranscript ? Color.accent : Color.textSecondary, bgColor: showTranscript ? Color.accent.opacity(0.10) : Color.bgCard) {
                                withAnimation(.easeInOut(duration: 0.2)) { showTranscript.toggle() }
                            }

                            if !recorder.isRecording && LocalStore.shared.audioURL(for: meeting.id) != nil {
                                if DiarizationService.shared.isDiarizing {
                                    HStack(spacing: 6) {
                                        ProgressView(value: DiarizationService.shared.progress)
                                            .frame(width: 40)
                                            .tint(Color.vaBlue)
                                        Text("Identifying speakers... \(Int(DiarizationService.shared.progress * 100))%")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.vaBlue)
                                    }
                                    .padding(.horizontal, DesignTokens.Spacing.space3)
                                    .padding(.vertical, 5)
                                    .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(Color.vaBlue.opacity(0.08)))
                                } else {
                                    headerButton(icon: "person.wave.2", label: "Identify Speakers", color: Color.vaBlue, bgColor: Color.vaBlue.opacity(0.10)) {
                                        Task { await runDiarization(meeting: meeting) }
                                    }
                                }
                            }

                            Spacer()
                        }

                        // Metadata line
                        HStack(spacing: DesignTokens.Spacing.space3) {
                            HStack(spacing: DesignTokens.Spacing.space1) {
                                Image(systemName: "calendar").font(.system(size: 10))
                                let df = DateFormatter()
                                let _ = df.dateFormat = "MMM d, h:mm a"
                                Text(df.string(from: meeting.startedAt)).font(DesignTokens.Typography.label)
                            }
                            .foregroundStyle(Color.textTertiary)
                            .fixedSize()

                            if let duration = meeting.durationSeconds, duration > 0 {
                                HStack(spacing: DesignTokens.Spacing.space1) {
                                    Image(systemName: "clock").font(.system(size: 10))
                                    Text("\(duration / 60) min").font(DesignTokens.Typography.label)
                                }
                                .foregroundStyle(Color.textTertiary)
                                .fixedSize()
                            }

                            if meeting.speakerCount > 0 {
                                HStack(spacing: DesignTokens.Spacing.space1) {
                                    Image(systemName: "person.2").font(.system(size: 10))
                                    Text("\(meeting.speakerCount)").font(DesignTokens.Typography.label)
                                }
                                .foregroundStyle(Color.textTertiary)
                                .fixedSize()
                            }

                            PrivacyBadge()
                        }
                        .lineLimit(1)

                        // Participant avatars
                        if !speakers.isEmpty {
                            HStack(spacing: -4) {
                                ForEach(Array(speakers.enumerated()), id: \.element) { idx, speaker in
                                    Circle()
                                        .fill(speakerColors[idx % speakerColors.count])
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Text(speakerInitials(speaker))
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                        )
                                        .overlay(Circle().stroke(Color.bgContent, lineWidth: 2))
                                        .help(speaker)
                                }
                            }
                        }

                        // Speaker talk-time breakdown bar chart
                        if !diarizationSpeakers.isEmpty {
                            speakerBreakdownView(
                                speakers: diarizationSpeakers,
                                totalDuration: Double(meeting.durationSeconds ?? 0)
                            )
                        }

                        // Project + Tags
                        meetingMetadataRow(meeting)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.space6)
                    .padding(.vertical, DesignTokens.Spacing.space4)

                    Divider().opacity(0.5)

                    // Section-grouped blocks
                    if meetingVM.transcriptionService.isTranscribing {
                        Spacer()
                        VStack(spacing: DesignTokens.Spacing.space3) {
                            ProgressView(value: meetingVM.transcriptionService.progress)
                                .tint(Color.accent)
                                .frame(width: 200)
                            Text("Transcribing... \(Int(meetingVM.transcriptionService.progress * 100))%")
                                .font(DesignTokens.Typography.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                            Text("Processing audio on your device")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                    } else if meetingVM.isLoadingBlocks {
                        Spacer()
                        VStack(spacing: DesignTokens.Spacing.space3) {
                            ProgressView()
                                .tint(Color.accent)
                            Text("Enhancing notes...")
                                .font(DesignTokens.Typography.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                            Text("Creating summary, decisions, and action items")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                    } else if activeBlocks.isEmpty {
                        Spacer()
                        EmptyStateView(
                            icon: "sparkles",
                            title: "No enhanced notes yet",
                            subtitle: "Click Enhance to create structured notes",
                            actionLabel: "Enhance Notes",
                            action: {
                                let settings = LocalStore.shared.loadSettings()
                                Task { await meetingVM.enhanceMeeting(meetingId: meeting.id, userNotes: floatingNotes, language: settings.notesLanguage) }
                            }
                        )
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                                notesLanguageToggle(meeting: meeting)

                                ForEach(summaryBlocks) { block in blockRow(block, meetingId: meeting.id) }

                                if !decisionBlocks.isEmpty {
                                    sectionHeader("DECISIONS", count: decisionBlocks.count, color: DesignTokens.BlockColor.decision)
                                    ForEach(decisionBlocks) { block in blockRow(block, meetingId: meeting.id) }
                                }
                                if !actionBlocks.isEmpty {
                                    sectionHeader("ACTION ITEMS", count: actionBlocks.count, color: DesignTokens.BlockColor.action)
                                    ForEach(actionBlocks) { block in blockRow(block, meetingId: meeting.id) }
                                }
                                if !quoteBlocks.isEmpty {
                                    sectionHeader("KEY QUOTES", count: quoteBlocks.count, color: DesignTokens.BlockColor.quote)
                                    ForEach(quoteBlocks) { block in blockRow(block, meetingId: meeting.id) }
                                }
                                ForEach(otherBlocks) { block in blockRow(block, meetingId: meeting.id) }
                            }
                            .padding(.horizontal, DesignTokens.Spacing.space6)
                            .padding(.vertical, DesignTokens.Spacing.space4)
                            .frame(maxWidth: DesignTokens.Block.maxContentWidth)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Divider().opacity(0.5)

                    // Slash command input bar
                    HStack(spacing: DesignTokens.Spacing.space3) {
                        TextField("Type / for commands...", text: $newBlockContent)
                            .textFieldStyle(.plain)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, DesignTokens.Spacing.space3)
                            .padding(.vertical, DesignTokens.Spacing.space2 + 2)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .fill(Color.bgCard)
                                    .shadow(color: DesignTokens.Shadow.cardColor, radius: DesignTokens.Shadow.cardRadius, y: DesignTokens.Shadow.cardY)
                            )
                            .onSubmit { handleSlashSubmit(meetingId: meeting.id) }
                            .onChange(of: newBlockContent) { _, newVal in
                                showSlashMenu = (newVal == "/")
                            }
                            .popover(isPresented: $showSlashMenu, arrowEdge: .top) {
                                slashMenuView
                            }

                        // Current type badge
                        Text(newBlockType.capitalized)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(colorForBlockType(newBlockType))
                            .padding(.horizontal, DesignTokens.Spacing.space2)
                            .padding(.vertical, DesignTokens.Spacing.space1)
                            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(colorForBlockType(newBlockType).opacity(0.10)))

                        Button(action: { handleSlashSubmit(meetingId: meeting.id) }) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(Color.accent)
                        }.buttonStyle(.plain).disabled(newBlockContent.isEmpty)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.space6)
                    .padding(.vertical, DesignTokens.Spacing.space3)
                }
            }
            .background(Color.bgContent)

            // Right panels
            if let meeting = meetingVM.selectedMeeting {
                if showTranscript {
                    Divider().opacity(0.5)
                    VStack(spacing: 0) {
                        if !meetingVM.isStreamingTranscription {
                            transcriptLanguageToggle(meeting: meeting)
                            Divider().opacity(0.3)
                        }
                        if meetingVM.isStreamingTranscription {
                            LiveTranscriptView(
                                transcriptionService: meetingVM.transcriptionService
                            )
                        } else if meetingVM.isTranslating {
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Translating...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // Build transcript text from stored segments or live service
                            let segments: [TranscriptSegmentData] = {
                                if selectedTranscriptLang == "original" {
                                    let liveSegs = meetingVM.transcriptionService.segments
                                    if !liveSegs.isEmpty {
                                        return liveSegs.map { seg in
                                            TranscriptSegmentData(
                                                start: seg.start, end: seg.end,
                                                text: seg.text, speaker: seg.speaker,
                                                isConfirmed: seg.isConfirmed
                                            )
                                        }
                                    }
                                    return meeting.transcript
                                }
                                return meeting.translatedTranscripts[selectedTranscriptLang] ?? meeting.transcript
                            }()
                            let transcriptText = segments.map { seg in
                                let speaker = seg.speaker.map { "[\($0)] " } ?? ""
                                return "[\(seg.startFormatted)] \(speaker)\(seg.text)"
                            }.joined(separator: "\n")
                            TranscriptView(
                                transcript: transcriptText,
                                meetingId: meeting.id,
                                blocks: meetingVM.blocks,
                                diarizationSpeakers: diarizationSpeakers
                            )
                        }
                    }
                    .transition(.move(edge: .trailing))
                }

                Divider().opacity(0.5)
                ContextualSidebar(meetingId: meeting.id)
                    .environment(meetingVM)
            }
        }
        .sheet(isPresented: $vm.showShareSheet) {
            ShareSheet(url: meetingVM.shareURL ?? "")
        }
        .onChange(of: showFloatingNotepad) { _, show in
            if show {
                showFloatingPanel()
            } else {
                FloatingPanelManager.shared.closePanel()
            }
        }
        .alert("Microphone Access Required", isPresented: $rec.permissionDenied) {
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Vaakya needs microphone access to record meetings. Please enable it in System Settings > Privacy & Security > Microphone.")
        }
        .onChange(of: meetingVM.toggleTranscriptRequest) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showTranscript.toggle()
            }
        }
        .onChange(of: meetingVM.enhanceRequest) { _, _ in
            if let meeting = meetingVM.selectedMeeting {
                let settings = LocalStore.shared.loadSettings()
                Task { await meetingVM.enhanceMeeting(meetingId: meeting.id, userNotes: floatingNotes, language: settings.notesLanguage) }
            }
        }
        .onChange(of: meetingVM.selectedMeeting?.id) { _, _ in
            if let lang = meetingVM.selectedMeeting?.notesLanguage {
                selectedNotesLang = lang
            }
            selectedTranscriptLang = "original"
        }
        .alert("Regenerate AI Notes", isPresented: $showRegenerateConfirm) {
            Button("Regenerate", role: .destructive) {
                if let meeting = meetingVM.selectedMeeting {
                    let settings = LocalStore.shared.loadSettings()
                    Task { await meetingVM.enhanceMeeting(meetingId: meeting.id, userNotes: floatingNotes, language: settings.notesLanguage) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will regenerate AI notes. Your edits will be lost.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFloatingPanel)) { _ in
            toggleFloatingPanel()
        }
        .sheet(isPresented: $showSpeakerMatching) {
            SpeakerMatchingView(
                speakers: diarizationSpeakers,
                participants: meetingVM.selectedMeeting?.participants?.map(\.name) ?? [],
                audioURL: lastRecordingURL ?? URL(fileURLWithPath: ""),
                onMatch: { speakerId, name in
                    var segments = meetingVM.transcriptionService.segments.map { seg in
                        DiarizationSegment(id: seg.id, start: seg.start, end: seg.end, text: seg.text, speaker: seg.speaker)
                    }
                    diarizationService.renameSpeaker(id: speakerId, newName: name, segments: &segments)
                    diarizationSpeakers = diarizationService.speakers
                },
                onDismiss: { showSpeakerMatching = false }
            )
        }
    }

    // MARK: - Header Button

    private func headerButton(icon: String, label: String, color: Color, bgColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(bgColor))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Recording Flow

    @State private var isLoadingModel = false

    private func startRecordingFlow(meetingId: String) {
        floatingNotes = ""
        showFloatingNotepad = true
        withAnimation(.easeInOut(duration: 0.2)) {
            showTranscript = true
        }

        Task {
            // Always try streaming first — load model if needed (shows loading state)
            if !meetingVM.transcriptionService.isModelLoaded {
                isLoadingModel = true
                print("[MeetingDetailView] Waiting for WhisperKit model to load...")
            }

            await meetingVM.startStreamingTranscription()
            isLoadingModel = false

            if meetingVM.isStreamingTranscription {
                // WhisperKit handles audio capture — just start the UI timer
                recorder.startTimerOnly()
                print("[MeetingDetailView] Streaming mode active — WhisperKit captures audio")
            } else {
                // Model failed to load — fall back to AVAudioRecorder (mic only, no transcription)
                print("[MeetingDetailView] Streaming failed — falling back to AVAudioRecorder")
                recorder.requestPermissionAndRecord(meetingId: meetingId, meetingTitle: meetingVM.selectedMeeting?.title)
            }
        }
    }

    /// Re-run diarization on an existing meeting's audio.
    private func runDiarization(meeting: MeetingDocument) async {
        guard let audioURL = LocalStore.shared.audioURL(for: meeting.id) else {
            meetingVM.errorMessage = "No audio file found for this meeting."
            return
        }
        do {
            var segments = meeting.transcript.map { seg in
                DiarizationSegment(id: seg.id, start: seg.start, end: seg.end, text: seg.text, speaker: seg.speaker)
            }
            try await DiarizationService.shared.diarize(audioURL: audioURL, segments: &segments)
            diarizationSpeakers = DiarizationService.shared.speakers

            if !diarizationSpeakers.isEmpty {
                meetingVM.updateTranscriptSpeakers(
                    meetingId: meeting.id,
                    diarizedSegments: segments,
                    speakers: diarizationSpeakers
                )
            }
        } catch {
            meetingVM.errorMessage = "Speaker identification failed: \(error.localizedDescription)"
        }
    }

    private func stopRecordingFlow() {
        let recorderAudioURL = recorder.stopRecording()
        recorder.stopTimerOnly()
        let notes = session.notes
        session.end()
        showFloatingNotepad = false
        FloatingPanelManager.shared.closePanel()
        if let meeting = meetingVM.selectedMeeting {
            Task {
                let streamAudioURL = await meetingVM.stopStreamingTranscription(meetingId: meeting.id)
                let audioURL = streamAudioURL ?? recorderAudioURL
                lastRecordingURL = audioURL

                if meetingVM.transcriptionService.segments.isEmpty {
                    #if DEBUG
                    print("[MeetingDetailView] Streaming produced no segments — audio saved but no transcript generated")
                    #endif
                    // Note: File-based transcription fallback disabled due to WhisperKit crash
                    // in SuppressTokensFilter.filterLogits (segfault on MLMultiArray access).
                    // The audio file is saved and can be re-transcribed after a WhisperKit update.
                    meetingVM.errorMessage = "No speech detected during recording. Audio has been saved."
                }

                // Run diarization on the saved audio (non-critical)
                if let savedURL = audioURL {
                    do {
                        var segments = meetingVM.transcriptionService.segments.map { seg in
                            DiarizationSegment(id: seg.id, start: seg.start, end: seg.end, text: seg.text, speaker: seg.speaker)
                        }
                        try await diarizationService.diarize(audioURL: savedURL, segments: &segments)
                        diarizationSpeakers = diarizationService.speakers

                        // Write diarized speaker labels back to the meeting transcript
                        if !diarizationSpeakers.isEmpty {
                            meetingVM.updateTranscriptSpeakers(
                                meetingId: meeting.id,
                                diarizedSegments: segments,
                                speakers: diarizationSpeakers
                            )

                            if let participants = meeting.participants, !participants.isEmpty {
                                showSpeakerMatching = true
                            }
                        }
                    } catch {
                        print("Diarization failed (non-critical): \(error)")
                    }
                }

                if meetingVM.transcriptionComplete {
                    let settings = LocalStore.shared.loadSettings()
                    await meetingVM.enhanceMeeting(meetingId: meeting.id, userNotes: notes, language: settings.notesLanguage)
                }
            }
        }
    }

    // MARK: - Floating Panel

    private var session: RecordingSession { RecordingSession.shared }

    private func showFloatingPanel() {
        guard let meeting = meetingVM.selectedMeeting else { return }
        session.start(meetingId: meeting.id, title: meeting.title)
        let notepadView = FloatingNotepad(
            recorder: recorder, session: session,
            onEndMeeting: { stopRecordingFlow() },
            onMinimize: { minimizeToPanel() }
        )
        let hostView = NSHostingView(rootView: notepadView)
        FloatingPanelManager.shared.showExpanded(content: hostView)
    }

    private func minimizeToPanel() {
        let pillView = RecordingPillView(
            recorder: recorder, session: session,
            onExpand: { expandFromPanel() }
        )
        let hostView = NSHostingView(rootView: pillView)
        FloatingPanelManager.shared.showMinimized(content: hostView)
    }

    private func expandFromPanel() {
        let notepadView = FloatingNotepad(
            recorder: recorder, session: session,
            onEndMeeting: { stopRecordingFlow() },
            onMinimize: { minimizeToPanel() }
        )
        let hostView = NSHostingView(rootView: notepadView)
        FloatingPanelManager.shared.expandFromPill(content: hostView)
    }

    func toggleFloatingPanel() {
        guard FloatingPanelManager.shared.isVisible else { return }
        if FloatingPanelManager.shared.isMinimized {
            expandFromPanel()
        } else {
            minimizeToPanel()
        }
    }

    // MARK: - Language Toggles

    private func langTab(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accent.opacity(0.12) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func transcriptLanguageToggle(meeting: MeetingDocument) -> some View {
        HStack(spacing: 4) {
            // "Original" tab -- always present
            langTab("Original", isSelected: selectedTranscriptLang == "original") {
                selectedTranscriptLang = "original"
            }

            // Translated language tabs
            ForEach(meeting.availableTranscriptLanguages, id: \.self) { langCode in
                let name = TranscriptionLanguage(rawValue: langCode)?.displayName ?? langCode
                langTab(name, isSelected: selectedTranscriptLang == langCode) {
                    selectedTranscriptLang = langCode
                }
            }

            // "+" button to add translation
            Button(action: { showTranscriptLangPicker = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.bgCard))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showTranscriptLangPicker) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(TranscriptionLanguage.allCases.filter { $0 != .auto }, id: \.self) { lang in
                        if !meeting.availableTranscriptLanguages.contains(lang.code) && lang.code != "original" {
                            Button(lang.displayName) {
                                showTranscriptLangPicker = false
                                Task {
                                    await meetingVM.translateTranscript(meetingId: meeting.id, targetLanguage: lang.code)
                                    selectedTranscriptLang = lang.code
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func notesLanguageToggle(meeting: MeetingDocument) -> some View {
        if !meeting.availableNotesLanguages.isEmpty {
            HStack(spacing: 4) {
                ForEach(meeting.availableNotesLanguages, id: \.self) { langCode in
                    let name = TranscriptionLanguage(rawValue: langCode)?.displayName ?? langCode
                    langTab(name, isSelected: selectedNotesLang == langCode) {
                        selectedNotesLang = langCode
                    }
                }

                Button(action: { showNotesLangPicker = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.bgCard))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showNotesLangPicker) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(TranscriptionLanguage.allCases.filter { $0 != .auto }, id: \.self) { lang in
                            if !meeting.availableNotesLanguages.contains(lang.code) {
                                Button(lang.displayName) {
                                    showNotesLangPicker = false
                                    Task {
                                        await meetingVM.enhanceMeeting(meetingId: meeting.id, language: lang.code)
                                        selectedNotesLang = lang.code
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Block.padding)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.space2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .tracking(0.5)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color.opacity(0.7))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(color.opacity(0.10)))
            Spacer()
        }
        .padding(.top, DesignTokens.Spacing.space3).padding(.bottom, 2)
    }

    // MARK: - Block Row

    private func blockRow(_ block: BlockData, meetingId: String) -> some View {
        BlockView(
            block: block,
            meetingId: meetingId,
            onToggle: { checked in meetingVM.toggleBlock(meetingId: meetingId, blockId: block.id, checked: checked) },
            onDelete: { meetingVM.deleteBlock(meetingId: meetingId, blockId: block.id) },
            onContentChange: { newContent in meetingVM.updateBlockContent(meetingId: meetingId, blockId: block.id, content: newContent) }
        )
    }

    // MARK: - Slash Commands

    @ViewBuilder
    private var slashMenuView: some View {
        VStack(spacing: 2) {
            slashOption("/summary", type: "summary", color: DesignTokens.BlockColor.summary)
            slashOption("/decision", type: "decision", color: DesignTokens.BlockColor.decision)
            slashOption("/action", type: "action", color: DesignTokens.BlockColor.action)
            slashOption("/quote", type: "quote", color: DesignTokens.BlockColor.quote)
        }
        .padding(DesignTokens.Spacing.space2)
        .frame(width: 180)
    }

    private func slashOption(_ label: String, type: String, color: Color) -> some View {
        Button(action: {
            showSlashMenu = false
            newBlockType = type
            newBlockContent = ""
        }) {
            HStack(spacing: DesignTokens.Spacing.space2) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 14)
                Text(label).font(DesignTokens.Typography.label).foregroundStyle(Color.textPrimary)
                Spacer()
                Text(type.capitalized).font(.system(size: 10)).foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.space2).padding(.vertical, DesignTokens.Spacing.space1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleSlashSubmit(meetingId: String) {
        let text = newBlockContent.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let commands = ["summary", "decision", "action", "quote", "heading", "text"]
        for cmd in commands {
            if text.lowercased().hasPrefix("/\(cmd)") {
                let content = String(text.dropFirst(cmd.count + 1)).trimmingCharacters(in: .whitespaces)
                let resolvedType = (cmd == "heading" || cmd == "text") ? "note" : cmd
                if !content.isEmpty {
                    newBlockContent = ""
                    meetingVM.createBlock(meetingId: meetingId, type: resolvedType, content: content)
                    return
                } else {
                    newBlockType = resolvedType
                    newBlockContent = ""
                    return
                }
            }
        }

        newBlockContent = ""
        meetingVM.createBlock(meetingId: meetingId, type: newBlockType, content: text)
    }

    // MARK: - Speaker Breakdown

    @ViewBuilder
    private func speakerBreakdownView(speakers: [Speaker], totalDuration: Double) -> some View {
        let totalTalkTime = speakers.reduce(0.0) { $0 + $1.talkTimeSeconds }

        VStack(alignment: .leading, spacing: 6) {
            Text("TALK TIME")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(speakers) { speaker in
                        let percent = totalTalkTime > 0
                            ? speaker.talkTimeSeconds / totalTalkTime
                            : 1.0 / Double(speakers.count)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: speaker.color))
                            .frame(width: max(4, geo.size.width * percent))
                            .help("\(speaker.label): \(Int(percent * 100))%")
                    }
                }
            }
            .frame(height: 8)

            HStack(spacing: 12) {
                ForEach(speakers) { speaker in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: speaker.color))
                            .frame(width: 8, height: 8)
                        Text(speaker.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        if totalTalkTime > 0 {
                            Text("\(Int(speaker.talkTimeSeconds / totalTalkTime * 100))%")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func meetingMetadataRow(_ meeting: MeetingDocument) -> some View {
        let meta = LocalStore.shared.meetings.first(where: { $0.id == meeting.id })
        let projects = LocalStore.shared.projects

        HStack(spacing: DesignTokens.Spacing.space2) {
            // Project
            if let projectId = meta?.project,
               let project = projects.first(where: { $0.id == projectId }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: project.color))
                    Text(project.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: project.color))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: project.color).opacity(0.10))
                )
            }

            // Change project button
            Menu {
                ProjectPickerMenu(
                    meetingId: meeting.id,
                    currentProjectId: meta?.project,
                    showCreateProject: $showCreateProject
                )
            } label: {
                Image(systemName: meta?.project == nil ? "folder.badge.plus" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.bgCard))
            }
            .buttonStyle(.plain)
            .help(meta?.project == nil ? "Add to project" : "Change project")

            // Tags
            if let tags = meta?.tags, !tags.isEmpty {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 2) {
                        Text(tag)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        Button(action: {
                            LocalStore.shared.removeTag(tag, fromMeeting: meeting.id)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.textTertiary.opacity(0.10)))
                }
            }

            // Add tag button
            Menu {
                TagPickerMenu(
                    meetingId: meeting.id,
                    currentTags: meta?.tags ?? [],
                    showNewTag: $showNewTag,
                    tagMeetingId: $tagMeetingId
                )
            } label: {
                Image(systemName: "tag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.bgCard))
            }
            .buttonStyle(.plain)
            .help("Add tag")

            Spacer()
        }
        .alert("New Tag", isPresented: $showNewTag) {
            TextField("Tag name", text: $newTagName)
            Button("Add") {
                let tag = newTagName.trimmingCharacters(in: .whitespaces)
                guard !tag.isEmpty, let id = tagMeetingId else { return }
                LocalStore.shared.addTag(tag, toMeeting: id)
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCreateProject) {
            ProjectEditorSheet { name, color in
                let project = ProjectFolder(name: name, color: color)
                LocalStore.shared.addProject(project)
            }
        }
    }

    private func speakerInitials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    private func colorForBlockType(_ type: String) -> Color {
        switch type.lowercased() {
        case "summary":  return DesignTokens.BlockColor.summary
        case "decision": return DesignTokens.BlockColor.decision
        case "action":   return DesignTokens.BlockColor.action
        case "quote":    return DesignTokens.BlockColor.quote
        default:         return Color.textTertiary
        }
    }
}
#endif
