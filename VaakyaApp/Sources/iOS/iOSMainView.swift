#if os(iOS)
import SwiftUI
import UIKit

/// Root view for iOS -- NavigationStack layout with meetings list,
/// NextMeetingCard at top, toolbar button for new recording, and pull-to-refresh.
struct iOSMainView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(ThemeManager.self) private var themeManager
    @State private var meetingVM = MeetingViewModel()
    @State private var recorder = AudioRecorder()
    @State private var calendarVM = CalendarViewModel()
    @State private var audioDeviceManager = AudioDeviceManagerIOS()
    @State private var showSettings = false
    @State private var showCreateSheet = false
    @State private var showRecordingView = false
    @State private var recordingMeetingId: String?
    @State private var recordingMeetingTitle: String = ""
    @State private var showTranscriptSheet = false
    @State private var searchText: String = ""
    @State private var toastManager = ToastManager()

    private var filteredMeetings: [MeetingMetadata] {
        if searchText.isEmpty {
            return meetingVM.meetings
        }
        return meetingVM.meetings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Next meeting card
                if calendarVM.calendarService.isAuthorized,
                   let nextEvent = calendarVM.calendarService.nextEvent {
                    Section {
                        NextMeetingCard(event: nextEvent) {
                            let data = calendarVM.meetingFromEvent(nextEvent)
                            meetingVM.createMeeting(title: data.title)
                            if let meeting = meetingVM.selectedMeeting {
                                startRecording(meetingId: meeting.id, title: meeting.title)
                            }
                        }
                        .listRowInsets(EdgeInsets(
                            top: DesignTokens.Spacing.space2,
                            leading: DesignTokens.Spacing.space4,
                            bottom: DesignTokens.Spacing.space2,
                            trailing: DesignTokens.Spacing.space4
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }

                // Recording indicator
                if recorder.isRecording {
                    Section {
                        HStack(spacing: DesignTokens.Spacing.space2) {
                            Circle()
                                .fill(Color.blockRed)
                                .frame(width: 8, height: 8)
                            Text(recordingMeetingTitle.isEmpty ? "Recording..." : recordingMeetingTitle)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(Color.blockRed)
                            Spacer()
                            Text(recorder.formattedDuration)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.blockRed)
                        }
                        .padding(.vertical, DesignTokens.Spacing.space1)
                        .listRowBackground(Color.blockRed.opacity(0.08))
                        .onTapGesture { showRecordingView = true }
                    }
                }

                // Meetings
                Section {
                    if meetingVM.isLoadingMeetings {
                        HStack {
                            Spacer()
                            ProgressView().tint(Color.accent)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    } else if filteredMeetings.isEmpty {
                        VStack {
                            if searchText.isEmpty {
                                EmptyStateView(
                                    icon: "text.bubble",
                                    title: "No meetings yet",
                                    subtitle: "Record your first meeting to get started",
                                    actionLabel: "Record Meeting",
                                    action: { showCreateSheet = true }
                                )
                            } else {
                                EmptyStateView(
                                    icon: "magnifyingglass",
                                    title: "No matches",
                                    subtitle: "Try a different search term"
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.space12)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredMeetings) { meeting in
                            NavigationLink(value: meeting) {
                                meetingRow(meeting)
                            }
                        }
                        .onDelete { offsets in
                            let meetings = filteredMeetings
                            for offset in offsets {
                                let meeting = meetings[offset]
                                meetingVM.deleteMeeting(meeting)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search meetings")
            .navigationTitle("Vaakya")
            .navigationDestination(for: MeetingMetadata.self) { meeting in
                iOSMeetingDetailView(
                    meetingId: meeting.id,
                    meetingVM: meetingVM,
                    recorder: recorder,
                    audioDeviceManager: audioDeviceManager,
                    onStartRecording: { mid, title in startRecording(meetingId: mid, title: title) },
                    onStopRecording: { stopRecording() }
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: {
                            showCreateSheet = true
                        }) {
                            Label("New Meeting", systemImage: "plus")
                        }
                        Button(action: {
                            meetingVM.createMeeting(title: "Quick Recording")
                            if let meeting = meetingVM.selectedMeeting {
                                startRecording(meetingId: meeting.id, title: meeting.title)
                            }
                        }) {
                            Label("Quick Recording", systemImage: "record.circle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accent)
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .refreshable {
                // Data is local -- just refresh calendar
                calendarVM.calendarService.loadUpcoming()
            }
        }
        .tint(Color.accent)
        .overlay(alignment: .top) {
            if let toast = toastManager.currentToast {
                ToastView(
                    message: toast.message,
                    type: toast.type,
                    onDismiss: { toastManager.dismiss() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: meetingVM.errorMessage) { _, newVal in
            if let msg = newVal {
                toastManager.show(msg, type: .error)
                meetingVM.errorMessage = nil
            }
        }
        .task {
            await calendarVM.setup()
        }
        .sheet(isPresented: $showCreateSheet) {
            iOSCreateMeetingSheet(meetingVM: meetingVM, isPresented: $showCreateSheet)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                iOSSettingsView()
                    .environment(auth)
            }
        }
        .fullScreenCover(isPresented: $showRecordingView) {
            iOSRecordingView(
                recorder: recorder,
                meetingTitle: recordingMeetingTitle,
                deviceName: audioDeviceManager.currentDeviceName,
                onStop: {
                    showRecordingView = false
                    stopRecording()
                }
            )
        }
    }

    // MARK: - Meeting Row

    private func meetingRow(_ meeting: MeetingMetadata) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space1) {
            Text(meeting.title)
                .font(DesignTokens.Typography.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            HStack(spacing: DesignTokens.Spacing.space3) {
                Text(meeting.formattedDate)
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(Color.textTertiary)

                if let dur = meeting.durationSeconds, dur > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(meeting.durationFormatted)
                            .font(DesignTokens.Typography.label)
                    }
                    .foregroundStyle(Color.textTertiary)
                }

                if meeting.speakerCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2")
                            .font(.system(size: 9))
                        Text("\(meeting.speakerCount)")
                            .font(DesignTokens.Typography.label)
                    }
                    .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.space1)
    }

    // MARK: - Recording Flow

    private func startRecording(meetingId: String, title: String) {
        recordingMeetingId = meetingId
        recordingMeetingTitle = title
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        showRecordingView = true

        if meetingVM.transcriptionService.isModelLoaded {
            // Model loaded → use WhisperKit streaming (it handles audio capture internally)
            // Do NOT also start AVAudioRecorder — they fight over AVAudioSession
            recorder.startTimerOnly()
            Task {
                await meetingVM.startStreamingTranscription()
            }
        } else {
            // No model loaded → simple AVAudioRecorder, transcribe file later
            // Don't try to load model mid-recording (takes 30-90s)
            recorder.requestPermissionAndRecord(meetingId: meetingId)
        }
    }

    private func stopRecording() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        let recorderAudioURL = recorder.stopRecording()
        showRecordingView = false

        if let meetingId = recordingMeetingId {
            Task {
                let streamAudioURL = await meetingVM.stopStreamingTranscription(meetingId: meetingId)
                let audioURL = streamAudioURL ?? recorderAudioURL

                if meetingVM.transcriptionService.segments.isEmpty, let url = audioURL {
                    #if DEBUG
                    print("[iOSMainView] Streaming produced no segments -- falling back to file-based transcription")
                    #endif
                    await meetingVM.transcribeMeeting(meetingId: meetingId, audioURL: url)
                }
            }
        }
        recordingMeetingId = nil
        recordingMeetingTitle = ""
    }
}

// MARK: - iOS Meeting Detail (adapted for phone)

struct iOSMeetingDetailView: View {
    let meetingId: String
    let meetingVM: MeetingViewModel
    let recorder: AudioRecorder
    let audioDeviceManager: AudioDeviceManagerIOS
    var onStartRecording: (String, String) -> Void
    var onStopRecording: () -> Void

    @State private var showTranscriptSheet = false
    @State private var showChatSheet = false

    private var meeting: MeetingDocument? {
        meetingVM.selectedMeeting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space4) {
                if let meeting = meeting {
                    // Metadata
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                        HStack(spacing: DesignTokens.Spacing.space3) {
                            HStack(spacing: DesignTokens.Spacing.space1) {
                                Image(systemName: "calendar").font(.system(size: 10))
                                let df = DateFormatter()
                                let _ = df.dateFormat = "MMM d, h:mm a"
                                Text(df.string(from: meeting.startedAt)).font(DesignTokens.Typography.label)
                            }.foregroundStyle(Color.textTertiary)

                            if let dur = meeting.durationSeconds, dur > 0 {
                                HStack(spacing: DesignTokens.Spacing.space1) {
                                    Image(systemName: "clock").font(.system(size: 10))
                                    Text("\(dur / 60) min").font(DesignTokens.Typography.label)
                                }.foregroundStyle(Color.textTertiary)
                            }

                            if meeting.speakerCount > 0 {
                                HStack(spacing: DesignTokens.Spacing.space1) {
                                    Image(systemName: "person.2").font(.system(size: 10))
                                    Text("\(meeting.speakerCount) speakers").font(DesignTokens.Typography.label)
                                }.foregroundStyle(Color.textTertiary)
                            }
                        }

                        PrivacyBadge(text: "Processed on your iPhone")
                    }

                    Divider().opacity(0.5)

                    // Blocks
                    if meetingVM.transcriptionService.isTranscribing {
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.space12)
                    } else if meetingVM.isLoadingBlocks {
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.space12)
                    } else if meetingVM.blocks.isEmpty {
                        EmptyStateView(
                            icon: "sparkles",
                            title: "No enhanced notes yet",
                            subtitle: "Click Enhance to create structured notes",
                            actionLabel: "Enhance Notes",
                            action: {
                                Task { await meetingVM.enhanceMeeting(meetingId: meeting.id) }
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.space12)
                    } else {
                        ForEach(meetingVM.blocks) { block in
                            BlockView(
                                block: block,
                                meetingId: meeting.id,
                                onToggle: { checked in
                                    meetingVM.toggleBlock(meetingId: meeting.id, blockId: block.id, checked: checked)
                                },
                                onDelete: {
                                    meetingVM.deleteBlock(meetingId: meeting.id, blockId: block.id)
                                },
                                onContentChange: { newContent in
                                    meetingVM.updateBlockContent(meetingId: meeting.id, blockId: block.id, content: newContent)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space3)
        }
        .background(Color.bgApp)
        .navigationTitle(meeting?.title ?? "Meeting")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let meeting = meeting {
                    Menu {
                        if recorder.isRecording {
                            Button(action: { onStopRecording() }) {
                                Label("Stop Recording", systemImage: "stop.circle")
                            }
                        } else {
                            Button(action: { onStartRecording(meeting.id, meeting.title) }) {
                                Label("Record", systemImage: "record.circle")
                            }
                        }

                        Button(action: {
                            Task { await meetingVM.enhanceMeeting(meetingId: meeting.id) }
                        }) {
                            Label("Enhance with AI", systemImage: "sparkles")
                        }

                        if !meeting.transcript.isEmpty {
                            Button(action: { showTranscriptSheet = true }) {
                                Label("Transcript", systemImage: "text.quote")
                            }
                        }

                        Button(action: { showChatSheet = true }) {
                            Label("Ask Vaakya", systemImage: "bubble.left.and.bubble.right")
                        }

                        Button(action: {
                            Task { await meetingVM.shareMeeting(meetingId: meeting.id) }
                        }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showTranscriptSheet) {
            if let meeting = meeting {
                NavigationStack {
                    let transcriptText = meeting.transcript.map { seg in
                        let speaker = seg.speaker.map { "[\($0)] " } ?? ""
                        return "[\(seg.startFormatted)] \(speaker)\(seg.text)"
                    }.joined(separator: "\n")
                    TranscriptView(
                        transcript: transcriptText,
                        meetingId: meeting.id,
                        blocks: meetingVM.blocks
                    )
                    .navigationTitle("Transcript")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showTranscriptSheet = false }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showChatSheet) {
            if let meeting = meeting {
                NavigationStack {
                    ChatView(meetingId: meeting.id)
                        .navigationTitle("Ask Vaakya")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showChatSheet = false }
                            }
                        }
                }
            }
        }
        .task {
            meetingVM.selectMeeting(id: meetingId)
        }
    }
}

// MARK: - Create Meeting Sheet

struct iOSCreateMeetingSheet: View {
    let meetingVM: MeetingViewModel
    @Binding var isPresented: Bool
    @State private var title: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meeting title", text: $title)
                }
            }
            .navigationTitle("New Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        meetingVM.createMeeting(title: title)
                        isPresented = false
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - iOS Settings (Form + Section layout)

struct iOSSettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var aiProvider: AIProvider
    @State private var openAIKey: String
    @State private var anthropicKey: String
    @State private var ollamaURL: String
    @State private var ollamaModel: String
    @State private var defaultTemplate: MeetingTemplate
    @State private var autoEnhance: Bool
    @State private var autoStartRecording: Bool
    @State private var calendarAccess: Bool
    @State private var autoDetectMeetings: Bool
    @State private var diarizationBackend: DiarizationBackendOption
    @State private var showDeleteConfirm: Bool = false

    init() {
        let defaults = UserDefaults.standard
        let providerRaw = defaults.string(forKey: SettingsKey.aiProvider) ?? AIProvider.platform.rawValue
        _aiProvider = State(initialValue: AIProvider(rawValue: providerRaw) ?? .platform)
        _openAIKey = State(initialValue: KeychainService.load(key: "vaakya_openai_key") ?? "")
        _anthropicKey = State(initialValue: KeychainService.load(key: "vaakya_anthropic_key") ?? "")
        _ollamaURL = State(initialValue: defaults.string(forKey: SettingsKey.ollamaURL) ?? "http://localhost:11434")
        _ollamaModel = State(initialValue: defaults.string(forKey: SettingsKey.ollamaModel) ?? "llama3.2")
        let templateRaw = defaults.string(forKey: SettingsKey.defaultTemplate) ?? MeetingTemplate.general.rawValue
        _defaultTemplate = State(initialValue: MeetingTemplate(rawValue: templateRaw) ?? .general)
        _autoEnhance = State(initialValue: defaults.bool(forKey: SettingsKey.autoEnhance))
        _autoStartRecording = State(initialValue: defaults.bool(forKey: SettingsKey.autoStartRecording))
        _calendarAccess = State(initialValue: defaults.bool(forKey: SettingsKey.calendarAccess))
        _autoDetectMeetings = State(initialValue: defaults.bool(forKey: SettingsKey.autoDetectMeetings))
        let backendRaw = defaults.string(forKey: SettingsKey.diarizationBackend) ?? DiarizationBackendOption.speakerKit.rawValue
        _diarizationBackend = State(initialValue: DiarizationBackendOption(rawValue: backendRaw) ?? .speakerKit)
    }

    var body: some View {
        Form {
            // MARK: - Recording
            Section("Audio Capture") {
                Toggle("Auto-start for calendar events", isOn: $autoStartRecording)
                Toggle("Calendar integration", isOn: $calendarAccess)
                Toggle("Auto-detect meetings", isOn: $autoDetectMeetings)
            }

            Section("Speaker Identification") {
                Picker("Engine", selection: $diarizationBackend) {
                    ForEach(DiarizationBackendOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            }

            // MARK: - Intelligence
            Section("AI Enhancement") {
                Picker("Provider", selection: $aiProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }

                if aiProvider == .openai {
                    SecureField("OpenAI API Key", text: $openAIKey)
                        .textContentType(.password)
                }
                if aiProvider == .anthropic {
                    SecureField("Anthropic API Key", text: $anthropicKey)
                        .textContentType(.password)
                }
                if aiProvider == .ollama {
                    TextField("Ollama URL", text: $ollamaURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                    TextField("Model", text: $ollamaModel)
                        .autocapitalization(.none)
                }
            }

            Section("Automation") {
                Toggle("Auto-enhance after recording", isOn: $autoEnhance)
                Picker("Default Template", selection: $defaultTemplate) {
                    ForEach(MeetingTemplate.allCases) { template in
                        Text(template.rawValue).tag(template)
                    }
                }
            }

            // MARK: - Account
            Section("Account") {
                if auth.isLoggedIn {
                    HStack {
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String(auth.currentUser?.email.prefix(1).uppercased() ?? "?"))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.currentUser?.email ?? "Signed in")
                                .font(DesignTokens.Typography.caption)
                            Text("Signed in with Apple")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    Button("Sign Out", role: .destructive) {
                        auth.logout()
                        dismiss()
                    }
                } else {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                        Text("Sign in to sync across devices")
                            .font(DesignTokens.Typography.bodyMedium)
                        Text("Your meetings stay on this device. Sign in to sync to other devices and share meetings.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Section {
                HStack(spacing: DesignTokens.Spacing.space2) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.vaGreen)
                    Text("Audio never leaves your device")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(Color.vaGreen)
                }
            }

            Section {
                Button("Delete All Data", role: .destructive) {
                    showDeleteConfirm = true
                }
            } footer: {
                Text("Permanently remove all meetings, transcripts, and notes from this device.")
                    .font(.system(size: 11))
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.accent)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    saveSettings()
                    dismiss()
                }
            }
        }
        .alert("Delete all data?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) {
                // Data deletion flow
            }
        } message: {
            Text("This will permanently delete \(LocalStore.shared.meetings.count) meetings, their transcripts, notes, and audio from this device. This cannot be undone.")
        }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(aiProvider.rawValue, forKey: SettingsKey.aiProvider)
        defaults.set(ollamaURL, forKey: SettingsKey.ollamaURL)
        defaults.set(ollamaModel, forKey: SettingsKey.ollamaModel)
        defaults.set(defaultTemplate.rawValue, forKey: SettingsKey.defaultTemplate)
        defaults.set(autoEnhance, forKey: SettingsKey.autoEnhance)
        defaults.set(autoStartRecording, forKey: SettingsKey.autoStartRecording)
        defaults.set(calendarAccess, forKey: SettingsKey.calendarAccess)
        defaults.set(autoDetectMeetings, forKey: SettingsKey.autoDetectMeetings)
        defaults.set(diarizationBackend.rawValue, forKey: SettingsKey.diarizationBackend)

        // Save API keys to Keychain
        KeychainService.save(key: "vaakya_openai_key", value: openAIKey)
        KeychainService.save(key: "vaakya_anthropic_key", value: anthropicKey)

        // Apply diarization backend
        Task { await DiarizationService.shared.applyBackendSetting(diarizationBackend) }

        // Save to local file
        let localSettings = LocalSettings(
            aiProvider: aiProvider.apiValue,
            ollamaURL: ollamaURL,
            ollamaModel: ollamaModel,
            defaultTemplate: defaultTemplate.apiValue,
            autoEnhance: autoEnhance,
            autoStartRecording: autoStartRecording
        )
        LocalStore.shared.saveSettings(localSettings)
    }
}
#endif
