#if os(macOS)
import SwiftUI

struct NotchPresentation: Equatable {
    enum Mode: Equatable {
        case hidden               // not recording, no UI (window mouse-passthrough)
        case summonedIdle         // not recording, faintly visible for drag positioning (non-notch)
        case expandedRecording    // expanded with red dot + duration + waveform
        case expandedStop         // recording just ended, greyed dot + final time
    }
    var mode: Mode
    var duration: TimeInterval
    var amplitude: Float
    var isFloating: Bool   // non-notch: enables drag interactions
    var isRecording: Bool  // drives the persistent under-notch bar
}

struct NotchIndicatorView: View {
    let presentation: NotchPresentation
    let onHoverChange: (Bool) -> Void
    let onClick: () -> Void
    let onDragDelta: (CGSize) -> Void
    let onDragEnded: () -> Void

    @State private var dragAccumulated: CGFloat = 0

    var body: some View {
        VStack(spacing: 1) {
            pill
            recordingBar
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    /// Persistent thin red bar shown just below the notch while recording — gives an at-a-glance
    /// "still recording" signal between heartbeats, when the pill itself is hidden behind the bezel.
    @ViewBuilder
    private var recordingBar: some View {
        if presentation.isRecording {
            Capsule(style: .continuous)
                .fill(Color(red: 1.0, green: 0.23, blue: 0.19))
                .frame(width: 44, height: 3)
                .shadow(color: Color(red: 1.0, green: 0.23, blue: 0.19).opacity(0.75), radius: 4)
                .opacity(isExpanded ? 0 : 1)         // the pill itself reads as "active" when expanded
                .modifier(PulseModifier(active: true))
                .animation(.easeInOut(duration: 0.22), value: isExpanded)
        }
    }

    private var pill: some View {
        // Horizontal layout — pill stays at notch height; content lives on either side of the notch.
        HStack(spacing: 0) {
            leftContent
                .frame(width: NotchGeometry.sideExtensionWidth, alignment: .trailing)
                .opacity(isExpanded ? 1 : 0)

            // Center spacer matches notch width — visually behind the bezel.
            Color.clear.frame(width: NotchGeometry.virtualNotchWidth)

            rightContent
                .frame(width: NotchGeometry.sideExtensionWidth, alignment: .leading)
                .opacity(isExpanded ? 1 : 0)
        }
        .frame(width: width, height: NotchGeometry.pillHeight)
        .background(pillShape)
        .opacity(opacity)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: presentation.mode)
        .animation(.easeOut(duration: 0.18), value: isExpanded)
        .onHover { hovering in onHoverChange(hovering) }
        .gesture(dragGesture)
    }

    private var pillShape: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: NotchGeometry.pillHeight / 2,
            bottomTrailingRadius: NotchGeometry.pillHeight / 2,
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(Color.black)
    }

    private var leftContent: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(presentation.mode == .expandedStop
                      ? Color(white: 0.4)
                      : Color(red: 1.0, green: 0.23, blue: 0.19))
                .frame(width: 9, height: 9)
                .shadow(
                    color: presentation.mode == .expandedStop
                        ? .clear
                        : Color(red: 1.0, green: 0.23, blue: 0.19).opacity(0.65),
                    radius: 4
                )
                .modifier(PulseModifier(active: presentation.mode == .expandedRecording))

            Text(formattedDuration(presentation.duration))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.trailing, 10)
    }

    private var rightContent: some View {
        NotchWaveformView(
            amplitude: presentation.mode == .expandedRecording ? presentation.amplitude : Float(0)
        )
        .padding(.leading, 10)
    }

    // MARK: - Derived layout

    private var isExpanded: Bool {
        presentation.mode == .expandedRecording || presentation.mode == .expandedStop
    }

    private var width: CGFloat {
        isExpanded ? NotchGeometry.expandedWidth : NotchGeometry.virtualNotchWidth
    }

    private var opacity: Double {
        switch presentation.mode {
        case .hidden:
            // On notched Macs the black pill at notch width is the notch — keep it opaque
            // so the merge with the bezel reads clean. On non-notch Macs we want it invisible.
            return presentation.isFloating ? 0 : 1
        case .summonedIdle:
            return 0.55
        case .expandedRecording, .expandedStop:
            return 1
        }
    }

    // MARK: - Drag / click

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let distance = (dx * dx + dy * dy).squareRoot()
                dragAccumulated = max(dragAccumulated, distance)
                if presentation.isFloating && dragAccumulated >= 4 {
                    onDragDelta(value.translation)
                }
            }
            .onEnded { _ in
                defer { dragAccumulated = 0 }
                if dragAccumulated < 4 {
                    if presentation.mode == .expandedRecording { onClick() }
                } else if presentation.isFloating {
                    onDragEnded()
                }
            }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let total = Int(max(0, duration))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && pulsing ? 0.82 : 1.0)
            .opacity(active && pulsing ? 0.75 : 1.0)
            .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { if active { pulsing = true } }
            .onChange(of: active) { _, newValue in pulsing = newValue }
    }
}
#endif
