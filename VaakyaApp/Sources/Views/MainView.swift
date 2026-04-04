#if os(macOS)
import SwiftUI

struct MainView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var meetingVM = MeetingViewModel()
    @State private var recorder = AudioRecorder()
    @State private var toastManager = ToastManager()
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @State private var calendarVM = CalendarViewModel()

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView(recorder: recorder)
                .environment(meetingVM)
        } detail: {
            if meetingVM.selectedMeeting != nil {
                MeetingDetailView(recorder: recorder)
                    .environment(meetingVM)
            } else {
                DashboardView(recorder: recorder)
                    .environment(meetingVM)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.bgApp)
        .frame(minWidth: 800, minHeight: 550)
        .toolbar(.hidden)
        .task {
            await calendarVM.setup()
            // Model is pre-loaded in VaakyaApp.swift before MainView appears
        }
        .overlay(alignment: .top) {
            if let toast = toastManager.currentToast {
                ToastView(
                    message: toast.message,
                    type: toast.type,
                    onDismiss: { toastManager.dismiss() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: meetingVM.errorMessage) { _, newVal in
            if let msg = newVal {
                toastManager.show(msg, type: .error)
                meetingVM.errorMessage = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation { sidebarVisibility = sidebarVisibility == .detailOnly ? .automatic : .detailOnly }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTranscript)) { _ in
            meetingVM.toggleTranscriptRequest.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .enhanceMeeting)) { _ in
            meetingVM.enhanceRequest.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newMeeting)) { _ in
            meetingVM.showCreateSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .startRecording)) { _ in
            // Pre-fill from calendar if an event is starting within 5 minutes
            var title = "Recording \(Date().formatted(date: .abbreviated, time: .shortened))"
            let now = Date()
            if let nextEvent = calendarVM.calendarService.upcomingEvents.first(where: {
                let timeUntilStart = $0.startDate.timeIntervalSince(now)
                return timeUntilStart > -300 && timeUntilStart < 300  // within 5 min
            }) {
                title = nextEvent.title ?? title
            }
            meetingVM.createMeeting(title: title)
        }
    }
}
#endif
