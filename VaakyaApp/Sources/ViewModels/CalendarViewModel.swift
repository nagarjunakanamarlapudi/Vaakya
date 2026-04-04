import EventKit
import Foundation
import UserNotifications

/// Pre-populated meeting data derived from a calendar event.
struct CalendarMeetingData {
    let title: String
    let participants: [(name: String, email: String)]
    let participantsJSON: String
    let template: String
    let source: MeetingSource
    let videoLink: String?
    let eventDurationMinutes: Int
}

/// Combines CalendarService + MeetingSourceDetector to provide calendar-aware meeting creation.
@MainActor
@Observable
final class CalendarViewModel {
    let calendarService = CalendarService()

    var autoStartEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoStartEnabled, forKey: "vaakya_auto_start_enabled")
        }
    }

    /// Timer for periodic meeting check.
    private var checkTimer: Timer?
    /// Tracks event IDs we already sent notifications for.
    private var notifiedEventIDs: Set<String> = []

    init() {
        self.autoStartEnabled = UserDefaults.standard.bool(forKey: "vaakya_auto_start_enabled")
    }

    // MARK: - Setup

    /// Request calendar access, set up periodic check, and request notification permission.
    func setup() async {
        await calendarService.requestAccess()
        startPeriodicCheck()
        await requestNotificationPermission()
    }

    // MARK: - Meeting Data from Event

    /// Build pre-populated meeting data from a calendar event.
    func meetingFromEvent(_ event: EKEvent) -> CalendarMeetingData {
        let participants = calendarService.participants(for: event)
        let videoLink = calendarService.videoLink(for: event)
        let template = calendarService.suggestedTemplate(for: event)
        let source = MeetingSourceDetector.detect(fromURL: videoLink)

        // Encode participants as JSON array
        let participantDicts = participants.map { ["name": $0.name, "email": $0.email] }
        let participantsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: participantDicts),
           let json = String(data: data, encoding: .utf8) {
            participantsJSON = json
        } else {
            participantsJSON = "[]"
        }

        let duration = Int(event.endDate.timeIntervalSince(event.startDate) / 60)

        return CalendarMeetingData(
            title: event.title ?? "Untitled Meeting",
            participants: participants,
            participantsJSON: participantsJSON,
            template: template,
            source: source,
            videoLink: videoLink,
            eventDurationMinutes: duration
        )
    }

    // MARK: - Periodic Check

    private func startPeriodicCheck() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.periodicCheck()
            }
        }
    }

    private func periodicCheck() {
        calendarService.loadUpcoming()

        guard autoStartEnabled else { return }

        // Send notification 1 minute before meeting starts
        for event in calendarService.upcomingEvents {
            guard let eventID = event.eventIdentifier else { continue }
            guard !notifiedEventIDs.contains(eventID) else { continue }

            let timeUntilStart = event.startDate.timeIntervalSinceNow
            // If event starts in the next 60 seconds, send notification
            if timeUntilStart > 0 && timeUntilStart <= 60 {
                sendPreMeetingNotification(for: event)
                notifiedEventIDs.insert(eventID)
            }
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() async {
        // UNUserNotificationCenter requires a bundle identifier.
        // Skip if running without one (debug builds from swift build).
        guard Bundle.main.bundleIdentifier != nil else {
            print("[CalendarViewModel] Skipping notification permission — no bundle identifier")
            return
        }
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func sendPreMeetingNotification(for event: EKEvent) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting starting soon"

        let participantCount = event.attendees?.count ?? 0
        if participantCount > 0 {
            content.body = "\(event.title ?? "Meeting") with \(participantCount) participant\(participantCount == 1 ? "" : "s") in 1 min -- tap to start recording"
        } else {
            content.body = "\(event.title ?? "Meeting") in 1 min -- tap to start recording"
        }
        content.sound = .default
        content.categoryIdentifier = "MEETING_REMINDER"

        let request = UNNotificationRequest(
            identifier: "meeting-\(event.eventIdentifier ?? UUID().uuidString)",
            content: content,
            trigger: nil // Fire immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    func stopPeriodicCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
}
