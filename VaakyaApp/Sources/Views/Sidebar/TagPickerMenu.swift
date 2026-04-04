#if os(macOS)
import SwiftUI

struct TagPickerMenu: View {
    let meetingId: String
    let currentTags: [String]
    @Binding var showNewTag: Bool
    @Binding var tagMeetingId: String?

    var body: some View {
        ForEach(LocalStore.shared.availableTags, id: \.self) { tag in
            Button(action: {
                if currentTags.contains(tag) {
                    LocalStore.shared.removeTag(tag, fromMeeting: meetingId)
                } else {
                    LocalStore.shared.addTag(tag, toMeeting: meetingId)
                }
            }) {
                HStack {
                    Text(tag)
                    if currentTags.contains(tag) { Image(systemName: "checkmark") }
                }
            }
        }
        if !LocalStore.shared.availableTags.isEmpty { Divider() }
        Button("New Tag...") {
            tagMeetingId = meetingId
            showNewTag = true
        }
    }
}
#endif
