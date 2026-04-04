import AVFoundation
import EventKit
import SwiftUI

// MARK: - Onboarding Constants

private enum OnboardingConstants {
    static let totalSteps = 5
    static let completionKey = "vaakya_onboarding_complete"
    static let maxContentWidth: CGFloat = 480
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @State private var step = 0
    @State private var modelManager = ModelManager()
    @State private var calendarService = CalendarService()

    // Permission states
    @State private var micGranted = false
    @State private var calendarGranted = false
    #if os(macOS)
    @State private var screenRecordingNoted = false
    #endif

    // Model download
    @State private var modelDownloaded = false
    @State private var isDownloadingModel = false

    var onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.bgApp.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Content area
                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: permissionsStep
                    case 2: modelDownloadStep
                    case 3: quickTourStep
                    case 4: doneStep
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: OnboardingConstants.maxContentWidth)

                Spacer()

                // Navigation: step dots + back/next
                navigationBar
                    .padding(.bottom, DesignTokens.Spacing.space8)
            }
            .padding(.horizontal, DesignTokens.Spacing.space8)
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 520)
        #endif
        .task {
            await modelManager.loadAvailableModels()
            checkExistingPermissions()
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: DesignTokens.Spacing.space6) {
            // App icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xl)
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 96, height: 96)

                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accent)
            }

            VStack(spacing: DesignTokens.Spacing.space3) {
                Text("Welcome to Vaakya")
                    .font(DesignTokens.Typography.pageTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text("AI-powered meeting notes that never leave your device")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            primaryButton("Get Started") {
                withAnimation(.spring(duration: 0.3)) { step = 1 }
            }
            .padding(.top, DesignTokens.Spacing.space4)
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space6) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                Text("Let's set things up")
                    .font(DesignTokens.Typography.pageTitle)
                    .foregroundStyle(Color.textPrimary)

                Text("Vaakya needs a few permissions to work its magic.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: DesignTokens.Spacing.space3) {
                // Microphone
                permissionRow(
                    icon: "mic.fill",
                    iconColor: Color.vaRed,
                    title: "Microphone",
                    description: "Record meeting audio",
                    isGranted: micGranted,
                    action: requestMicrophone
                )

                #if os(macOS)
                // System Audio (macOS only)
                permissionRow(
                    icon: "speaker.wave.2.fill",
                    iconColor: Color.vaBlue,
                    title: "System Audio",
                    description: "Capture what others say in calls",
                    isGranted: screenRecordingNoted,
                    action: openScreenRecordingSettings,
                    buttonLabel: "Open Settings"
                )
                #endif

                // Calendar
                permissionRow(
                    icon: "calendar",
                    iconColor: Color.vaYellow,
                    title: "Calendar",
                    description: "See your upcoming meetings",
                    isGranted: calendarGranted,
                    action: requestCalendar
                )
            }

            primaryButton("Continue") {
                withAnimation(.spring(duration: 0.3)) { step = 2 }
            }
            .disabled(!micGranted)
            .opacity(micGranted ? 1 : 0.5)
        }
    }

    // MARK: - Step 3: Model Download

    @State private var selectedModelId: String = ModelManager().recommendedModel

    private var modelDownloadStep: some View {
        VStack(spacing: DesignTokens.Spacing.space6) {
            VStack(spacing: DesignTokens.Spacing.space3) {
                Image(systemName: "brain")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accent)

                Text("Private transcription")
                    .font(DesignTokens.Typography.pageTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                #if os(macOS)
                let deviceName = "Mac"
                #else
                let deviceName = "iPhone"
                #endif

                Text("Audio is transcribed on your device — it never leaves your \(deviceName).")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            PrivacyBadge()

            // Model picker
            VStack(spacing: DesignTokens.Spacing.space2) {
                ForEach(WhisperModelOption.all) { option in
                    Button(action: { selectedModelId = option.id }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: DesignTokens.Spacing.space2) {
                                    Text(option.displayName)
                                        .font(DesignTokens.Typography.bodyMedium)
                                        .foregroundStyle(Color.textPrimary)
                                    if option.isRecommended {
                                        Text("Recommended")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(Color.accent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accent.opacity(0.10))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                Text("\(option.size) · \(option.quality) quality")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Spacer()
                            if selectedModelId == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accent)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .padding(DesignTokens.Spacing.space3)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .fill(selectedModelId == option.id ? Color.accent.opacity(0.10) : Color.bgCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .stroke(selectedModelId == option.id ? Color.accent.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Download progress or button
            if modelDownloaded {
                HStack {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(DesignTokens.Typography.bodyMedium)
                        .foregroundStyle(Color.vaGreen)
                }
            } else if isDownloadingModel {
                VStack(spacing: DesignTokens.Spacing.space2) {
                    ProgressView(value: modelManager.downloadProgress)
                        .tint(Color.accent)
                    Text("\(Int(modelManager.downloadProgress * 100))%")
                        .font(DesignTokens.Typography.label)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.space4)
            } else {
                primaryButton("Download Model") {
                    downloadModel()
                }
            }

            if let error = modelManager.error {
                Text(error)
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(Color.vaRed)
                    .multilineTextAlignment(.center)
            }

            // Skip or continue
            if modelDownloaded {
                primaryButton("Continue") {
                    withAnimation(.spring(duration: 0.3)) { step = 3 }
                }
            } else if !isDownloadingModel {
                Button("Skip for now") {
                    withAnimation(.spring(duration: 0.3)) { step = 3 }
                }
                .font(DesignTokens.Typography.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Step 4: Quick Tour

    private var quickTourStep: some View {
        VStack(spacing: DesignTokens.Spacing.space6) {
            Text("A quick look around")
                .font(DesignTokens.Typography.pageTitle)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            VStack(spacing: DesignTokens.Spacing.space3) {
                #if os(macOS)
                tourCard(
                    icon: "menubar.rectangle",
                    title: "Menu bar",
                    description: "Start recording from your menu bar — always one click away."
                )

                tourCard(
                    icon: "note.text",
                    title: "Floating notepad",
                    description: "Jot notes during meetings in a floating window."
                )
                #else
                tourCard(
                    icon: "mic.circle.fill",
                    title: "Record meetings",
                    description: "Record in-person meetings directly from your iPhone."
                )
                #endif

                tourCard(
                    icon: "sparkles",
                    title: "Enhance with AI",
                    description: "AI creates structured notes with decisions and action items."
                )

                tourCard(
                    icon: "text.quote",
                    title: "Full transcript",
                    description: "Full transcript with speaker labels and audio playback."
                )
            }

            primaryButton("Continue") {
                withAnimation(.spring(duration: 0.3)) { step = 4 }
            }
        }
    }

    // MARK: - Step 5: Done

    private var doneStep: some View {
        VStack(spacing: DesignTokens.Spacing.space6) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accent)
            }

            VStack(spacing: DesignTokens.Spacing.space3) {
                Text("You're all set!")
                    .font(DesignTokens.Typography.pageTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                if let nextEvent = calendarService.nextEvent,
                   let startDate = nextEvent.startDate as Date? {
                    let hours = Calendar.current.dateComponents([.hour, .minute], from: Date(), to: startDate)
                    let hourVal = hours.hour ?? 0
                    let minuteVal = hours.minute ?? 0

                    if hourVal > 0 || minuteVal > 0 {
                        Text("Your next meeting is in \(hourVal > 0 ? "\(hourVal)h " : "")\(minuteVal)m")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Start your first recording")
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("Start your first recording")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            primaryButton("Open Vaakya") {
                completeOnboarding()
            }
            .padding(.top, DesignTokens.Spacing.space4)
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Back button
            if step > 0 && step < 4 {
                Button(action: {
                    withAnimation(.spring(duration: 0.3)) { step -= 1 }
                }) {
                    HStack(spacing: DesignTokens.Spacing.space1) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(DesignTokens.Typography.bodyMedium)
                    }
                    .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 60)
            }

            Spacer()

            // Step indicator dots
            HStack(spacing: DesignTokens.Spacing.space2) {
                ForEach(0..<OnboardingConstants.totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accent : Color.vaBorder)
                        .frame(width: i == step ? 8 : 6, height: i == step ? 8 : 6)
                        .animation(.spring(duration: 0.2), value: step)
                }
            }

            Spacer()

            // Spacer to balance back button
            Spacer().frame(width: 60)
        }
    }

    // MARK: - Reusable Components

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: DesignTokens.Button.fontSize, weight: DesignTokens.Button.fontWeight))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: DesignTokens.Button.height)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Button.cornerRadius)
                        .fill(Color.accent)
                )
        }
        .buttonStyle(.plain)
    }

    private func permissionRow(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void,
        buttonLabel: String = "Grant"
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.space3) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)

                Text(description)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            // Status / Grant button
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.vaGreen)
            } else {
                Button(action: action) {
                    Text(buttonLabel)
                        .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DesignTokens.Spacing.space3)
                        .padding(.vertical, DesignTokens.Spacing.space1)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(Color.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignTokens.Spacing.space3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bgCard)
        )
    }

    private func tourCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.space4) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.accent.opacity(0.10))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)

                Text(description)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.space3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bgCard)
        )
    }

    // MARK: - Permission Actions

    private func checkExistingPermissions() {
        // Check microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micGranted = true
        default:
            micGranted = false
        }

        // Check calendar
        let ekStatus: EKAuthorizationStatus
        if #available(macOS 14.0, iOS 17.0, *) {
            ekStatus = EKEventStore.authorizationStatus(for: .event)
            calendarGranted = ekStatus == .fullAccess
        } else {
            ekStatus = EKEventStore.authorizationStatus(for: .event)
            calendarGranted = ekStatus == .authorized
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                micGranted = granted
            }
        }
    }

    private func requestCalendar() {
        Task {
            await calendarService.requestAccess()
            calendarGranted = calendarService.isAuthorized
        }
    }

    #if os(macOS)
    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        // Mark as noted since we can't programmatically check Screen Recording permission
        screenRecordingNoted = true
        // Enable system audio capture in settings so it's active after onboarding
        UserDefaults.standard.set(true, forKey: SettingsKey.captureSystemAudio)
    }
    #endif

    // MARK: - Model Download

    private func downloadModel() {
        isDownloadingModel = true
        Task {
            do {
                try await modelManager.downloadModel(selectedModelId)
                modelDownloaded = true
            } catch {
                // Error is already set on modelManager.error
            }
            isDownloadingModel = false
        }
    }

    // MARK: - Completion

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: OnboardingConstants.completionKey)
        onComplete()
    }
}
