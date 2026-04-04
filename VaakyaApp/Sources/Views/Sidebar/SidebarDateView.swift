#if os(macOS)
import SwiftUI

struct SidebarDateView: View {
    let meetings: [MeetingMetadata]
    let projects: [ProjectFolder]
    let selectedId: String?
    let onSelect: (MeetingMetadata) -> Void
    let contextMenu: (MeetingMetadata) -> AnyView

    private struct DateGroups {
        var pinned: [MeetingMetadata] = []
        var today: [MeetingMetadata] = []
        var yesterday: [MeetingMetadata] = []
        var thisWeek: [MeetingMetadata] = []
        var earlier: [MeetingMetadata] = []
    }

    private func groupMeetings() -> DateGroups {
        var groups = DateGroups()
        let cal = Calendar.current
        for meeting in meetings {
            if meeting.isPinned {
                groups.pinned.append(meeting)
            } else if cal.isDateInToday(meeting.startedAt) {
                groups.today.append(meeting)
            } else if cal.isDateInYesterday(meeting.startedAt) {
                groups.yesterday.append(meeting)
            } else if cal.isDate(meeting.startedAt, equalTo: Date(), toGranularity: .weekOfYear) {
                groups.thisWeek.append(meeting)
            } else {
                groups.earlier.append(meeting)
            }
        }
        groups.pinned.sort { ($0.pinSortOrder ?? 0) < ($1.pinSortOrder ?? 0) }
        return groups
    }

    var body: some View {
        let groups = groupMeetings()
        LazyVStack(spacing: 0) {
            PinnedSectionView(
                meetings: groups.pinned,
                allMeetings: meetings,
                selectedId: selectedId,
                onSelect: onSelect,
                contextMenu: contextMenu,
                showProjectPill: true,
                projects: projects
            )
            section("today", label: "Today", meetings: groups.today)
            section("yesterday", label: "Yesterday", meetings: groups.yesterday)
            section("thisweek", label: "This Week", meetings: groups.thisWeek)
            section("earlier", label: "Earlier", meetings: groups.earlier)
        }
        .padding(.vertical, DesignTokens.Spacing.space2)
    }

    @ViewBuilder
    private func section(_ id: String, label: String, meetings: [MeetingMetadata]) -> some View {
        if !meetings.isEmpty {
            SidebarSectionHeader(title: label, isExpanded: LocalStore.shared.sectionBinding(id), count: meetings.count)
            if !LocalStore.shared.isSectionCollapsed(id) {
                ForEach(meetings) { meeting in
                    meetingButton(meeting, isPinnedSection: false)
                }
            }
        }
    }

    private func meetingButton(_ meeting: MeetingMetadata, isPinnedSection: Bool) -> some View {
        let project = projects.first(where: { $0.id == meeting.project })
        return Button(action: { onSelect(meeting) }) {
            SidebarMeetingRow(
                meeting: meeting,
                isSelected: selectedId == meeting.id,
                showProjectPill: !isPinnedSection && meeting.project != nil,
                projectColor: project.map { Color(hex: $0.color) },
                projectName: project?.name,
                isPinnedView: isPinnedSection
            )
        }
        .buttonStyle(.plain)
        .draggable(meeting.id)
        .contextMenu { contextMenu(meeting) }
    }
}
#endif
