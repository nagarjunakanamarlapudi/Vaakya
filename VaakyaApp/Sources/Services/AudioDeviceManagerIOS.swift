#if os(iOS)
import AVFoundation
import Foundation

/// Detects and manages audio input devices on iOS via AVAudioSession.
/// Watches for route changes (Bluetooth connect/disconnect, headset plug/unplug)
/// and auto-falls back to the built-in mic on disconnect.
@MainActor
@Observable
final class AudioDeviceManagerIOS {
    var availableInputs: [AVAudioSessionPortDescription] = []
    var selectedInput: AVAudioSessionPortDescription?
    var currentDeviceName: String = "iPhone Microphone"
    var disconnectMessage: String?

    @ObservationIgnored
    nonisolated(unsafe) var routeObserver: NSObjectProtocol?

    init() {
        refreshInputs()
        watchForRouteChanges()
    }

    // MARK: - Input Enumeration

    func refreshInputs() {
        let session = AVAudioSession.sharedInstance()
        availableInputs = session.availableInputs ?? []

        // Check if our selected input is still available
        if let selected = selectedInput {
            if !availableInputs.contains(where: { $0.portType == selected.portType && $0.portName == selected.portName }) {
                handleDisconnect(disconnectedName: selected.portName)
                return
            }
        }

        // Update current device name from the active route
        let currentRoute = session.currentRoute
        if let input = currentRoute.inputs.first {
            currentDeviceName = input.portName
        } else if let first = availableInputs.first {
            currentDeviceName = first.portName
        }
    }

    // MARK: - Input Selection

    func selectInput(_ input: AVAudioSessionPortDescription) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setPreferredInput(input)
            selectedInput = input
            currentDeviceName = input.portName
        } catch {
            #if DEBUG
            print("AudioDeviceManagerIOS: Failed to set preferred input: \(error)")
            #endif
        }
    }

    // MARK: - Disconnect Handling

    private func handleDisconnect(disconnectedName: String) {
        // Reset to default (system will fall back to built-in mic)
        let session = AVAudioSession.sharedInstance()
        try? session.setPreferredInput(nil)
        selectedInput = nil

        let currentRoute = session.currentRoute
        if let input = currentRoute.inputs.first {
            currentDeviceName = input.portName
            disconnectMessage = "Switched to \(input.portName)"
        } else {
            currentDeviceName = "iPhone Microphone"
            disconnectMessage = "Switched to iPhone Microphone"
        }

        // Clear the message after 3 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            disconnectMessage = nil
        }
    }

    // MARK: - Route Change Watching

    private func watchForRouteChanges() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason) {
                    switch changeReason {
                    case .oldDeviceUnavailable:
                        // A device was disconnected
                        if let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
                           let oldInput = previousRoute.inputs.first {
                            self.handleDisconnect(disconnectedName: oldInput.portName)
                        }
                    default:
                        break
                    }
                }

                self.refreshInputs()
            }
        }
    }

    deinit {
        if let observer = routeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
#endif
