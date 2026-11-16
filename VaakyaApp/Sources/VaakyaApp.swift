import FirebaseCore
import SwiftUI

// Color palette is now in Theme/DesignTokens.swift

// MARK: - Notification Names (cross-platform)

extension Notification.Name {
    static let toggleFloatingPanel = Notification.Name("toggleFloatingPanel")
    static let toggleTranscript = Notification.Name("toggleTranscript")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let enhanceMeeting = Notification.Name("enhanceMeeting")
    static let newMeeting = Notification.Name("newMeeting")
    static let startRecording = Notification.Name("startRecording")
    static let stopRecording = Notification.Name("stopRecording")
}

// MARK: - macOS App Delegate

#if os(macOS)

class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FirebaseApp.configure()

        // Check for --e2e flag
        if CommandLine.arguments.contains("--e2e") {
            Task { @MainActor in
                await runE2ETests()
                NSApp.terminate(nil)
            }
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Register Cmd+Shift+V to toggle floating panel minimize/expand
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let cmd = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            let key = event.charactersIgnoringModifiers ?? ""

            // Cmd+Shift+V -- toggle floating panel
            if cmd && shift && key == "v" {
                guard FloatingPanelManager.shared.isVisible else { return event }
                NotificationCenter.default.post(name: .toggleFloatingPanel, object: nil)
                return nil
            }
            // Cmd+] -- toggle transcript
            if cmd && !shift && key == "]" {
                NotificationCenter.default.post(name: .toggleTranscript, object: nil)
                return nil
            }
            // Cmd+[ -- toggle sidebar
            if cmd && !shift && key == "[" {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                return nil
            }
            // Cmd+E -- enhance
            if cmd && !shift && key == "e" {
                NotificationCenter.default.post(name: .enhanceMeeting, object: nil)
                return nil
            }
            // Cmd+N -- new meeting
            if cmd && !shift && key == "n" {
                NotificationCenter.default.post(name: .newMeeting, object: nil)
                return nil
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        // Flush LocalStore synchronously on app termination — a detached Task
        // would not complete before the process exits.
        MainActor.assumeIsolated {
            LocalStore.shared.shutdown()
        }
    }
}

#endif

// MARK: - App Entry Point

