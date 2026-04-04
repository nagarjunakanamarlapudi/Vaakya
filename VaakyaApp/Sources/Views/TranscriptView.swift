import SwiftUI

// TranscriptSegment is defined in TranscriptionService.swift

struct TranscriptView: View {
    let transcript: String
    let meetingId: String
    let blocks: [BlockData]
    var diarizationSpeakers: [Speaker] = []
    @State private var segments: [TranscriptSegment] = []
    @State private var selectedSegmentId: String?
    @State private var audioPlayer = AudioPlayer()
    @State private var selectedSpeaker: String? = nil

    private var uniqueSpeakers: [String] {
        Array(Set(segments.compactMap(\.speaker))).sorted()
    }

    private var visibleSegments: [TranscriptSegment] {
        guard let speaker = selectedSpeaker else { return segments }
        return segments.filter { $0.speaker == speaker }
    }

    /// Fallback palette when diarization speakers are not available.
    private let fallbackSpeakerColors: [Color] = [
        Color.accent,
        DesignTokens.BlockColor.summary,
        DesignTokens.BlockColor.decision,
        DesignTokens.BlockColor.action,
        Color(red: 0.85, green: 0.65, blue: 0.3),
        Color(red: 0.7, green: 0.5, blue: 0.9),
        Color(red: 0.0, green: 0.74, blue: 0.83),
        Color(red: 0.47, green: 0.33, blue: 0.28),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "text.quote")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accent)
                Text("Transcript")
                    .font(DesignTokens.Typography.sectionHead)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space3)

            Divider().opacity(0.5)

            // Audio Player
            VStack(spacing: DesignTokens.Spacing.space2) {
                HStack(spacing: DesignTokens.Spacing.space3) {
                    Button(action: { audioPlayer.toggle() }) {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(audioPlayer.duration > 0 ? Color.textPrimary : Color.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.bgCard)
                                    .shadow(color: DesignTokens.Shadow.cardColor, radius: 2, y: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(audioPlayer.duration == 0)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.bgCard)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accent)
                                .frame(width: geo.size.width * audioPlayer.progress, height: 4)
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let fraction = location.x / geo.size.width
                            audioPlayer.seek(to: max(0, min(1, fraction)))
                        }
                    }
                    .frame(height: 32)

                    Text(audioPlayer.duration > 0
                         ? "\(audioPlayer.formattedCurrentTime) / \(audioPlayer.formattedDuration)"
                         : "No audio")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                }

                // Speed controls
                HStack(spacing: DesignTokens.Spacing.space2) {
                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { speed in
                        Button(action: { audioPlayer.setSpeed(Float(speed)) }) {
                            Text(speed == 1.0 ? "1\u{00D7}" : String(format: "%.1f\u{00D7}", speed))
                                .font(.system(size: 10, weight: audioPlayer.playbackSpeed == Float(speed) ? .bold : .regular))
                                .foregroundStyle(audioPlayer.playbackSpeed == Float(speed) ? Color.accent : Color.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space3)

            Divider().opacity(0.5)

            // Speaker filter pills
            if !uniqueSpeakers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignTokens.Spacing.space2) {
                        speakerPill(label: "All (\(segments.count))", speaker: nil)
                        ForEach(uniqueSpeakers, id: \.self) { speaker in
                            let count = segments.filter { $0.speaker == speaker }.count
                            speakerPill(label: "\(speaker) (\(count))", speaker: speaker)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.space3)
                    .padding(.vertical, DesignTokens.Spacing.space2)
                }

                Divider().opacity(0.5)
            }

            // Segments
            if segments.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "waveform",
                    title: "No transcript yet",
                    subtitle: "Start recording to generate a transcript"
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visibleSegments) { segment in
                            segmentRow(segment)
                        }
                    }
                    .padding(.vertical, DesignTokens.Spacing.space2)
                    .padding(.horizontal, DesignTokens.Spacing.space3)
                }
            }
        }
        #if os(macOS)
        .frame(width: 340)
        #endif
        .background(Color.bgSidebar)
        .onAppear {
            segments = parseTranscript(transcript)
            audioPlayer.loadForMeeting(meetingId: meetingId)
        }
        .onChange(of: transcript) { _, newValue in
            segments = parseTranscript(newValue)
        }
        .onChange(of: meetingId) { _, newId in
            audioPlayer.loadForMeeting(meetingId: newId)
        }
    }

    private func speakerPill(label: String, speaker: String?) -> some View {
        let isSelected = selectedSpeaker == speaker
        let pillColor: Color = {
            if let speaker = speaker {
                return colorForSpeaker(speaker)
            }
            return Color.accent
        }()
        return Button(action: { selectedSpeaker = speaker }) {
            HStack(spacing: 4) {
                if let speaker = speaker {
                    Circle()
                        .fill(colorForSpeaker(speaker))
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.white : Color.textSecondary)
            .padding(.horizontal, DesignTokens.Spacing.space3)
            .padding(.vertical, DesignTokens.Spacing.space1)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(isSelected ? pillColor : Color.bgCard)
            )
        }
        .buttonStyle(.plain)
    }

    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        let isSelected = selectedSegmentId == segment.id
        let tags = matchingBlockTypes(for: segment)

        return Button(action: {
            selectedSegmentId = isSelected ? nil : segment.id
            if audioPlayer.duration > 0 && segment.start > 0 {
                let fraction = segment.start / audioPlayer.duration
                audioPlayer.seek(to: min(1, fraction))
                if !audioPlayer.isPlaying { audioPlayer.play() }
            }
        }) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space1) {
                HStack(spacing: DesignTokens.Spacing.space2) {
                    // Colored speaker badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForSpeaker(segment.speaker ?? "Speaker"))
                            .frame(width: 6, height: 6)
                        Text(segment.speaker ?? "Speaker")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(colorForSpeaker(segment.speaker ?? "Speaker"))
                    }
                    .padding(.horizontal, DesignTokens.Spacing.space2)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(colorForSpeaker(segment.speaker ?? "Speaker").opacity(0.10))
                    )

                    Text(segment.startFormatted)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                }
                Text(segment.text)
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // Attribution tags
                if !tags.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.space1) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag.capitalized)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(colorForBlockType(tag))
                                .padding(.horizontal, DesignTokens.Spacing.space2)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                        .fill(colorForBlockType(tag).opacity(0.10))
                                )
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.space3)
            .padding(.vertical, DesignTokens.Spacing.space2)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(isSelected ? Color.accent.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    /// Find which block types reference this transcript segment's text
    private func matchingBlockTypes(for segment: TranscriptSegment) -> [String] {
        var types: Set<String> = []
        let segWords = Set(segment.text.lowercased().split(separator: " ").filter { $0.count > 3 })
        guard segWords.count >= 2 else { return [] }

        for block in blocks {
            let blockWords = Set(block.content.lowercased().split(separator: " ").filter { $0.count > 3 })
            let overlap = segWords.intersection(blockWords)
            if overlap.count >= min(3, segWords.count) {
                types.insert(block.type)
            }
        }
        return Array(types).sorted()
    }

    private func colorForBlockType(_ type: String) -> Color {
        switch type.lowercased() {
        case "summary":  return DesignTokens.BlockColor.summary
        case "decision": return DesignTokens.BlockColor.decision
        case "action":   return DesignTokens.BlockColor.action
        case "quote":    return DesignTokens.BlockColor.quote
        default:         return Color.textTertiary
        }
    }

    private func colorForSpeaker(_ speaker: String) -> Color {
        // Use diarization speaker color (hex) if available
        if let diarSpeaker = diarizationSpeakers.first(where: { $0.label == speaker }) {
            return Color(hex: diarSpeaker.color)
        }
        // Fall back to index-based palette
        let allSpeakers = Array(Set(segments.compactMap(\.speaker))).sorted()
        let index = allSpeakers.firstIndex(of: speaker) ?? 0
        return fallbackSpeakerColors[index % fallbackSpeakerColors.count]
    }

    /// Parse a plain-text transcript (from server or stored text) into TranscriptSegment objects.
    /// Format: "[M:SS] [Speaker Name] Text" or "[M:SS] Text"
    private func parseTranscript(_ text: String) -> [TranscriptSegment] {
        guard !text.isEmpty else { return [] }
        var result: [TranscriptSegment] = []
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            guard let bracketStart = trimmed.firstIndex(of: "["),
                  let bracketEnd = trimmed.firstIndex(of: "]"),
                  bracketStart == trimmed.startIndex else {
                // Continuation line — append to last segment
                if !result.isEmpty {
                    let last = result.removeLast()
                    result.append(TranscriptSegment(
                        start: last.start,
                        end: last.end,
                        text: last.text + " " + trimmed,
                        speaker: last.speaker
                    ))
                } else {
                    result.append(TranscriptSegment(start: 0, end: 0, text: trimmed, speaker: nil))
                }
                continue
            }

            let timestamp = String(trimmed[trimmed.index(after: bracketStart)..<bracketEnd])
            let seconds = Double(parseTimestamp(timestamp))
            let afterBracket = String(trimmed[trimmed.index(after: bracketEnd)...]).trimmingCharacters(in: .whitespaces)

            // Check for optional [Speaker] tag after timestamp
            var speaker: String? = nil
            var bodyText = afterBracket

            if afterBracket.hasPrefix("["),
               let speakerEnd = afterBracket.dropFirst().firstIndex(of: "]") {
                speaker = String(afterBracket[afterBracket.index(after: afterBracket.startIndex)..<speakerEnd])
                bodyText = String(afterBracket[afterBracket.index(after: speakerEnd)...]).trimmingCharacters(in: .whitespaces)
            } else if let colonIdx = afterBracket.firstIndex(of: ":") {
                // Legacy format: "Speaker Name: text"
                let beforeColon = String(afterBracket[afterBracket.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let afterColon = String(afterBracket[afterBracket.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                if beforeColon.count <= 30 && beforeColon.split(separator: " ").count <= 3 {
                    speaker = beforeColon
                    bodyText = afterColon
                }
            }

            result.append(TranscriptSegment(
                start: seconds,
                end: seconds,  // end unknown from plain text; set equal to start
                text: bodyText,
                speaker: speaker
            ))
        }
        return result
    }

    private func parseTimestamp(_ ts: String) -> Int {
        let parts = ts.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        return 0
    }
}
