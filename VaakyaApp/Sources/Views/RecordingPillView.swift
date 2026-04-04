#if os(macOS)
import SwiftUI

struct RecordingPillView: View {
    let recorder: AudioRecorder
    let session: RecordingSession
    let onExpand: () -> Void

    // Pulsing animation for the recording dot
    @State private var isPulsing = false

    // Drive continuous updates for waveform animation
    @State private var animationTick: Date = Date()
    private let animationTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private let barCount = 5

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.space2) {
            // 1. Red pulsing recording dot
            Circle()
                .fill(Color.blockRed)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.6 : 1.0)
                .animation(
                    .easeInOut(duration: 1).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            // 2. Timer (MM:SS)
            Text(recorder.formattedDuration)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textPrimary)

            // 3. Audio waveform bars
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accent.opacity(0.7))
                        .frame(width: 3, height: waveHeight(index: i))
                }
            }
            .frame(height: 16)

            // 4. Current speaker name (if diarization is running)
            if !session.currentSpeakerName.isEmpty {
                Text(session.currentSpeakerName)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.space4)
        .padding(.vertical, DesignTokens.Spacing.space2)
        .frame(width: 220, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(
                    color: DesignTokens.Shadow.elevatedColor,
                    radius: DesignTokens.Shadow.elevatedRadius,
                    y: DesignTokens.Shadow.elevatedY
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
        .onTapGesture { onExpand() }
        .onAppear { isPulsing = true }
        .onReceive(animationTimer) { tick in
            animationTick = tick
        }
    }

    // MARK: - Waveform Height

    private func waveHeight(index: Int) -> CGFloat {
        let base: CGFloat = 3
        let maxH: CGFloat = 14
        let amp = CGFloat(recorder.currentAmplitude)
        let wave = sin(Double(index) * 0.7 + animationTick.timeIntervalSince1970 * 3)
        return max(base, base + (maxH - base) * amp * CGFloat(max(0.2, (wave + 1) / 2)))
    }
}
#endif