@main
struct VaakyaApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @State private var auth = AuthViewModel()
    @State private var themeManager = ThemeManager()
    @State private var onboardingComplete = UserDefaults.standard.bool(forKey: "vaakya_onboarding_complete")
    @State private var appReady = false
    @State private var loadingStatus = "Loading meetings..."
    @State private var loadingProgress: Double = 0
    @State private var loadingModelName = ""

    #if os(macOS)
    private let menuBarRecorder = AudioRecorder.shared
    @State private var calendarVM = CalendarViewModel()
    @State private var menuBarMeetingVM = MeetingViewModel()
    @State private var notchController: NotchIndicatorController?
    #endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            Group {
                if !appReady {
                    // Loading screen — LocalStore + WhisperKit model
                    VStack(spacing: DesignTokens.Spacing.space6) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accent)
                        Text("Vaakya")
                            .font(DesignTokens.Typography.pageTitle)
                            .foregroundStyle(Color.textPrimary)

                        VStack(spacing: DesignTokens.Spacing.space2) {
                            ProgressView(value: loadingProgress)
                                .tint(Color.accent)
                                .frame(width: 240)

                            Text(loadingStatus)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(Color.textTertiary)

                            if !loadingModelName.isEmpty {
                                Text(loadingModelName)
                                    .font(DesignTokens.Typography.label)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bgApp)
                } else if !onboardingComplete {
                    OnboardingView {
                        withAnimation(.spring(duration: 0.3)) {
                            onboardingComplete = true
                        }
                    }
                } else {
                    MainView()
                        .environment(auth)
                }
            }
            .environment(themeManager)
            .preferredColorScheme(themeManager.resolvedColorScheme)
            .task {
                // Step 1: Load meetings from disk (fast)
                loadingStatus = "Loading meetings..."
                withAnimation(.easeOut(duration: 0.3)) { loadingProgress = 0.1 }
                await LocalStore.shared.initialize()
                withAnimation(.easeOut(duration: 0.3)) { loadingProgress = 0.2 }

                // Step 2: Load WhisperKit model (slow — 30-90s for large model)
                let modelManager = ModelManager()
                let modelName = modelManager.currentModel ?? modelManager.recommendedModel
                let displayName = WhisperModelOption.all.first(where: { $0.id == modelName })?.displayName ?? modelName
                loadingModelName = displayName
                loadingStatus = "Loading \(displayName) model..."

                // Animate progress smoothly while model loads
                let progressTask = Task {
                    var current = 0.2
                    while current < 0.9 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        current += 0.01 // Slow crawl to 90%
                        withAnimation(.easeOut(duration: 0.5)) { loadingProgress = current }
                    }
                }

                try? await TranscriptionService.shared.loadModel(modelName, directory: modelManager.modelsDirectoryURL)
                progressTask.cancel()
                withAnimation(.easeOut(duration: 0.3)) { loadingProgress = 0.95 }

                // Step 3: Download + load SpeakerKit diarization models (~20 MB first time)
                loadingStatus = "Loading speaker detection..."
                await DiarizationService.shared.setupSpeakerKit()
                withAnimation(.easeOut(duration: 0.3)) { loadingProgress = 0.97 }

                // Step 4: Check auth (fast)
                loadingStatus = "Almost ready..."
                await auth.checkSession()
                withAnimation(.easeOut(duration: 0.3)) { loadingProgress = 1.0 }

                // Done
                try? await Task.sleep(nanoseconds: 300_000_000) // Brief pause at 100%
                withAnimation(.easeOut(duration: 0.3)) {
                    appReady = true
                }

                // Install the notch indicator now that the app is ready.
                if notchController == nil {
                    let c = NotchIndicatorController(recorder: menuBarRecorder)
                    c.install()
                    notchController = c
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra("Vaakya", systemImage: menuBarRecorder.isRecording ? "record.circle.fill" : "text.bubble") {
            VStack(alignment: .leading, spacing: 0) {
                // Status line
                HStack {
                    if menuBarRecorder.isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text(RecordingSession.shared.meetingTitle.isEmpty
                                 ? "Recording..."
                                 : RecordingSession.shared.meetingTitle)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                    } else {
                        Text("No active meeting")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Next meeting from calendar
                if calendarVM.calendarService.isAuthorized, let nextEvent = calendarVM.calendarService.nextEvent {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("Next Meeting")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(nextEvent.title ?? "Untitled")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text({
                                let f = DateFormatter()
                                f.dateFormat = "h:mm a"
                                return f.string(from: nextEvent.startDate)
                            }())
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            if let attendees = nextEvent.attendees, !attendees.isEmpty {
                                Text("--")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                                Text("\(attendees.count) participant\(attendees.count == 1 ? "" : "s")")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                Divider()

                // Start Recording
                Button(action: {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first {
                        window.makeKeyAndOrderFront(nil)
                    }
                    NotificationCenter.default.post(name: .startRecording, object: nil)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                        Text("Start Recording")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\u{2318}\u{21E7}R")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                // Show Vaakya
                Button(action: {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first {
                        window.makeKeyAndOrderFront(nil)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 11))
                        Text("Show Vaakya")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\u{2318}\u{2325}M")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                // Meeting Library
                Button(action: {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first {
                        window.makeKeyAndOrderFront(nil)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 11))
                        Text("Meeting Library")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\u{2318}\u{21E7}L")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                Divider()

                // Recent meetings (last 3) from LocalStore
                if !LocalStore.shared.meetings.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)

                        ForEach(Array(LocalStore.shared.meetings.prefix(3))) { meeting in
                            Button(action: {
                                NSApplication.shared.activate(ignoringOtherApps: true)
                                if let window = NSApplication.shared.windows.first {
                                    window.makeKeyAndOrderFront(nil)
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(meeting.title)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                        Text(meeting.formattedDate)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                } else {
                    Text("No recent meetings")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }

                Divider()

                // Privacy badge
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("Audio never leaves your Mac")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                // Quit
                Button(action: {
                    LocalStore.shared.shutdown()
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "power")
                            .font(.system(size: 11))
                        Text("Quit Vaakya")
                            .font(.system(size: 13))
                        Spacer()
                        Text("\u{2318}Q")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            .frame(width: 260)
            .task {
                await calendarVM.setup()
            }
        }

        #else
        // iOS
        WindowGroup {
            Group {
                if !LocalStore.shared.isInitialized {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                } else if !onboardingComplete {
                    OnboardingView {
                        withAnimation(.spring(duration: 0.3)) {
                            onboardingComplete = true
                        }
                    }
                    .environment(themeManager)
                } else {
                    iOSMainView()
                        .environment(auth)
                        .environment(themeManager)
                }
            }
            .preferredColorScheme(themeManager.resolvedColorScheme)
            .task {
                FirebaseApp.configure()
                await LocalStore.shared.initialize()
                await auth.checkSession()
            }
        }
        #endif
    }
}
