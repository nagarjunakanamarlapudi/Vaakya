import SwiftUI
#if os(macOS)
import ScreenCaptureKit
#endif

// MARK: - Settings Keys (shared across platforms)

enum SettingsKey {
    static let aiProvider = "vaakya_ai_provider"
    static let openAIKey = "vaakya_openai_key"
    static let anthropicKey = "vaakya_anthropic_key"
    static let ollamaURL = "vaakya_ollama_url"
    static let ollamaModel = "vaakya_ollama_model"
    static let defaultTemplate = "vaakya_default_template"
    static let autoEnhance = "vaakya_auto_enhance"
    static let launchAtLogin = "vaakya_launch_at_login"
    static let autoStartRecording = "vaakya_auto_start_recording"
    static let calendarAccess = "vaakya_calendar_access"
    static let autoDetectMeetings = "vaakya_auto_detect_meetings"
    static let captureSystemAudio = "vaakya_capture_system_audio"
    static let diarizationBackend = "vaakya_diarization_backend"
    static let transcriptionLanguage = "vaakya_transcription_language"
    static let notesLanguage = "vaakya_notes_language"
}

enum DiarizationBackendOption: String, CaseIterable, Identifiable {
    case speakerKit = "SpeakerKit (Best)"
    case onnx = "ONNX pyannote"
    case energy = "Energy-based (Fast)"

    var id: String { rawValue }
}

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case auto = "auto"
    case english = "en"
    case hindi = "hi"
    case telugu = "te"
    case tamil = "ta"
    case kannada = "kn"

    var id: String { rawValue }
    var code: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .hindi: return "Hindi"
        case .telugu: return "Telugu"
        case .tamil: return "Tamil"
        case .kannada: return "Kannada"
        }
    }

    var subtitle: String {
        switch self {
        case .auto: return "Detect language automatically"
        case .english: return "American, British, Indian English"
        case .hindi: return "हिन्दी"
        case .telugu: return "తెలుగు"
        case .tamil: return "தமிழ்"
        case .kannada: return "ಕನ್ನಡ"
        }
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case platform = "Platform"
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case ollama = "Local Ollama"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .platform: return "platform"
        case .openai: return "openai"
        case .anthropic: return "anthropic"
        case .ollama: return "ollama"
        }
    }
}

enum MeetingTemplate: String, CaseIterable, Identifiable {
    case general = "General"
    case standup = "Standup"
    case oneOnOne = "1-on-1"
    case salesCall = "Sales Call"
    case interview = "Interview"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .general: return "general"
        case .standup: return "standup"
        case .oneOnOne: return "one_on_one"
        case .salesCall: return "sales_call"
        case .interview: return "interview"
        }
    }
}

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case recording = "Recording"
    case intelligence = "Intelligence"
    case account = "Account"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .recording:     return "mic"
        case .intelligence:  return "sparkles"
        case .account:       return "person.crop.circle"
        }
    }
}

