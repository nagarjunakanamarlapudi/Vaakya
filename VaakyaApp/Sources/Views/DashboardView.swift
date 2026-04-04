import SwiftUI

struct DashboardView: View {
    @Environment(MeetingViewModel.self) private var meetingVM

    let recorder: AudioRecorder

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:       return "Good evening"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space6) {
                // Greeting
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.space1) {
                    Text(greeting)
                        .font(DesignTokens.Typography.pageTitle)
                        .foregroundStyle(Color.textPrimary)

                    Text("Here's your meeting overview")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.top, DesignTokens.Spacing.space4)

                // Stats bar
                statsBar

                // Quick Start
                quickStartSection

                // Recently Enhanced
                recentlyEnhancedSection
            }
            .padding(.horizontal, DesignTokens.Spacing.space6)
            .padding(.vertical, DesignTokens.Spacing.space4)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .background(Color.bgContent)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: DesignTokens.Spacing.space4) {
            statCard(
                icon: "calendar",
                value: "\(meetingVM.meetingsThisWeek)",
                label: "This week"
            )

            statCard(
                icon: "clock",
                value: formattedTotalHours,
                label: "Total captured"
            )

            statCard(
                icon: "checkmark.square",
                value: "\(meetingVM.pendingActionItemCount)",
                label: "Action items"
            )

            statCard(
                icon: "sparkles",
                value: "\(meetingVM.aiEnhancedMeetingCount)",
                label: "AI enhanced"
            )
        }
    }

    private var formattedTotalHours: String {
        let hours = Double(meetingVM.totalCapturedSeconds) / 3600.0
        if hours < 0.1 && meetingVM.totalCapturedSeconds > 0 {
            return String(format: "%.1fh", hours)
        }
        return hours >= 10 ? String(format: "%.0fh", hours) : String(format: "%.1fh", hours)
    }

    private func statCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.space2) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accent)

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            Text(label)
                .font(DesignTokens.Typography.label)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.space4)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bgCard)
                .shadow(color: DesignTokens.Shadow.cardColor, radius: DesignTokens.Shadow.cardRadius, y: DesignTokens.Shadow.cardY)
        )
    }

    // MARK: - Quick Start

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space3) {
            Text("Quick Start")
                .font(DesignTokens.Typography.sectionHead)
                .foregroundStyle(Color.textPrimary)

            HStack(spacing: DesignTokens.Spacing.space4) {
                quickStartCard(icon: "mic.fill", label: "Record meeting", color: Color.blockRed) {
                    meetingVM.showCreateSheet = true
                }

                quickStartCard(icon: "magnifyingglass", label: "Search notes", color: Color.accent) {
                    // Placeholder for search
                }

                quickStartCard(icon: "checkmark.square", label: "Action items", color: DesignTokens.BlockColor.action) {
                    // Placeholder for action items view
                }
            }
        }
    }

    private func quickStartCard(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DesignTokens.Spacing.space2) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)

                Text(label)
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.space4)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.bgCard)
                    .shadow(color: DesignTokens.Shadow.cardColor, radius: DesignTokens.Shadow.cardRadius, y: DesignTokens.Shadow.cardY)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recently Enhanced

    private var recentlyEnhancedSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space3) {
            Text("Recently Enhanced")
                .font(DesignTokens.Typography.sectionHead)
                .foregroundStyle(Color.textPrimary)

            let enhanced = meetingVM.recentlyEnhancedMeetings()
            if enhanced.isEmpty {
                VStack(spacing: DesignTokens.Spacing.space2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.textTertiary)
                    Text("No enhanced meetings yet")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text("Record a meeting and tap Enhance to generate AI notes")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.space8)
            } else {
                VStack(spacing: DesignTokens.Spacing.space2) {
                    ForEach(enhanced) { meeting in
                        enhancedMeetingRow(meeting)
                    }
                }
            }
        }
    }

    private func enhancedMeetingRow(_ meeting: MeetingMetadata) -> some View {
        Button(action: {
            meetingVM.selectMeeting(meeting)
        }) {
            HStack(spacing: DesignTokens.Spacing.space3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: DesignTokens.Spacing.space2) {
                        Text(meeting.formattedDate)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)

                        if let duration = meeting.durationSeconds, duration > 0 {
                            Text(meeting.durationFormatted)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }

                Spacer()

                if let source = meeting.source, !source.isEmpty {
                    MeetingSourceTag(source: source)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space3)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.bgCard)
                    .shadow(color: DesignTokens.Shadow.cardColor, radius: DesignTokens.Shadow.cardRadius, y: DesignTokens.Shadow.cardY)
            )
        }
        .buttonStyle(.plain)
    }
}

