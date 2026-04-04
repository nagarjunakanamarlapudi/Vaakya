#if os(macOS)
import SwiftUI

struct FloatingNotepad: View {
    let recorder: AudioRecorder
    let session: RecordingSession
    let onEndMeeting: () -> Void
    let onMinimize: () -> Void

    // Drive waveform updates
    @State private var animationTick: Date = Date()
    private let animationTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private let waveBarCount = 20

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Recording Status Bar (top)
            HStack(spacing: DesignTokens.Spacing.space3) {
                if recorder.isRecording {
                    HStack(spacing: DesignTokens.Spacing.space2) {
                        Circle().fill(Color.blockRed).frame(width: 8, height: 8)
                        Text(recorder.formattedDuration)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.blockRed)
                    }

                    // Mini waveform in status bar
                    HStack(spacing: 1.5) {
                        ForEach(0..<8, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.accent.opacity(0.6))
                                .frame(width: 2, height: statusWaveHeight(index: i))
                        }
                    }
                    .frame(height: 14)
                }

                Spacer()

                // Stop / End button
                Button(action: onEndMeeting) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.blockRed)
                }
                .buttonStyle(.plain)
                .help("End Meeting")

                // Minimize button
                Button(action: onMinimize) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(Color.bgCard)
                                .shadow(color: DesignTokens.Shadow.cardColor, radius: 1, y: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Minimize to pill (Cmd+Shift+V)")
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space3)

            Divider().opacity(0.3)

            // MARK: - Waveform visualization
            if recorder.isRecording {
                HStack(spacing: 2) {
                    ForEach(0..<waveBarCount, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.accent.opacity(0.6))
                            .frame(width: 3, height: waveHeight(index: i))
                    }
                }
                .frame(height: 24)
                .padding(.vertical, DesignTokens.Spacing.space2)
            }

            // MARK: - Notes Editor
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                Text("Quick Notes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)

                TextEditor(text: Binding(
                    get: { session.notes },
                    set: { session.notes = $0 }
                ))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.bgCard.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space3)

            Spacer(minLength: 0)

            // MARK: - Resize handle (bottom-right)
            HStack {
                Spacer()
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary.opacity(0.5))
                    .padding(.trailing, 6)
                    .padding(.bottom, 4)
            }
        }
        .frame(width: 400, height: 300)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .fill(.ultraThinMaterial)
                .shadow(
                    color: DesignTokens.Shadow.elevatedColor,
                    radius: DesignTokens.Shadow.elevatedRadius,
                    y: DesignTokens.Shadow.elevatedY
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .onReceive(animationTimer) { tick in
            animationTick = tick
        }
    }

    // MARK: - Wave Heights

    private func waveHeight(index: Int) -> CGFloat {
        let base: CGFloat = 3
        let maxH: CGFloat = 20
        let amp = CGFloat(recorder.currentAmplitude)
        let wave = sin(Double(index) * 0.5 + animationTick.timeIntervalSince1970 * 4)
        return max(base, base + (maxH - base) * amp * CGFloat(max(0.2, (wave + 1) / 2)))
    }

    private func statusWaveHeight(index: Int) -> CGFloat {
        let base: CGFloat = 2
        let maxH: CGFloat = 12
        let amp = CGFloat(recorder.currentAmplitude)
        let wave = sin(Double(index) * 0.8 + animationTick.timeIntervalSince1970 * 3)
        return max(base, base + (maxH - base) * amp * CGFloat(max(0.2, (wave + 1) / 2)))
    }
}
#endif
