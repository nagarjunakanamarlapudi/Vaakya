import SwiftUI

/// Shows live transcript segments during active streaming transcription.
/// Confirmed segments appear in normal style; unconfirmed segments appear dimmed/italic.
/// Auto-scrolls to the bottom as new segments arrive.
struct LiveTranscriptView: View {
    let transcriptionService: TranscriptionService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.blockRed)
                    .symbolEffect(.pulse)
                Text("Live Transcript")
                    .font(DesignTokens.Typography.sectionHead)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.blockRed).frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.blockRed)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(Color.blockRed.opacity(0.08))
                )
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space3)

            Divider().opacity(0.5)

            // Segments list
            if transcriptionService.segments.isEmpty && transcriptionService.currentStreamingText.isEmpty {
                Spacer()
                VStack(spacing: DesignTokens.Spacing.space2) {
                    ProgressView()
                        .tint(Color.accent)
                    Text("Listening...")
                        .font(DesignTokens.Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Text("Speak to see your transcript appear here")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(transcriptionService.segments) { segment in
                                liveSegmentRow(segment)
                            }

                            // Show current in-progress text at the bottom
                            if !transcriptionService.currentStreamingText.isEmpty
                                && transcriptionService.currentStreamingText != "Waiting for speech..." {
                                currentTextRow(transcriptionService.currentStreamingText)
                                    .id("currentText")
                            }

                            // Invisible anchor for auto-scroll
                            Color.clear.frame(height: 1).id("bottomAnchor")
                        }
                        .padding(.vertical, DesignTokens.Spacing.space2)
                        .padding(.horizontal, DesignTokens.Spacing.space3)
                    }
                    .onChange(of: transcriptionService.segments.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottomAnchor", anchor: .bottom)
                        }
                    }
                    .onChange(of: transcriptionService.currentStreamingText) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottomAnchor", anchor: .bottom)
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 340)
        #endif
        .background(Color.bgSidebar)
    }

    // MARK: - Segment Rows

    private let speakerColors: [String: Color] = [
        "You": Color.accent,
        "Remote": Color.vaBlue,
    ]

    private func colorForSpeaker(_ speaker: String?) -> Color {
        guard let s = speaker else { return Color.textTertiary }
        return speakerColors[s] ?? Color.vaYellow
    }

    @ViewBuilder
    private func liveSegmentRow(_ segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space1) {
            HStack(spacing: DesignTokens.Spacing.space2) {
                if let speaker = segment.speaker {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForSpeaker(speaker))
                            .frame(width: 6, height: 6)
                        Text(speaker)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(colorForSpeaker(speaker))
                    }
                }

                Text(segment.startFormatted)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)

                if !segment.isConfirmed {
                    Text("processing")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(Color.textTertiary.opacity(0.10))
                        )
                }
            }

            Text(segment.text)
                .font(DesignTokens.Typography.label)
                .foregroundStyle(segment.isConfirmed ? Color.textPrimary : Color.textTertiary)
                .italic(!segment.isConfirmed)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.space3)
        .padding(.vertical, DesignTokens.Spacing.space2)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(segment.isConfirmed ? Color.clear : Color.bgCard.opacity(0.5))
        )
    }

    @ViewBuilder
    private func currentTextRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.space2) {
            Circle()
                .fill(Color.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            Text(text)
                .font(DesignTokens.Typography.label)
                .foregroundStyle(Color.accent.opacity(0.7))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.space3)
        .padding(.vertical, DesignTokens.Spacing.space2)
    }
}
