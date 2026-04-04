#if os(iOS)
import SwiftUI
import UIKit

/// Recording UI adapted for iPhone -- shows recording indicator, timer,
/// waveform, current audio device, and a stop button with haptic feedback.
struct iOSRecordingView: View {
    let recorder: AudioRecorder
    let meetingTitle: String
    let deviceName: String
    let onStop: () -> Void

    @State private var animationTick: Date = Date()
    private let animationTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.space6) {
            Spacer()

            // Recording indicator
            VStack(spacing: DesignTokens.Spacing.space3) {
                Circle()
                    .fill(Color.blockRed)
                    .frame(width: 16, height: 16)
                    .shadow(color: Color.blockRed.opacity(0.5), radius: 8)

                Text("Recording")
                    .font(DesignTokens.Typography.sectionHead)
                    .foregroundStyle(Color.blockRed)
            }

            // Meeting title
            Text(meetingTitle)
                .font(DesignTokens.Typography.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Timer
            Text(recorder.formattedDuration)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(Color.textPrimary)

            // Waveform
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accent.opacity(0.7))
                        .frame(width: 4, height: waveHeight(index: i))
                }
            }
            .frame(height: 40)

            // Current audio device
            HStack(spacing: DesignTokens.Spacing.space2) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                Text(deviceName)
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            // Stop button
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                onStop()
            }) {
                HStack(spacing: DesignTokens.Spacing.space2) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 20))
                    Text("Stop Recording")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.space4)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(Color.blockRed)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.space6)
            .padding(.bottom, DesignTokens.Spacing.space8)
        }
        .background(Color.bgApp)
        .onReceive(animationTimer) { tick in
            animationTick = tick
        }
    }

    private func waveHeight(index: Int) -> CGFloat {
        let base: CGFloat = 4
        let maxH: CGFloat = 36
        let amp = CGFloat(recorder.currentAmplitude)
        let wave = sin(Double(index) * 0.5 + animationTick.timeIntervalSince1970 * 4)
        return max(base, base + (maxH - base) * amp * CGFloat(max(0.2, (wave + 1) / 2)))
    }
}
#endif
