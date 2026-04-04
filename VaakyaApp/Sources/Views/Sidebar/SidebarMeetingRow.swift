#if os(macOS)
import SwiftUI

struct SidebarMeetingRow: View {
    let meeting: MeetingMetadata
    let isSelected: Bool
    var showProjectPill: Bool = false
    var projectColor: Color? = nil
    var projectName: String? = nil
    var isPinnedView: Bool = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.space3) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space1) {
                HStack(spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if meeting.isEnhanced {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.vaGreen)
                    }
                    if meeting.pendingActionItems > 0 {
                        HStack(spacing: 1) {
                            Text("\(meeting.pendingActionItems)")
                                .font(.system(size: 9, weight: .semibold))
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 7))
                        }
                        .foregroundStyle(Color.vaRed)
                    }
                    if meeting.hasAudio {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                HStack(spacing: DesignTokens.Spacing.space2) {
                    Text(meeting.formattedDate)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    if meeting.speakerCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "person.2").font(.system(size: 9))
                            Text("\(meeting.speakerCount)").font(.system(size: 11))
                        }
                        .foregroundStyle(Color.textTertiary)
                    }
                    if let source = meeting.source, !source.isEmpty {
                        MeetingSourceTag(source: source)
                    }
                    if showProjectPill, let name = projectName, let color = projectColor {
                        Text(name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.12)))
                    }
                }
                // Tags row
                if !meeting.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(meeting.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.textTertiary.opacity(0.12))
                                )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.space4)
        .padding(.vertical, DesignTokens.Spacing.space2 + 2)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(isSelected ? Color.accent.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            if isPinnedView {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.vaGreen)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
    }
}
#endif