#if os(macOS)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth
    @Environment(ThemeManager.self) private var themeManager

    @State private var selectedTab: SettingsTab = .recording
    @State private var aiProvider: AIProvider
    @State private var openAIKey: String
    @State private var anthropicKey: String
    @State private var ollamaURL: String
    @State private var ollamaModel: String
    @State private var defaultTemplate: MeetingTemplate
    @State private var autoEnhance: Bool
    @State private var launchAtLogin: Bool
    @State private var autoStartRecording: Bool
    @State private var calendarAccess: Bool
    @State private var autoDetectMeetings: Bool
    @State private var captureSystemAudio: Bool
    @State private var systemAudioPermission: Bool = false
    @State private var showOpenAIKey: Bool = false
    @State private var showAnthropicKey: Bool = false
    @State private var modelManager = ModelManager()
    @State private var isLoadingModels: Bool = false
    @State private var diarizationBackend: DiarizationBackendOption
    @State private var transcriptionLanguage: String
    @State private var notesLanguage: String
    @State private var showDeleteConfirm: Bool = false
    @State private var showManageDownloads: Bool = false

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
        _launchAtLogin = State(initialValue: defaults.bool(forKey: SettingsKey.launchAtLogin))
        _autoStartRecording = State(initialValue: defaults.bool(forKey: SettingsKey.autoStartRecording))
        _calendarAccess = State(initialValue: defaults.bool(forKey: SettingsKey.calendarAccess))
        _autoDetectMeetings = State(initialValue: defaults.bool(forKey: SettingsKey.autoDetectMeetings))
        _captureSystemAudio = State(initialValue: defaults.bool(forKey: SettingsKey.captureSystemAudio))
        let backendRaw = defaults.string(forKey: SettingsKey.diarizationBackend) ?? DiarizationBackendOption.speakerKit.rawValue
        _diarizationBackend = State(initialValue: DiarizationBackendOption(rawValue: backendRaw) ?? .speakerKit)
        _transcriptionLanguage = State(initialValue: defaults.string(forKey: SettingsKey.transcriptionLanguage) ?? "auto")
        _notesLanguage = State(initialValue: defaults.string(forKey: SettingsKey.notesLanguage) ?? "en")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(DesignTokens.Typography.pageTitle)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(Color.bgCard)
                                .shadow(color: DesignTokens.Shadow.cardColor, radius: 1, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.space6)
            .padding(.top, DesignTokens.Spacing.space6)
            .padding(.bottom, DesignTokens.Spacing.space4)

            // Tab bar (segmented)
            Picker("Settings", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DesignTokens.Spacing.space6)
            .padding(.bottom, DesignTokens.Spacing.space4)

            Divider().opacity(0.5)

            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.space6) {
                    switch selectedTab {
                    case .recording:     recordingTab
                    case .intelligence:  intelligenceTab
                    case .account:       accountTab
                    }
                }
                .padding(DesignTokens.Spacing.space6)
            }
        }
        .frame(width: 560, height: 580)
        .background(Color.bgApp)
        .task {
            loadModels()
            checkScreenRecordingPermission()
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

    // MARK: - Recording Tab

    @ViewBuilder
    private var recordingTab: some View {
        sectionLabel("Audio Capture")
        settingsCard {
            settingsToggleRow(
                title: "Capture system audio",
                subtitle: "Record from Zoom, Slack, Meet, Teams",
                isOn: Binding(get: { captureSystemAudio }, set: { newVal in
                    captureSystemAudio = newVal
                    saveSetting(SettingsKey.captureSystemAudio, value: newVal)
                    if newVal { checkScreenRecordingPermission() }
                })
            )

            if captureSystemAudio {
                permissionStatusRow
            }

            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)

            settingsToggleRow(
                title: "Auto-start for calendar events",
                subtitle: "Prompt when a scheduled meeting begins",
                isOn: Binding(get: { autoStartRecording }, set: { newVal in
                    autoStartRecording = newVal
                    saveSetting(SettingsKey.autoStartRecording, value: newVal)
                })
            )

            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)

            settingsToggleRow(
                title: "Calendar integration",
                subtitle: "Show upcoming meetings in menu bar",
                isOn: Binding(get: { calendarAccess }, set: { newVal in
                    calendarAccess = newVal
                    saveSetting(SettingsKey.calendarAccess, value: newVal)
                })
            )
        }

        sectionLabel("Transcription")
        settingsCard {
            ForEach(Array(WhisperModelOption.all.enumerated()), id: \.element.id) { index, model in
                let isActive = modelManager.currentModel == model.id
                radioRow(
                    title: model.displayName,
                    subtitle: model.quality == "Best" ? "Best quality" : model.quality == "Good" ? "Good quality" : "Fast, basic",
                    isSelected: isActive,
                    isRecommended: model.isRecommended,
                    isDownloading: modelManager.isDownloading && modelManager.currentModel == model.id,
                    downloadProgress: modelManager.downloadProgress
                ) {
                    Task { await modelManager.selectModel(model.id) }
                }
                if index < WhisperModelOption.all.count - 1 {
                    Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)
                }
            }

            if let error = modelManager.error {
                HStack(spacing: DesignTokens.Spacing.space2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.vaRed)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.vaRed)
                }
                .padding(.horizontal, DesignTokens.Block.padding)
                .padding(.vertical, DesignTokens.Spacing.space2)
            }

            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)
            DisclosureGroup(isExpanded: $showManageDownloads) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                    ForEach(WhisperModelOption.all) { model in
                        let isDownloaded = modelManager.downloadedModels.contains(where: { $0 == model.id })
                        HStack {
                            Text(model.displayName)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textPrimary)
                            Text(model.size)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                            if isDownloaded {
                                Button(action: { try? modelManager.deleteModel(model.id) }) {
                                    Text("Remove")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.vaRed)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("Not downloaded")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Text("\(modelManager.diskUsage()) used")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.space4)
                .padding(.vertical, DesignTokens.Spacing.space2)
            } label: {
                Text("Manage Downloads")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, DesignTokens.Block.padding)
            .padding(.vertical, DesignTokens.Spacing.space2)
        }

        sectionLabel("Transcription Language")
        settingsCard {
            ForEach(TranscriptionLanguage.allCases) { lang in
                radioRow(
                    title: lang.displayName,
                    subtitle: lang.subtitle,
                    isSelected: transcriptionLanguage == lang.code,
                    isRecommended: lang == .auto
                ) {
                    transcriptionLanguage = lang.code
                    UserDefaults.standard.set(lang.code, forKey: SettingsKey.transcriptionLanguage)
                }
                if lang != TranscriptionLanguage.allCases.last {
                    Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)
                }
            }
        }

        sectionLabel("Speaker Identification")
        settingsCard {
            ForEach(Array(diarizationOptions.enumerated()), id: \.element.option) { index, item in
                let isActive = diarizationBackend == item.option
                radioRow(
                    title: item.name,
                    subtitle: item.quality,
                    isSelected: isActive,
                    isRecommended: item.option == .speakerKit
                ) {
                    diarizationBackend = item.option
                    UserDefaults.standard.set(item.option.rawValue, forKey: SettingsKey.diarizationBackend)
                    Task { await DiarizationService.shared.applyBackendSetting(item.option) }
                }
                if index < diarizationOptions.count - 1 {
                    Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)
                }
            }
        }
    }

    @ViewBuilder
    private var permissionStatusRow: some View {
        if systemAudioPermission {
            HStack(spacing: 6) {
                Circle().fill(Color.vaGreen).frame(width: 6, height: 6)
                Text("Screen Recording permission granted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.vaGreen)
            }
            .padding(.horizontal, DesignTokens.Block.padding)
            .padding(.vertical, DesignTokens.Spacing.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vaGreen.opacity(0.04))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.vaYellow)
                Text("Screen Recording permission required")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button(action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Open Settings")
                        .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Block.padding)
            .padding(.vertical, DesignTokens.Spacing.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vaYellow.opacity(0.06))
        }
    }

    private var diarizationOptions: [DiarizationOptionInfo] {
        [
            DiarizationOptionInfo(option: .speakerKit, name: "SpeakerKit", size: "~20 MB", quality: "Best accuracy"),
            DiarizationOptionInfo(option: .onnx, name: "ONNX pyannote", size: "~5 MB", quality: "Good accuracy"),
            DiarizationOptionInfo(option: .energy, name: "Energy-based", size: "No download", quality: "Fast, basic"),
        ]
    }

    private struct DiarizationOptionInfo {
        let option: DiarizationBackendOption
        let name: String
        let size: String
        let quality: String
    }

    // MARK: - Intelligence Tab

    @ViewBuilder
    private var intelligenceTab: some View {
        sectionLabel("AI Enhancement")
        settingsCard {
            HStack {
                Text("Provider")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Picker("", selection: Binding(get: { aiProvider }, set: { newVal in
                    aiProvider = newVal
                    UserDefaults.standard.set(newVal.rawValue, forKey: SettingsKey.aiProvider)
                    saveSettingsToFile()
                })) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.textSecondary)
                .frame(width: 160)
            }
            .padding(.horizontal, DesignTokens.Block.padding)
            .padding(.vertical, DesignTokens.Spacing.space3)

            if aiProvider == .openai {
                conditionalFieldArea {
                    apiKeyField(label: "OpenAI API Key", placeholder: "sk-...", text: $openAIKey, showKey: $showOpenAIKey)
                }
            }

            if aiProvider == .anthropic {
                conditionalFieldArea {
                    apiKeyField(label: "Anthropic API Key", placeholder: "sk-ant-...", text: $anthropicKey, showKey: $showAnthropicKey)
                }
            }

            if aiProvider == .ollama {
                conditionalFieldArea {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.space3) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                            Text("Ollama URL")
                                .font(DesignTokens.Typography.label)
                                .foregroundStyle(Color.textSecondary)
                            textInputField("http://localhost:11434", text: Binding(get: { ollamaURL }, set: { newVal in
                                ollamaURL = newVal
                                UserDefaults.standard.set(newVal, forKey: SettingsKey.ollamaURL)
                                saveSettingsToFile()
                            }), monospaced: true)
                        }
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                            Text("Model")
                                .font(DesignTokens.Typography.label)
                                .foregroundStyle(Color.textSecondary)
                            textInputField("llama3.2", text: Binding(get: { ollamaModel }, set: { newVal in
                                ollamaModel = newVal
                                UserDefaults.standard.set(newVal, forKey: SettingsKey.ollamaModel)
                                saveSettingsToFile()
                            }))
                        }
                    }
                }
            }
        }

        sectionLabel("Automation")
        settingsCard {
            settingsToggleRow(
                title: "Auto-enhance after recording",
                subtitle: "Run AI enhancement when recording ends",
                isOn: Binding(get: { autoEnhance }, set: { newVal in
                    autoEnhance = newVal
                    saveSetting(SettingsKey.autoEnhance, value: newVal)
                })
            )

            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)

            HStack {
                Text("Default template")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Picker("", selection: Binding(get: { defaultTemplate }, set: { newVal in
                    defaultTemplate = newVal
                    UserDefaults.standard.set(newVal.rawValue, forKey: SettingsKey.defaultTemplate)
                    saveSettingsToFile()
                })) {
                    ForEach(MeetingTemplate.allCases) { template in
                        Text(template.rawValue).tag(template)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.textSecondary)
                .frame(width: 140)
            }
            .padding(.horizontal, DesignTokens.Block.padding)
            .padding(.vertical, DesignTokens.Spacing.space3)
        }

        sectionLabel("Notes Language")
        settingsCard {
            ForEach(TranscriptionLanguage.allCases.filter { $0 != .auto }, id: \.self) { lang in
                radioRow(
                    title: lang.displayName,
                    subtitle: lang.subtitle,
                    isSelected: notesLanguage == lang.code,
                    isRecommended: lang == .english
                ) {
                    notesLanguage = lang.code
                    UserDefaults.standard.set(lang.code, forKey: SettingsKey.notesLanguage)
                    var settings = LocalStore.shared.loadSettings()
                    settings.notesLanguage = lang.code
                    LocalStore.shared.saveSettings(settings)
                }
                if lang != TranscriptionLanguage.allCases.filter({ $0 != .auto }).last {
                    Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)
                }
            }
        }
    }

    // MARK: - Account Tab

    @ViewBuilder
    private var accountTab: some View {
        sectionLabel("Account")
        if auth.isLoggedIn {
            settingsCard {
                HStack(spacing: DesignTokens.Spacing.space3) {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(auth.currentUser?.email.prefix(1).uppercased() ?? "?"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.currentUser?.email ?? "Signed in")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                        Text("Signed in with Apple")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Button(action: {
                        auth.logout()
                        dismiss()
                    }) {
                        Text("Sign Out")
                            .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, DesignTokens.Spacing.space3)
                            .padding(.vertical, DesignTokens.Spacing.space1)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Button.compactCornerRadius)
                                    .fill(Color.bgCard)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.Block.padding)
                .padding(.vertical, DesignTokens.Spacing.space3)
            }
        } else {
            signedOutCard
        }

        sectionLabel("Sync")
        settingsCard {
            let syncService = SyncService.shared
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync across devices")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                    if auth.isLoggedIn {
                        if let lastSync = syncService.lastSyncDate {
                            Text("Last synced \(lastSync, style: .relative) ago")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textTertiary)
                        }
                    } else {
                        Text("Sign in to enable sync")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                Spacer()
                Button(action: {
                    Task { await syncService.sync() }
                }) {
                    if syncService.isSyncing {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.6).tint(Color.accent)
                            Text("Syncing...")
                                .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                        }
                        .foregroundStyle(Color.accent)
                    } else {
                        Text("Sync Now")
                            .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                            .foregroundStyle(Color.accent)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignTokens.Spacing.space3)
                .padding(.vertical, DesignTokens.Spacing.space1)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Button.compactCornerRadius)
                        .fill(Color.accent.opacity(0.08))
                )
                .disabled(!auth.isLoggedIn || syncService.isSyncing)
            }
            .padding(.horizontal, DesignTokens.Block.padding)
            .padding(.vertical, DesignTokens.Spacing.space3)

            if auth.isLoggedIn {
                Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)
                HStack(spacing: 6) {
                    Image(systemName: syncService.isWifi ? "wifi" : "cellularbars")
                        .font(.system(size: 10))
                    Text(syncService.isWifi ? "Wi-Fi connected — audio will sync" : "Cellular — audio sync paused")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, DesignTokens.Block.padding)
                .padding(.vertical, DesignTokens.Spacing.space2)
            }

            if let error = syncService.syncError {
                HStack(spacing: DesignTokens.Spacing.space2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.vaRed)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.vaRed)
                }
                .padding(.horizontal, DesignTokens.Block.padding)
                .padding(.vertical, DesignTokens.Spacing.space2)
            }
        }
        .opacity(auth.isLoggedIn ? 1 : 0.45)

        sectionLabel("Preferences")
        settingsCard {
            HStack {
                Text("Theme")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                @Bindable var tm = themeManager
                Picker("", selection: $tm.appearanceMode) {
                    ForEach(ThemeManager.AppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal, DesignTokens.Block.padding)
            .padding(.vertical, DesignTokens.Spacing.space3)

            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)

            settingsToggleRow(
                title: "Launch at login",
                subtitle: nil,
                isOn: Binding(get: { launchAtLogin }, set: { newVal in
                    launchAtLogin = newVal
                    saveSetting(SettingsKey.launchAtLogin, value: newVal)
                })
            )
        }

        dangerZoneLabel
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete all data")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                    Text("Permanently remove all meetings from this device")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Button(action: { showDeleteConfirm = true }) {
                    Text("Delete...")
                        .font(.system(size: DesignTokens.Button.compactFontSize, weight: .semibold))
                        .foregroundStyle(Color.vaRed)
                        .padding(.horizontal, DesignTokens.Spacing.space3)
                        .padding(.vertical, DesignTokens.Spacing.space1)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Button.compactCornerRadius)
                                .fill(Color.vaRed.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(DesignTokens.Block.padding)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .stroke(Color.vaRed.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: DesignTokens.Shadow.cardColor, radius: DesignTokens.Shadow.cardRadius, y: DesignTokens.Shadow.cardY)
        )
    }

    @ViewBuilder
    private var signedOutCard: some View {
        settingsCard {
            VStack(spacing: DesignTokens.Spacing.space4) {
                VStack(spacing: DesignTokens.Spacing.space2) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.textTertiary)
                    Text("Sign in to sync across devices")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Your meetings stay on this device. Sign in to sync to other Macs and iPhones, share meetings, and access platform AI.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .padding(.top, DesignTokens.Spacing.space2)

                VStack(spacing: DesignTokens.Spacing.space2) {
                    Button(action: { auth.signInWithApple() }) {
                        HStack(spacing: DesignTokens.Spacing.space2) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 14))
                            Text("Sign in with Apple")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: DesignTokens.Button.height)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Button.cornerRadius)
                                .fill(Color(hex: 0x1A1A1A))
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: { Task { await auth.signInWithGoogle() } }) {
                        HStack(spacing: DesignTokens.Spacing.space2) {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 14))
                            Text("Sign in with Google")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: DesignTokens.Button.height)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Button.cornerRadius)
                                .fill(Color.bgCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Button.cornerRadius)
                                        .stroke(Color.vaBorder, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.vaRed)
                }
            }
            .padding(DesignTokens.Block.padding)
        }
    }

    // MARK: - Shared Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.leading, 4)
    }

    private var dangerZoneLabel: some View {
        Text("Danger Zone")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.vaRed)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.leading, 4)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bgCard)
                .shadow(color: DesignTokens.Shadow.cardColor, radius: DesignTokens.Shadow.cardRadius, y: DesignTokens.Shadow.cardY)
        )
    }

    private func settingsToggleRow(title: String, subtitle: String?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Color.accent)
        .padding(.horizontal, DesignTokens.Block.padding)
        .padding(.vertical, DesignTokens.Spacing.space3)
    }

    private func radioRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        isRecommended: Bool = false,
        isDownloading: Bool = false,
        downloadProgress: Double = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.space3) {
                Circle()
                    .strokeBorder(isSelected ? Color.accent : Color.textTertiary.opacity(0.5), lineWidth: 2)
                    .frame(width: 18, height: 18)
                    .overlay(
                        isSelected
                            ? Circle().fill(Color.accent).frame(width: 8, height: 8)
                            : nil
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(Color.textPrimary)
                        if isRecommended {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.accent.opacity(0.12)))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                if isDownloading {
                    HStack(spacing: 6) {
                        ProgressView(value: downloadProgress)
                            .frame(width: 60)
                            .tint(Color.accent)
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DesignTokens.Block.padding)
        .padding(.vertical, DesignTokens.Spacing.space3)
        .background(isSelected ? Color.accent.opacity(0.04) : Color.clear)
    }

    private func conditionalFieldArea<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space3) {
            content()
        }
        .padding(.horizontal, DesignTokens.Block.padding)
        .padding(.vertical, DesignTokens.Spacing.space3)
        .background(Color.bgApp.opacity(0.5))
    }

    private func apiKeyField(label: String, placeholder: String, text: Binding<String>, showKey: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
            Text(label)
                .font(DesignTokens.Typography.label)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: DesignTokens.Spacing.space2) {
                Group {
                    if showKey.wrappedValue {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, DesignTokens.Spacing.space3)
                .padding(.vertical, DesignTokens.Spacing.space2)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(Color.bgContent)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .stroke(Color.vaBorder, lineWidth: 1)
                        )
                )
                .onSubmit { saveAPIKeys() }

                Button(action: { showKey.wrappedValue.toggle() }) {
                    Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func textInputField(_ placeholder: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 13, design: .monospaced) : .system(size: 13))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, DesignTokens.Spacing.space3)
            .padding(.vertical, DesignTokens.Spacing.space2)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.bgContent)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .stroke(Color.vaBorder, lineWidth: 1)
                    )
            )
    }

    // MARK: - Auto-save

    private func saveSetting(_ key: String, value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
        saveSettingsToFile()
    }

    private func saveAPIKeys() {
        KeychainService.save(key: "vaakya_openai_key", value: openAIKey)
        KeychainService.save(key: "vaakya_anthropic_key", value: anthropicKey)
    }

    private func saveSettingsToFile() {
        var localSettings = LocalSettings(
            aiProvider: aiProvider.apiValue,
            ollamaURL: ollamaURL,
            ollamaModel: ollamaModel,
            defaultTemplate: defaultTemplate.apiValue,
            autoEnhance: autoEnhance,
            captureSystemAudio: captureSystemAudio,
            launchAtLogin: launchAtLogin,
            autoStartRecording: autoStartRecording
        )
        localSettings.notesLanguage = notesLanguage
        LocalStore.shared.saveSettings(localSettings)
    }

    private func loadModels() {
        isLoadingModels = true
        Task {
            await modelManager.loadAvailableModels()
            isLoadingModels = false
        }
    }

    private func checkScreenRecordingPermission() {
        Task {
            do {
                _ = try await SCShareableContent.current
                systemAudioPermission = true
            } catch {
                systemAudioPermission = false
            }
        }
    }
}
#endif
