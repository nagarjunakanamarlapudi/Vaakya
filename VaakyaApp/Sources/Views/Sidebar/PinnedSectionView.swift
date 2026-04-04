#if os(macOS)
import SwiftUI

struct PinnedSectionView: View {
    let meetings: [MeetingMetadata]  // already filtered to pinned + sorted
    let allMeetings: [MeetingMetadata]  // full list for drop destination lookup
    let selectedId: String?
    let onSelect: (MeetingMetadata) -> Void
    let contextMenu: (MeetingMetadata) -> AnyView
    var showProjectPill: Bool = false
    var projects: [ProjectFolder] = []

    private func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !LocalStore.shared.isSectionCollapsed(id) },
            set: { _ in LocalStore.shared.toggleSectionCollapsed(id) }
        )
    }

    var body: some View {
        if !meetings.isEmpty {
            SidebarSectionHeader(title: "Pinned", isExpanded: isExpanded("pinned"),
                count: meetings.count, icon: "star.fill", iconColor: Color.vaYellow)
            .dropDestination(for: String.self) { meetingIds, _ in
                for id in meetingIds {
                    if !(allMeetings.first(where: { $0.id == id })?.isPinned ?? true) {
                        LocalStore.shared.togglePin(meetingId: id)
                    }
                }
                return true
            }
            if !LocalStore.shared.isSectionCollapsed("pinned") {
                ForEach(meetings) { meeting in
                    let project = projects.first(where: { $0.id == meeting.project })
                    Button(action: { onSelect(meeting) }) {
                        SidebarMeetingRow(
                            meeting: meeting,
                            isSelected: selectedId == meeting.id,
                            showProjectPill: showProjectPill && meeting.project != nil,
                            projectColor: project.map { Color(hex: $0.color) },
                            projectName: project?.name,
                            isPinnedView: true
                        )
                    }
                    .buttonStyle(.plain)
                    .draggable(meeting.id)
                    .contextMenu { contextMenu(meeting) }
                }
                .onMove { source, destination in
                    var reordered = meetings
                    reordered.move(fromOffsets: source, toOffset: destination)
                    LocalStore.shared.setPinOrders(reordered.enumerated().map { ($1.id, $0) })
                }
            }
            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)
        }
    }
}
#endif
