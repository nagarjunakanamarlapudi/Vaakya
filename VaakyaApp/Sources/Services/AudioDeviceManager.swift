#if os(macOS)
import AVFoundation
import CoreAudio
import Foundation

/// Detects and manages audio input devices on macOS via CoreAudio.
/// Watches for device changes (plug/unplug, Bluetooth connect/disconnect)
/// and auto-falls back to the default device on disconnect.
@MainActor
@Observable
final class AudioDeviceManager {
    var availableDevices: [AudioInputDevice] = []
    var selectedDevice: AudioInputDevice?
    var currentDeviceName: String = "Default"
    var disconnectMessage: String?

    /// Stores the listener block for device-change notifications.
    /// Using `@ObservationIgnored` so that the `@Observable` macro's `@ObservationTracked`
    /// expansion does not conflict with `nonisolated(unsafe)` needed for deinit access.
    @ObservationIgnored
    nonisolated(unsafe) var _listenerBlock: AudioObjectPropertyListenerBlock?

    struct AudioInputDevice: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
        let uid: String
    }

    init() {
        refreshDevices()
        watchForChanges()
    }

    // MARK: - Device Enumeration

    func refreshDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return }

        var inputDevices: [AudioInputDevice] = []
        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &streamSize) == noErr else { continue }
            let bufferListMemory = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListMemory.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &streamSize, bufferListMemory) == noErr else { continue }
            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListMemory)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)

            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid)

            inputDevices.append(AudioInputDevice(
                id: deviceID,
                name: name as String,
                uid: uid as String
            ))
        }

        availableDevices = inputDevices

        // Update selected device or fall back to first available
        if let selected = selectedDevice {
            if !inputDevices.contains(where: { $0.id == selected.id }) {
                // Selected device was disconnected -- auto-fallback
                handleDisconnect(disconnectedName: selected.name)
            }
        } else {
            selectedDevice = inputDevices.first
        }
        currentDeviceName = selectedDevice?.name ?? "Default"
    }

    // MARK: - Device Selection

    func selectDevice(_ device: AudioInputDevice) {
        selectedDevice = device
        currentDeviceName = device.name
    }

    // MARK: - Disconnect Handling

    private func handleDisconnect(disconnectedName: String) {
        selectedDevice = availableDevices.first
        currentDeviceName = selectedDevice?.name ?? "Default"
        if let fallback = selectedDevice {
            disconnectMessage = "Switched to \(fallback.name)"
        }
        // Clear the message after 3 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            disconnectMessage = nil
        }
    }

    // MARK: - Device Change Watching

    private func watchForChanges() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
        _listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }

    deinit {
        // Remove listener on deallocation
        if let block = _listenerBlock {
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                DispatchQueue.main,
                block
            )
        }
    }
}
#endif
