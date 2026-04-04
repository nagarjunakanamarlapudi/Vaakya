import EventKit
import Foundation

/// Wraps EventKit to provide calendar event data for meeting pre-population.
@MainActor
@Observable
final class CalendarService {
    private let store = EKEventStore()

    var isAuthorized: Bool = false
    var upcomingEvents: [EKEvent] = []
    var nextEvent: EKEvent?
    var authorizationError: String?

    // MARK: - Authorization

    func requestAccess() async {
        do {
            let granted: Bool
            if #available(macOS 14.0, iOS 17.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
            isAuthorized = granted
            if granted {
                authorizationError = nil
                loadUpcoming()
                startWatching()
            } else {
                authorizationError = "Calendar access denied. Grant access in System Settings > Privacy & Security > Calendars."
            }
        } catch {
            authorizationError = error.localizedDescription
            isAuthorized = false
        }
    }

    // MARK: - Load Events

    /// Fetch today's remaining events, sorted by start time. Sets `nextEvent` to the soonest future event.
    func loadUpcoming() {
        guard isAuthorized else { return }

        let now = Date()
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now

        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        self.upcomingEvents = events
        self.nextEvent = events.first
    }

    // MARK: - Participants

    /// Extract attendee names and emails from a calendar event.
    func participants(for event: EKEvent) -> [(name: String, email: String)] {
        guard let attendees = event.attendees else { return [] }
        return attendees.compactMap { attendee in
            let name = attendee.name ?? "Unknown"
            // EKParticipant exposes URL as "mailto:email@example.com"
            let url = attendee.url
            let email: String
            if url.scheme == "mailto" {
                email = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            } else {
                email = ""
            }
            return (name: name, email: email)
        }
    }

    // MARK: - Video Link Detection

    /// Regex search in URL, location, and notes for known video conferencing links.
    func videoLink(for event: EKEvent) -> String? {
        let sources = [
            event.url?.absoluteString,
            event.location,
            event.notes
        ].compactMap { $0 }

        let patterns = [
            // Zoom
            #"https?://[\w.-]*zoom\.us/[jw]/\S+"#,
            // Google Meet
            #"https?://meet\.google\.com/\S+"#,
            // Microsoft Teams
            #"https?://teams\.microsoft\.com/l/meetup-join/\S+"#,
            // Webex
            #"https?://[\w.-]*webex\.com/\S+"#,
            // FaceTime
            #"https?://facetime\.apple\.com/\S+"#
        ]

        for source in sources {
            for pattern in patterns {
                if let range = source.range(of: pattern, options: .regularExpression) {
                    return String(source[range])
                }
            }
        }
        return nil
    }

    // MARK: - Template Suggestion

    /// Keyword matching on event title to suggest a meeting template.
    func suggestedTemplate(for event: EKEvent) -> String {
        let title = event.title?.lowercased() ?? ""

        if title.contains("standup") || title.contains("stand-up") || title.contains("daily sync") {
            return "standup"
        }
        if title.contains("1:1") || title.contains("1-on-1") || title.contains("one on one") || title.contains("1 on 1") {
            return "one_on_one"
        }
        if title.contains("retro") || title.contains("retrospective") {
            return "retrospective"
        }
        if title.contains("sprint") || title.contains("planning") || title.contains("backlog") {
            return "planning"
        }
        if title.contains("interview") {
            return "interview"
        }
        if title.contains("all hands") || title.contains("all-hands") || title.contains("town hall") {
            return "all_hands"
        }
        if title.contains("brainstorm") {
            return "brainstorm"
        }
        return "general"
    }

    // MARK: - Change Watching

    private var observer: NSObjectProtocol?

    private func startWatching() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadUpcoming()
            }
        }
    }

    func stopWatching() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
