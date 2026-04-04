#if os(macOS)
import SwiftUI

enum SidebarViewMode: String { case date, projects }

struct SidebarView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(MeetingViewModel.self) private var meetingVM
    @State private var showSettings: Bool = false
    @State private var searchText: String = ""
    @State private var viewMode: SidebarViewMode = SidebarViewMode(rawValue: UserDefaults.standard.string(forKey: "vaakya_sidebar_view_mode") ?? "date") ?? .date
    @State private var showCreateProject = false
    @State private var showNewTag = false
    @State private var newTagName = ""
    @State private var tagMeetingId: String? = nil
    @State private var meetingToDelete: MeetingMetadata? = nil

    let recorder: AudioRecorder

    private var allMeetings: [MeetingMetadata] { LocalStore.shared.meetings }

    private var filteredMeetings: [MeetingMetadata] {
        if searchText.isEmpty {
            return allMeetings
        }
        return allMeetings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        @Bindable var vm = meetingVM

        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { vm.selectedMeeting = nil }) {
                    Text("Meetings")
                        .font(DesignTokens.Typography.sectionHead)
                        .foregroundStyle(Color.textPrimary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    vm.showCreateSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                        Text("Record Meeting")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignTokens.Spacing.space3)
                    .padding(.vertical, DesignTokens.Spacing.space1 + 2)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(Color.accent)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space4)

            // Search field
            HStack(spacing: DesignTokens.Spacing.space2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
                TextField("Search meetings...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(Color.textPrimary)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.space3)
            .padding(.vertical, DesignTokens.Spacing.space2)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(Color.bgContent)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.bottom, DesignTokens.Spacing.space2)

            // View mode toggle
            Picker("", selection: $viewMode) {
                Text("By Date").tag(SidebarViewMode.date)
                Text("Projects").tag(SidebarViewMode.projects)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.bottom, DesignTokens.Spacing.space2)
            .onChange(of: viewMode) { _, newVal in
                UserDefaults.standard.set(newVal.rawValue, forKey: "vaakya_sidebar_view_mode")
            }

            // Recording indicator
            if recorder.isRecording {
                HStack(spacing: DesignTokens.Spacing.space2) {
                    Circle()
                        .fill(Color.blockRed)
                        .frame(width: 6, height: 6)
                    Text("Recording")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.blockRed)
                    Spacer()
                    Text(recorder.formattedDuration)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.blockRed)
                }
                .padding(.horizontal, DesignTokens.Spacing.space4)
                .padding(.vertical, DesignTokens.Spacing.space2)
                .background(Color.blockRed.opacity(0.08))
            }

            Divider().opacity(0.5)

            // Meeting list
            if meetingVM.isLoadingMeetings {
                Spacer()
                ProgressView()
                    .tint(Color.accent)
                Spacer()
            } else if filteredMeetings.isEmpty {
                Spacer()
                if searchText.isEmpty {
                    EmptyStateView(
                        icon: "text.bubble",
                        title: "No meetings yet",
                        subtitle: "Record your first meeting to get started",
                        actionLabel: "Record Meeting",
                        action: { vm.showCreateSheet = true }
                    )
                } else {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No matches",
                        subtitle: "Try a different search term"
                    )
                }
                Spacer()
            } else {
                ScrollView {
                    if !searchText.isEmpty {
                        // Flat search results
                        LazyVStack(spacing: DesignTokens.Spacing.space1) {
                            ForEach(filteredMeetings) { meeting in
                                meetingButton(meeting)
                            }
                        }
                        .padding(.vertical, DesignTokens.Spacing.space2)
                    } else if viewMode == .projects {
                        SidebarProjectView(
                            meetings: allMeetings,
                            projects: LocalStore.shared.projects,
                            selectedId: meetingVM.selectedMeeting?.id,
                            onSelect: { meetingVM.selectMeeting($0) },
                            onAssignProject: { meetingId, projectId in
                                LocalStore.shared.assignProject(meetingId: meetingId, projectId: projectId)
                            },
                            contextMenu: { meeting in AnyView(meetingContextMenu(meeting)) }
                        )
                    } else {
                        SidebarDateView(
                            meetings: allMeetings,
                            projects: LocalStore.shared.projects,
                            selectedId: meetingVM.selectedMeeting?.id,
                            onSelect: { meetingVM.selectMeeting($0) },
                            contextMenu: { meeting in AnyView(meetingContextMenu(meeting)) }
                        )
                    }
                }
            }

            Divider().opacity(0.5)

            // Footer with user info and settings
            HStack(spacing: DesignTokens.Spacing.space2) {
                Circle()
                    .fill(Color.accent.opacity(0.15))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(initials)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accent)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(auth.currentUser?.name ?? (auth.isAnonymous ? "Local User" : "User"))
                        .font(DesignTokens.Typography.label)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text(auth.isAnonymous ? "Not signed in" : (auth.currentUser?.email ?? ""))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Settings gear
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Settings")

                if auth.isLoggedIn {
                    Button(action: { auth.logout() }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Sign out")
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space3)
        }
        .background(Color.bgSidebar)
        .frame(minWidth: 240, idealWidth: 280)
        .sheet(isPresented: $vm.showCreateSheet) {
            createMeetingSheet
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(auth)
        }
        .sheet(isPresented: $showCreateProject) {
            ProjectEditorSheet { name, color in
                let project = ProjectFolder(name: name, color: color)
                LocalStore.shared.addProject(project)
            }
        }
        .alert("New Tag", isPresented: $showNewTag) {
            TextField("Tag name", text: $newTagName)
            Button("Add") {
                let tag = newTagName.trimmingCharacters(in: .whitespaces)
                guard !tag.isEmpty, let meetingId = tagMeetingId else { return }
                LocalStore.shared.addTag(tag, toMeeting: meetingId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new tag.")
        }
        .alert("Delete meeting?", isPresented: Binding(
            get: { meetingToDelete != nil },
            set: { if !$0 { meetingToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { meetingToDelete = nil }
            Button("Delete", role: .destructive) {
                if let meeting = meetingToDelete {
                    meetingVM.deleteMeeting(meeting)
                }
                meetingToDelete = nil
            }
        } message: {
            if let meeting = meetingToDelete {
                Text("Delete \"\(meeting.title)\"? This will remove the transcript, notes, and audio. This cannot be undone.")
            }
        }
    }

    private var initials: String {
        let name = auth.currentUser?.name ?? (auth.isAnonymous ? "LU" : "User")
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func meetingButton(_ meeting: MeetingMetadata) -> some View {
        Button(action: { meetingVM.selectMeeting(meeting) }) {
            SidebarMeetingRow(
                meeting: meeting,
                isSelected: meetingVM.selectedMeeting?.id == meeting.id
            )
        }
        .buttonStyle(.plain)
        .draggable(meeting.id)
        .contextMenu { meetingContextMenu(meeting) }
    }

    @ViewBuilder
    private func meetingContextMenu(_ meeting: MeetingMetadata) -> some View {
        Button(action: { LocalStore.shared.togglePin(meetingId: meeting.id) }) {
            Label(meeting.isPinned ? "Unpin" : "Pin", systemImage: meeting.isPinned ? "pin.slash" : "pin")
        }

        Menu("Move to Project") {
            ProjectPickerMenu(
                meetingId: meeting.id,
                currentProjectId: meeting.project,
                showCreateProject: $showCreateProject
            )
        }

        Menu("Tags") {
            TagPickerMenu(
                meetingId: meeting.id,
                currentTags: meeting.tags,
                showNewTag: $showNewTag,
                tagMeetingId: $tagMeetingId
            )
        }

        Divider()
        Button("Delete", role: .destructive) { meetingToDelete = meeting }
    }

    private var createMeetingSheet: some View {
        @Bindable var vm = meetingVM
        return VStack(spacing: DesignTokens.Spacing.space6) {
            Text("New Meeting")
                .font(DesignTokens.Typography.sectionHead)
                .foregroundStyle(Color.textPrimary)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                Text("Title")
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(Color.textSecondary)

                TextField("Meeting title", text: $vm.newMeetingTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.space3)
                    .padding(.vertical, DesignTokens.Spacing.space3)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .fill(Color.bgContent)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
                            )
                    )
            }

            HStack(spacing: DesignTokens.Spacing.space3) {
                Button("Cancel") {
                    vm.showCreateSheet = false
                    vm.newMeetingTitle = ""
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)

                Button("Create") {
                    meetingVM.createMeeting(title: meetingVM.newMeetingTitle)
                    vm.showCreateSheet = false
                    vm.newMeetingTitle = ""
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignTokens.Button.paddingH)
                .padding(.vertical, DesignTokens.Spacing.space2)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Button.cornerRadius)
                        .fill(Color.accent)
                )
                .foregroundStyle(Color.white)
                .disabled(meetingVM.newMeetingTitle.isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.space6)
        .frame(width: 380)
        .background(Color.bgApp)
    }
}
#endif
