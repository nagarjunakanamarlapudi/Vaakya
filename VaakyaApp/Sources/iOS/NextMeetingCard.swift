#if os(iOS)
import EventKit
import SwiftUI

/// Card showing the next calendar event with a tap-to-record action.
/// Displayed at the top of the iOS meetings list.
struct NextMeetingCard: View {
    let event: EKEvent
    let onStartRecording: () -> Void

    var body: some View {
        Button(action: onStartRecording) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                HStack(spacing: DesignTokens.Spacing.space2) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accent)
                    Text("Next Meeting")
                        .font(DesignTokens.Typography.label)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(formattedTime)
                        .font(DesignTokens.Typography.label)
                        .foregroundStyle(Color.textTertiary)
                }

                Text(event.title ?? "Untitled")
                    .font(DesignTokens.Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DesignTokens.Spacing.space3) {
                    if let attendees = event.attendees, !attendees.isEmpty {
                        HStack(spacing: DesignTokens.Spacing.space1) {
                            Image(systemName: "person.2")
                                .font(.system(size: 10))
                            Text("\(attendees.count) participant\(attendees.count == 1 ? "" : "s")")
                                .font(DesignTokens.Typography.label)
                        }
                        .foregroundStyle(Color.textTertiary)
                    }

                    Spacer()

                    HStack(spacing: DesignTokens.Spacing.space1) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 10))
                        Text("Tap to start recording")
                            .font(DesignTokens.Typography.label)
                    }
                    .foregroundStyle(Color.accent)
                }
            }
            .padding(DesignTokens.Spacing.space4)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.bgCard)
                    .shadow(color: DesignTokens.Shadow.cardColor,
                            radius: DesignTokens.Shadow.cardRadius,
                            y: DesignTokens.Shadow.cardY)
            )
        }
        .buttonStyle(.plain)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: event.startDate)
    }
}
#endif
