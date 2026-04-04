import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Detected meeting platform source.
enum MeetingSource: String, Codable, Sendable {
    case zoom
    case meet
    case teams
    case facetime
    case webex
    case inPerson = "in_person"
    case manual

    /// Human-readable tag for display in UI.
    var displayTag: String {
        switch self {
        case .zoom: return "Zoom"
        case .meet: return "Meet"
        case .teams: return "Teams"
        case .facetime: return "FaceTime"
        case .webex: return "Webex"
        case .inPerson: return "In Person"
        case .manual: return "Manual"
        }
    }
}

/// Detects the meeting source from running processes or URLs.
struct MeetingSourceDetector {

    // Known macOS bundle identifiers for video conferencing apps.
    private static let bundleMap: [(bundleID: String, source: MeetingSource)] = [
        ("us.zoom.xos", .zoom),
        ("com.microsoft.teams2", .teams),
        ("com.microsoft.teams", .teams),
        ("com.cisco.webexmeetingsapp", .webex),
        ("com.apple.facetime", .facetime)
    ]

    // URL patterns mapped to sources.
    private static let urlPatterns: [(pattern: String, source: MeetingSource)] = [
        ("zoom.us", .zoom),
        ("meet.google.com", .meet),
        ("teams.microsoft.com", .teams),
        ("webex.com", .webex),
        ("facetime.apple.com", .facetime)
    ]

    /// Detect meeting source by checking running applications on macOS.
    /// On iOS, always returns `.inPerson`.
    static func detect() -> MeetingSource {
        #if os(macOS)
        let runningApps = NSWorkspace.shared.runningApplications
        for mapping in bundleMap {
            if runningApps.contains(where: { $0.bundleIdentifier == mapping.bundleID }) {
                return mapping.source
            }
        }
        return .manual
        #else
        return .inPerson
        #endif
    }

    /// Detect meeting source from a URL string (e.g., from a calendar event).
    static func detect(fromURL urlString: String) -> MeetingSource? {
        let lowered = urlString.lowercased()
        for mapping in urlPatterns {
            if lowered.contains(mapping.pattern) {
                return mapping.source
            }
        }
        return nil
    }

    /// Detect from either a URL (calendar event link) or running processes, with URL taking priority.
    static func detect(fromURL urlString: String?) -> MeetingSource {
        if let urlString, let source = detect(fromURL: urlString) {
            return source
        }
        return detect()
    }
}
