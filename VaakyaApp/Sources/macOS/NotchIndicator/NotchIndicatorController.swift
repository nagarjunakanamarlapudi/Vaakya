#if os(macOS)
import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class NotchIndicatorController {
    private(set) var presentation = NotchPresentation(
        mode: .hidden,
        duration: 0,
        amplitude: 0,
        isFloating: false,
        isRecording: false
    )

    private let recorder: AudioRecorder
    private var window: NotchIndicatorWindow?
    private var isUninstalled = false

    // Timers — kept as separate variables so cancellation paths can't collide.
    private var heartbeatTimer: Timer?
    private var retractTimer: Timer?      // expanded → hidden while recording
    private var hideTimer: Timer?         // expandedStop → hidden after recording ends
    private var summonHideTimer: Timer?
    private var summonEnterDelayTimer: Timer?

    // Mouse monitor
    private var mouseMonitor: Any?

    // Recording state edge detection
    private var lastIsRecording = false

    // Configurable
    private let heartbeatInterval: TimeInterval = 30   // brief reappearance cadence
    private let expandedHoldShort: TimeInterval = 2.0  // how long the heartbeat / start stays expanded
    private let expandedHoldStop: TimeInterval = 1.0
    private let summonDelay: TimeInterval = 0.3
    private let summonVisibleFor: TimeInterval = 3.0

    init(recorder: AudioRecorder) {
        self.recorder = recorder
    }

    // MARK: - Lifecycle

    func install() {
        guard window == nil else { return }
        guard let screen = NotchGeometry.screenForIndicator() else {
            #if DEBUG
            print("[NotchIndicator] install: no screens available; will retry on screen change")
            #endif
            // Register only the screen-change observer so we can retry when a display appears.
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleScreenChange),
                name: NSApplication.didChangeScreenParametersNotification, object: nil
            )
            return
        }

        let savedX = NotchGeometry.hasPhysicalNotch(screen) ? nil : NotchPositionStore.savedX(for: screen)
        let baseFrame = NotchGeometry.defaultFrame(on: screen, savedX: savedX)
        // Use the expanded width as the panel width so the pill can grow without resizing the panel.
        let panelFrame = NSRect(
            x: baseFrame.midX - NotchGeometry.expandedWidth / 2,
            y: baseFrame.origin.y,
            width: NotchGeometry.expandedWidth,
            height: NotchGeometry.windowHeight
        )

        let win = NotchIndicatorWindow(contentRect: panelFrame)
        win.install(NotchIndicatorHost(controller: self))
        window = win

        presentation.isFloating = !NotchGeometry.hasPhysicalNotch(screen)

        installMouseMonitor()
        observeRecorder()

        // Reposition on screen parameter changes
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        win.orderFrontRegardless()
        refreshIgnoresMouse()
    }

    func uninstall() {
        isUninstalled = true
        invalidateAllTimers()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        NotificationCenter.default.removeObserver(self)
        window?.close()
        window = nil
    }

    // MARK: - Recorder observation (Observation framework)

    private func observeRecorder() {
        guard !isUninstalled else { return }
        withObservationTracking {
            _ = recorder.isRecording
            _ = recorder.recordingDuration
            _ = recorder.currentAmplitude
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isUninstalled else { return }
                self.observeRecorder()    // re-register first to avoid missing a rapid mutation
                self.onRecorderChanged()
            }
        }
    }

    private func onRecorderChanged() {
        // Real-time fields
        presentation.duration = recorder.recordingDuration
        presentation.amplitude = recorder.currentAmplitude
        presentation.isRecording = recorder.isRecording

        // Edge transitions
        let nowRecording = recorder.isRecording
        if nowRecording != lastIsRecording {
            if nowRecording {
                handleRecordingStarted()
            } else {
                handleRecordingStopped()
            }
            lastIsRecording = nowRecording
        }
    }

    // MARK: - State transitions

    private func handleRecordingStarted() {
        #if DEBUG
        print("[NotchIndicator] recording started — scheduling heartbeat every \(heartbeatInterval)s")
        #endif
        cancelSummonTimers()
        cancelHide()
        setMode(.expandedRecording)
        scheduleRetract(after: expandedHoldShort)
        startHeartbeat()
    }

    private func handleRecordingStopped() {
        #if DEBUG
        print("[NotchIndicator] recording stopped — final duration=\(Int(presentation.duration))s")
        #endif
        stopHeartbeat()
        cancelRetract()
        setMode(.expandedStop)
        scheduleHide(after: expandedHoldStop)
    }

    private func setMode(_ mode: NotchPresentation.Mode) {
        guard presentation.mode != mode else { return }
        presentation.mode = mode
        refreshIgnoresMouse()
    }

    private func refreshIgnoresMouse() {
        guard let window else { return }
        switch presentation.mode {
        case .hidden:
            window.ignoresMouseEvents = true
        case .summonedIdle, .expandedRecording, .expandedStop:
            window.ignoresMouseEvents = false
        }
    }

    // MARK: - Hover (from SwiftUI view)

    func setHover(_ hovering: Bool) {
        guard recorder.isRecording else { return }
        if hovering {
            cancelRetract()
            setMode(.expandedRecording)
        } else {
            scheduleRetract(after: 0.4)
        }
    }

    // MARK: - Click (from SwiftUI view)

    func handleClick() {
        guard recorder.isRecording else { return }
        // Post the canonical stop notification so MeetingDetailView can run its full teardown
        // (AVAudioRecorder stop + WhisperKit teardown + meeting save + diarization).
        NotificationCenter.default.post(name: .stopRecording, object: nil)
    }

    // MARK: - Drag (from SwiftUI view, non-notch only)

    private var dragOrigin: NSPoint?

    func handleDragDelta(_ translation: CGSize) {
        guard presentation.isFloating, let window else { return }
        if dragOrigin == nil { dragOrigin = window.frame.origin }
        guard let origin = dragOrigin else { return }
        // SwiftUI Y is flipped relative to AppKit; we only move X horizontally so dy is fine to apply unflipped vertically too if desired. We'll only support horizontal drag for simplicity.
        let newOrigin = NSPoint(x: origin.x + translation.width, y: origin.y)
        window.setFrameOrigin(newOrigin)
    }

    func handleDragEnded() {
        guard presentation.isFloating, let window else { return }
        dragOrigin = nil
        guard let screen = window.screen else { return }
        // Soft snap to center if within 20pt
        let centerX = screen.frame.midX - window.frame.width / 2
        var newX = window.frame.origin.x
        if abs(newX - centerX) < 20 {
            newX = centerX
            window.setFrameOrigin(NSPoint(x: newX, y: window.frame.origin.y))
        }
        NotchPositionStore.save(x: newX, for: screen)
    }

    // MARK: - Heartbeat / auto-retract

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isUninstalled else { return }
                self.fireHeartbeat()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func fireHeartbeat() {
        guard recorder.isRecording else { return }
        #if DEBUG
        print("[NotchIndicator] heartbeat fired — mode=\(presentation.mode), duration=\(Int(presentation.duration))s")
        #endif
        // `.hidden` is the resting state during recording (no separate `.retracted` mode exists).
        // Skip if currently expanded for hover / start — heartbeat is only for re-revealing from rest.
        if presentation.mode == .hidden {
            setMode(.expandedRecording)
            scheduleRetract(after: expandedHoldShort)
        }
    }

    private func scheduleRetract(after seconds: TimeInterval) {
        cancelRetract()
        retractTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isUninstalled else { return }
                self.retract()
            }
        }
    }

    private func cancelRetract() {
        retractTimer?.invalidate()
        retractTimer = nil
    }

    private func retract() {
        // Only retract from expanded-recording. expandedStop has its own hide path.
        guard presentation.mode == .expandedRecording else { return }
        // If recording continues, retract to hidden; otherwise stay (handleRecordingStopped will fire).
        if recorder.isRecording {
            setMode(.hidden)
        }
    }

    private func scheduleHide(after seconds: TimeInterval) {
        cancelHide()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isUninstalled else { return }
                self.setMode(.hidden)
            }
        }
    }

    private func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: - Summon (non-notch only)

    private func installMouseMonitor() {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, !self.isUninstalled else { return }
                self.evaluateMouseLocation(event)
            }
        }
        if monitor == nil {
            #if DEBUG
            print("[NotchIndicator] addGlobalMonitorForEvents returned nil — Input Monitoring may be denied; summon-on-hover disabled")
            #endif
        }
        mouseMonitor = monitor
    }

    private func evaluateMouseLocation(_ event: NSEvent) {
        guard presentation.isFloating else { return }                // only non-notch screens
        guard !recorder.isRecording else { return }                  // recording handles its own UI
        guard let window, let screen = window.screen else { return }
        let mouseInScreenCoords = NSEvent.mouseLocation
        let hotZone = NotchGeometry.summonHotZone(on: screen)
        let inHotZone = hotZone.contains(mouseInScreenCoords)

        switch presentation.mode {
        case .hidden where inHotZone:
            if summonEnterDelayTimer == nil {
                summonEnterDelayTimer = Timer.scheduledTimer(withTimeInterval: summonDelay, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, !self.isUninstalled else { return }
                        self.summon()
                    }
                }
            }
        case .summonedIdle where !inHotZone && !window.frame.contains(mouseInScreenCoords):
            scheduleSummonHide()
        case .hidden:
            cancelSummonEnterTimer()
        default:
            break
        }
    }

    private func summon() {
        cancelSummonEnterTimer()
        setMode(.summonedIdle)
        scheduleSummonHide()
    }

    private func scheduleSummonHide() {
        summonHideTimer?.invalidate()
        summonHideTimer = Timer.scheduledTimer(withTimeInterval: summonVisibleFor, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isUninstalled else { return }
                guard self.presentation.mode == .summonedIdle else { return }
                self.setMode(.hidden)
            }
        }
    }

    private func cancelSummonEnterTimer() {
        summonEnterDelayTimer?.invalidate()
        summonEnterDelayTimer = nil
    }

    private func cancelSummonTimers() {
        cancelSummonEnterTimer()
        summonHideTimer?.invalidate()
        summonHideTimer = nil
    }

    private func invalidateAllTimers() {
        stopHeartbeat()
        cancelRetract()
        cancelHide()
        cancelSummonTimers()
    }

    // MARK: - Screen change

    @objc private func handleScreenChange() {
        cancelSummonTimers()    // pending summon may be against a screen that's gone
        guard let screen = NotchGeometry.screenForIndicator() else {
            #if DEBUG
            print("[NotchIndicator] screen change: no screens; hiding window")
            #endif
            window?.orderOut(nil)
            return
        }
        // Retry install if the initial attempt happened with no screens.
        if window == nil {
            #if DEBUG
            print("[NotchIndicator] retrying install on screen change")
            #endif
            install()
            return
        }
        guard let window else { return }
        let savedX = NotchGeometry.hasPhysicalNotch(screen) ? nil : NotchPositionStore.savedX(for: screen)
        let baseFrame = NotchGeometry.defaultFrame(on: screen, savedX: savedX)
        let newFrame = NSRect(
            x: baseFrame.midX - NotchGeometry.expandedWidth / 2,
            y: baseFrame.origin.y,
            width: NotchGeometry.expandedWidth,
            height: NotchGeometry.windowHeight
        )
        window.setFrame(newFrame, display: true)
        presentation.isFloating = !NotchGeometry.hasPhysicalNotch(screen)
    }
}

// MARK: - SwiftUI host that bridges the controller to the view

private struct NotchIndicatorHost: View {
    let controller: NotchIndicatorController
    var body: some View {
        NotchIndicatorView(
            presentation: controller.presentation,
            onHoverChange: { controller.setHover($0) },
            onClick: { controller.handleClick() },
            onDragDelta: { controller.handleDragDelta($0) },
            onDragEnded: { controller.handleDragEnded() }
        )
    }
}
#endif
