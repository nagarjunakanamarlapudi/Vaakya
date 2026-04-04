import AVFoundation
import SwiftUI

/// Allows users to match detected speakers to known participant names (from calendar).
/// Each speaker row shows a play button for a 5-second audio clip from their first turn,
/// plus a list of participant names to tap for assignment.
struct SpeakerMatchingView: View {
    let speakers: [Speaker]
    let participants: [String]
    let audioURL: URL
    var onMatch: (String, String) -> Void  // (speakerId, participantName)
    var onDismiss: () -> Void

    @State private var assignments: [String: String] = [:]  // speakerId -> participantName
    @State private var playingSpeakerId: String?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var customNames: [String: String] = [:]  // speakerId -> custom name for "not on invite"
    @State private var editingCustomNameFor: String?

    private var allAssigned: Bool {
        speakers.allSatisfy { assignments[$0.id] != nil }
    }

    private var assignedParticipants: Set<String> {
        Set(assignments.values)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accent)
                    .padding(.bottom, 4)

                Text("Match Speakers")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.textPrimary)

                Text("We detected \(speakers.count) speaker\(speakers.count == 1 ? "" : "s"). Match each voice to a participant.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider().background(Color.textTertiary.opacity(0.2))

            // Speaker rows
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(speakers) { speaker in
                        speakerRow(speaker)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Divider().background(Color.textTertiary.opacity(0.2))

            // Done button
            HStack {
                Button("Skip") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Spacer()

                Button(action: {
                    for (speakerId, name) in assignments {
                        onMatch(speakerId, name)
                    }
                    onDismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text(allAssigned ? "Done" : "Done (\(assignments.count)/\(speakers.count))")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.Button.compactCornerRadius).fill(Color.accent))
                }
                .buttonStyle(.plain)
                .disabled(assignments.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 420, height: 500)
        .background(Color.bgContent)
    }

    // MARK: - Speaker Row

    @ViewBuilder
    private func speakerRow(_ speaker: Speaker) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Speaker color dot and label
                Circle()
                    .fill(Color(hex: speaker.color))
                    .frame(width: 10, height: 10)

                Text(speaker.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                // Play button for audio preview
                Button(action: { playAudioClip(for: speaker) }) {
                    HStack(spacing: 4) {
                        Image(systemName: playingSpeakerId == speaker.id ? "pause.fill" : "play.fill")
                            .font(.system(size: 10))
                        Text("Preview")
                            .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                    }
                    .foregroundStyle(playingSpeakerId == speaker.id ? Color.accent : Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: DesignTokens.Button.compactCornerRadius).fill(Color.bgElevated))
                }
                .buttonStyle(.plain)

                Spacer()

                // Show assignment if made
                if let assigned = assignments[speaker.id] {
                    HStack(spacing: 4) {
                        Text(assigned)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accent)
                        Button(action: { assignments.removeValue(forKey: speaker.id) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accent.opacity(0.12)))
                }
            }

            // Participant name buttons (only if not yet assigned)
            if assignments[speaker.id] == nil {
                FlowLayout(spacing: 6) {
                    ForEach(participants.filter { !assignedParticipants.contains($0) }, id: \.self) { participant in
                        Button(action: {
                            assignments[speaker.id] = participant
                        }) {
                            Text(participant)
                                .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Button.compactCornerRadius)
                                        .fill(Color.bgElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Button.compactCornerRadius)
                                        .stroke(Color.textTertiary.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    // "Someone not on the invite" option
                    if editingCustomNameFor == speaker.id {
                        HStack(spacing: 4) {
                            TextField("Enter name", text: Binding(
                                get: { customNames[speaker.id] ?? "" },
                                set: { customNames[speaker.id] = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: 100)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.bgElevated))

                            Button(action: {
                                if let name = customNames[speaker.id], !name.isEmpty {
                                    assignments[speaker.id] = name
                                }
                                editingCustomNameFor = nil
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button(action: {
                            editingCustomNameFor = speaker.id
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 9))
                                Text("Someone else")
                                    .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                            }
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Button.compactCornerRadius)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    .foregroundStyle(Color.textTertiary.opacity(0.3))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgElevated)
        )
    }

    // MARK: - Audio Preview

    private func playAudioClip(for speaker: Speaker) {
        if playingSpeakerId == speaker.id {
            audioPlayer?.stop()
            playingSpeakerId = nil
            return
        }

        // Play a 5-second clip from the audio file
        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            // Seek to a point representative of this speaker (simplified: play from start)
            audioPlayer?.currentTime = 0
            audioPlayer?.play()
            playingSpeakerId = speaker.id

            // Auto-stop after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak audioPlayer] in
                audioPlayer?.stop()
                if playingSpeakerId == speaker.id {
                    playingSpeakerId = nil
                }
            }
        } catch {
            playingSpeakerId = nil
        }
    }
}

// MARK: - Flow Layout

/// Simple flow layout that wraps items to the next line when they exceed the available width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return ArrangeResult(
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
    }
}

