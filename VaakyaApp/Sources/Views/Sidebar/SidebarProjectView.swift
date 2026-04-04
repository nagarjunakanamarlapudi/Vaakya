#if os(macOS)
import SwiftUI

struct SidebarProjectView: View {
    let meetings: [MeetingMetadata]
    let projects: [ProjectFolder]
    let selectedId: String?
    let onSelect: (MeetingMetadata) -> Void
    let onAssignProject: (String, String?) -> Void
    let contextMenu: (MeetingMetadata) -> AnyView

    @State private var editingProject: ProjectFolder? = nil
    @State private var showCreateProject = false
    @State private var dragTargetProjectId: String? = nil

    private var pinned: [MeetingMetadata] {
        meetings.filter(\.isPinned).sorted { ($0.pinSortOrder ?? 0) < ($1.pinSortOrder ?? 0) }
    }

    private func meetingsFor(projectId: String) -> [MeetingMetadata] {
        meetings.filter { !$0.isPinned && $0.project == projectId }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var unlabeled: [MeetingMetadata] {
        meetings.filter { !$0.isPinned && $0.project == nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            PinnedSectionView(
                meetings: pinned,
                allMeetings: meetings,
                selectedId: selectedId,
                onSelect: onSelect,
                contextMenu: contextMenu
            )

            // Project folders
            ForEach(projects.sorted(by: { $0.sortOrder < $1.sortOrder })) { project in
                let folderMeetings = meetingsFor(projectId: project.id)
                let sectionId = "project_\(project.id)"
                let isExp = !LocalStore.shared.isSectionCollapsed(sectionId)
                let projectColor = Color(hex: project.color)

                accentSection(color: projectColor, showBar: isExp) {
                    SidebarSectionHeader(
                        title: project.name, isExpanded: LocalStore.shared.sectionBinding(sectionId),
                        count: folderMeetings.count,
                        icon: "folder.fill", iconColor: projectColor,
                        isFolderStyle: true
                    )
                    .dropDestination(for: String.self) { meetingIds, _ in
                        for id in meetingIds { onAssignProject(id, project.id) }
                        return true
                    } isTargeted: { targeted in
                        dragTargetProjectId = targeted ? project.id : nil
                        if targeted && LocalStore.shared.isSectionCollapsed(sectionId) {
                            LocalStore.shared.toggleSectionCollapsed(sectionId)
                        }
                    }
                    .background(
                        dragTargetProjectId == project.id
                            ? RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(projectColor.opacity(0.08))
                            : nil
                    )
                    .contextMenu {
                        Button("Rename") { editingProject = project }
                        Menu("Change Color") {
                            ForEach(ProjectFolder.presetColors, id: \.hex) { preset in
                                Button(action: { LocalStore.shared.changeProjectColor(id: project.id, color: preset.hex) }) {
                                    Label(preset.name, systemImage: "circle.fill")
                                }
                            }
                        }
                        Divider()
                        Button("Delete Project", role: .destructive) {
                            LocalStore.shared.deleteProject(id: project.id)
                        }
                    }

                    if isExp {
                        ForEach(folderMeetings) { meeting in
                            Button(action: { onSelect(meeting) }) {
                                SidebarMeetingRow(meeting: meeting, isSelected: selectedId == meeting.id)
                            }
                            .buttonStyle(.plain)
                            .draggable(meeting.id)
                            .contextMenu { contextMenu(meeting) }
                        }
                    }
                }

                Divider().opacity(0.15).padding(.horizontal, DesignTokens.Spacing.space4)
            }

            // Unlabeled
            if !unlabeled.isEmpty {
                SidebarSectionHeader(
                    title: "Unlabeled", isExpanded: LocalStore.shared.sectionBinding("unlabeled"),
                    count: unlabeled.count,
                    icon: "folder.fill", iconColor: Color.textTertiary,
                    isFolderStyle: true, dimmed: true
                )
                .dropDestination(for: String.self) { meetingIds, _ in
                    for id in meetingIds { onAssignProject(id, nil) }
                    return true
                }

                if !LocalStore.shared.isSectionCollapsed("unlabeled") {
                    ForEach(unlabeled) { meeting in
                        Button(action: { onSelect(meeting) }) {
                            SidebarMeetingRow(meeting: meeting, isSelected: selectedId == meeting.id)
                        }
                        .buttonStyle(.plain)
                        .draggable(meeting.id)
                        .contextMenu { contextMenu(meeting) }
                    }
                }
            }

            // New Project button
            Button(action: { showCreateProject = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accent)
                    Text("New Project")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accent)
                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Spacing.space4)
                .padding(.vertical, DesignTokens.Spacing.space3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, DesignTokens.Spacing.space2)
        .sheet(item: $editingProject) { project in
            ProjectEditorSheet(existing: project) { name, color in
                LocalStore.shared.renameProject(id: project.id, name: name)
                LocalStore.shared.changeProjectColor(id: project.id, color: color)
            }
        }
        .sheet(isPresented: $showCreateProject) {
            ProjectEditorSheet { name, color in
                let project = ProjectFolder(name: name, color: color)
                LocalStore.shared.addProject(project)
            }
        }
    }

    // MARK: - Accent bar wrapper

    /// Wraps content with a rounded left accent bar spanning the full section height.
    @ViewBuilder
    private func accentSection<Content: View>(color: Color, showBar: Bool = true, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            if showBar {
                UnevenRoundedRectangle(
                    topLeadingRadius: 4, bottomLeadingRadius: 4,
                    bottomTrailingRadius: 0, topTrailingRadius: 0
                )
                .fill(color)
                .frame(width: 4)
                .padding(.vertical, 4)
                .padding(.leading, 6)
            }
            VStack(spacing: 0) {
                content()
            }
        }
    }
}
#endif
