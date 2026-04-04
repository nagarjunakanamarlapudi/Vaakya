#if os(macOS)
import SwiftUI

struct ProjectPickerMenu: View {
    let meetingId: String
    let currentProjectId: String?
    @Binding var showCreateProject: Bool

    var body: some View {
        ForEach(LocalStore.shared.projects) { project in
            Button(action: {
                LocalStore.shared.assignProject(meetingId: meetingId, projectId: project.id)
            }) {
                Label(project.name, systemImage: "folder.fill")
            }
        }
        Divider()
        if currentProjectId != nil {
            Button("Remove from Project") {
                LocalStore.shared.assignProject(meetingId: meetingId, projectId: nil)
            }
        }
        Button("New Project...") { showCreateProject = true }
    }
}
#endif
