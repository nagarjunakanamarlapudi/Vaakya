// VaakyaApp/Sources/Services/LocalStore.swift
import Foundation
import SwiftUI

@MainActor
@Observable
final class LocalStore {
    static let shared = LocalStore()

    // MARK: - Public State

    private(set) var meetings: [MeetingMetadata] = []
    var isInitialized = false

    // MARK: - Private

    private let baseDirectory: URL
    private let meetingsDirectory: URL
    private let indexURL: URL
    private let preferencesURL: URL
    private let settingsURL: URL
    private let wal: WALWriter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var flushTimer: Timer?
    private var isFlushing = false

    // MARK: - Projects

    private(set) var projects: [ProjectFolder] = []

    // In-memory cache of full documents for currently open meetings
    private var documentCache: [String: MeetingDocument] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDirectory = appSupport.appendingPathComponent("Vaakya")
        meetingsDirectory = baseDirectory.appendingPathComponent("meetings")
        indexURL = baseDirectory.appendingPathComponent("index.json")
        preferencesURL = baseDirectory.appendingPathComponent("preferences.json")
        settingsURL = baseDirectory.appendingPathComponent("settings.json")

        // Create directories
        try? FileManager.default.createDirectory(at: meetingsDirectory, withIntermediateDirectories: true)

        wal = WALWriter(directory: baseDirectory)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Lifecycle

    /// Initialize on app launch: load all meeting metadata into memory, replay WAL.
    func initialize() async {
        // 0. Load saved index to recover sidebar-only metadata (isPinned, project, tags)
        var savedIndex: [String: MeetingMetadata] = [:]
        if let indexData = try? Data(contentsOf: indexURL),
           let indexed = try? decoder.decode([MeetingMetadata].self, from: indexData) {
            for m in indexed { savedIndex[m.id] = m }
        }

        // 1. Scan meetings directory for all meeting.json files
        var loadedMeetings: [MeetingMetadata] = []
        if let meetingDirs = try? FileManager.default.contentsOfDirectory(
            at: meetingsDirectory, includingPropertiesForKeys: nil
        ) {
            for dir in meetingDirs {
                let jsonURL = dir.appendingPathComponent("meeting.json")
                guard FileManager.default.fileExists(atPath: jsonURL.path) else { continue }
                if let data = try? Data(contentsOf: jsonURL),
                   let doc = try? decoder.decode(MeetingDocument.self, from: data) {
                    let audioExists = FileManager.default.fileExists(
                        atPath: dir.appendingPathComponent("audio.m4a").path
                    )
                    let meta = MeetingMetadata.from(doc, hasAudio: audioExists, preserving: savedIndex[doc.id])
                    loadedMeetings.append(meta)
                }
            }
        }

        // 2. Replay WAL entries on top of loaded state
        let walEntries = wal.pendingEntries()
        if !walEntries.isEmpty {
            print("[LocalStore] Replaying \(walEntries.count) WAL entries")
            for entry in walEntries {
                switch entry.operation {
                case .create, .update:
                    guard let doc = entry.data else { continue }
                    let meta = MeetingMetadata.from(doc, preserving: savedIndex[doc.id])
                    if let idx = loadedMeetings.firstIndex(where: { $0.id == doc.id }) {
                        loadedMeetings[idx] = meta
                    } else {
                        loadedMeetings.append(meta)
                    }
                case .delete:
                    loadedMeetings.removeAll { $0.id == entry.meetingId }
                }
            }
            // Flush WAL to disk to ensure consistency
            flush()
        }

        // 3. Sort by date (newest first) and publish
        meetings = loadedMeetings.sorted { $0.startedAt > $1.startedAt }
        loadProjects()  // Also loads tags + collapsedSections from preferences.json
        isInitialized = true
        print("[LocalStore] Initialized with \(meetings.count) meetings")

        // 4. Start periodic flush timer
        startFlushTimer()
    }

    // MARK: - Read

    /// Returns the in-memory meetings array.
    func allMeetings() -> [MeetingMetadata] {
        meetings
    }

    /// Load full meeting document from disk (or cache).
    func loadMeeting(id: String) -> MeetingDocument? {
        if let cached = documentCache[id] { return cached }
        let jsonURL = meetingsDirectory
            .appendingPathComponent(id)
            .appendingPathComponent("meeting.json")
        guard let data = try? Data(contentsOf: jsonURL),
              let doc = try? decoder.decode(MeetingDocument.self, from: data) else {
            return nil
        }
        documentCache[id] = doc
        return doc
    }

    /// Search meetings by title or participant name.
    func searchMeetings(query: String) -> [MeetingMetadata] {
        let q = query.lowercased()
        return meetings.filter { meta in
            meta.title.lowercased().contains(q) ||
            meta.participantNames.contains { $0.lowercased().contains(q) }
        }
    }

    /// Audio URL for a meeting (nil if no audio recorded).
    func audioURL(for meetingId: String) -> URL? {
        let url = meetingsDirectory
            .appendingPathComponent(meetingId)
            .appendingPathComponent("audio.m4a")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Write

    /// Create a new meeting.
    func createMeeting(_ meeting: MeetingDocument) {
        // Create directory
        let dir = meetingsDirectory.appendingPathComponent(meeting.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Write WAL
        let op = WALOperation(timestamp: Date(), operation: .create, meetingId: meeting.id, data: meeting)
        do {
            try wal.append(op)
        } catch {
            print("[LocalStore] WAL append failed: \(error)")
        }

        // Update in-memory — preserve sidebar metadata if meeting already exists (sync pull)
        documentCache[meeting.id] = meeting
        if let idx = meetings.firstIndex(where: { $0.id == meeting.id }) {
            let meta = MeetingMetadata.from(meeting, preserving: meetings[idx])
            meetings[idx] = meta
        } else {
            meetings.insert(MeetingMetadata.from(meeting), at: 0)
        }
    }

    /// Update an existing meeting.
    func updateMeeting(_ meeting: MeetingDocument) {
        var updated = meeting
        updated.lastModified = Date()

        // Write WAL
        let op = WALOperation(timestamp: Date(), operation: .update, meetingId: meeting.id, data: updated)
        do {
            try wal.append(op)
        } catch {
            print("[LocalStore] WAL append failed: \(error)")
        }

        // Update in-memory — preserve sidebar-only metadata (pin, project, tags)
        documentCache[meeting.id] = updated
        if let idx = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[idx] = MeetingMetadata.from(updated, hasAudio: audioURL(for: meeting.id) != nil, preserving: meetings[idx])
        }
    }

    /// Delete a meeting and its files.
    func deleteMeeting(id: String) {
        // Write WAL
        let op = WALOperation(timestamp: Date(), operation: .delete, meetingId: id, data: nil)
        do {
            try wal.append(op)
        } catch {
            print("[LocalStore] WAL append failed: \(error)")
        }

        // Remove from memory
        documentCache.removeValue(forKey: id)
        meetings.removeAll { $0.id == id }

        // Remove files
        let dir = meetingsDirectory.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Save audio file for a meeting.
    func saveAudio(meetingId: String, from sourceURL: URL) {
        let dir = meetingsDirectory.appendingPathComponent(meetingId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destURL = dir.appendingPathComponent("audio.m4a")
        try? FileManager.default.removeItem(at: destURL) // remove old if exists
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            print("[LocalStore] ERROR: saveAudio copy failed — \(error)")
            return
        }

        // Update hasAudio in index
        if let idx = meetings.firstIndex(where: { $0.id == meetingId }) {
            meetings[idx].hasAudio = true
        }
    }

    // MARK: - Stats (computed from in-memory index)

    var meetingsThisWeek: Int {
        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return meetings.filter { $0.startedAt >= startOfWeek }.count
    }

    var totalCapturedSeconds: Int {
        meetings.compactMap(\.durationSeconds).reduce(0, +)
    }

    var pendingActionItems: Int {
        meetings.map(\.pendingActionItems).reduce(0, +)
    }

    var aiEnhancedCount: Int {
        meetings.filter(\.isEnhanced).count
    }

    // MARK: - Project Storage

    func loadProjects() {
        if let prefs = loadPreferences() {
            projects = prefs.projects.sorted(by: { $0.sortOrder < $1.sortOrder })
            availableTags = prefs.tags
            collapsedSections = Set(prefs.collapsedSections ?? [])
        }
    }

    func saveProjects() {
        savePreferences()
    }

    // MARK: - Project CRUD

    func addProject(_ project: ProjectFolder) {
        var p = project
        p.sortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
        projects.append(p)
        saveProjects()
    }

    func deleteProject(id: String) {
        projects.removeAll { $0.id == id }
        for i in meetings.indices where meetings[i].project == id {
            meetings[i].project = nil
        }
        saveProjects()
        flushIndex()
    }

    func renameProject(id: String, name: String) {
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].name = name
            saveProjects()
        }
    }

    func changeProjectColor(id: String, color: String) {
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].color = color
            saveProjects()
        }
    }

    // MARK: - Meeting Metadata Mutations (sidebar-only, no document change)

    func togglePin(meetingId: String) {
        guard let idx = meetings.firstIndex(where: { $0.id == meetingId }) else { return }
        meetings[idx].isPinned.toggle()
        if !meetings[idx].isPinned { meetings[idx].pinSortOrder = nil }
        flushIndex()
    }

    func setPinOrder(meetingId: String, order: Int) {
        guard let idx = meetings.firstIndex(where: { $0.id == meetingId }) else { return }
        meetings[idx].pinSortOrder = order
        flushIndex()
    }

    /// Batch update pin sort orders — single disk write instead of N.
    func setPinOrders(_ orders: [(meetingId: String, order: Int)]) {
        for (meetingId, order) in orders {
            if let idx = meetings.firstIndex(where: { $0.id == meetingId }) {
                meetings[idx].pinSortOrder = order
            }
        }
        flushIndex()
    }

    func assignProject(meetingId: String, projectId: String?) {
        guard let idx = meetings.firstIndex(where: { $0.id == meetingId }) else { return }
        meetings[idx].project = projectId
        flushIndex()
    }

    // MARK: - Tags

    private(set) var availableTags: [String] = []

    private func saveTags() {
        savePreferences()
    }

    func addTag(_ tag: String, toMeeting meetingId: String) {
        guard let idx = meetings.firstIndex(where: { $0.id == meetingId }) else { return }
        if !meetings[idx].tags.contains(tag) {
            meetings[idx].tags.append(tag)
            flushIndex()
        }
        if !availableTags.contains(tag) {
            availableTags.append(tag)
            saveTags()
        }
    }

    func removeTag(_ tag: String, fromMeeting meetingId: String) {
        guard let idx = meetings.firstIndex(where: { $0.id == meetingId }) else { return }
        meetings[idx].tags.removeAll { $0 == tag }
        flushIndex()
    }

    func createTag(_ tag: String) {
        guard !availableTags.contains(tag) else { return }
        availableTags.append(tag)
        saveTags()
    }

    // MARK: - Index Persistence

    /// Write only the meetings index to disk (lightweight, no WAL replay).
    private func flushIndex() {
        do {
            let data = try encoder.encode(meetings)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("[LocalStore] ERROR: flushIndex failed — \(error)")
        }
        scheduleSyncPush()
    }

    /// Debounced sync push — coalesces rapid changes into a single push after 2 seconds.
    private var syncPushTask: Task<Void, Never>?

    private func scheduleSyncPush() {
        syncPushTask?.cancel()
        syncPushTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            guard KeychainService.load(key: "access_token") != nil else { return }
            do {
                try await SyncService.shared.pushIndex()
                try await SyncService.shared.pushPreferences()
            } catch {
                print("[Sync] scheduleSyncPush failed: \(error)")
            }
        }
    }

    // MARK: - Preferences (synced to S3 alongside index.json)

    /// Projects + tags + UI state bundled into a single syncable file.
    struct SyncablePreferences: Codable {
        var projects: [ProjectFolder]
        var tags: [String]
        var collapsedSections: [String]?  // section IDs that are collapsed
    }

    /// Section IDs that the user has collapsed (persisted across restarts).
    private(set) var collapsedSections: Set<String> = []

    func isSectionCollapsed(_ id: String) -> Bool { collapsedSections.contains(id) }

    func sectionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !self.isSectionCollapsed(id) },
            set: { _ in self.toggleSectionCollapsed(id) }
        )
    }

    func toggleSectionCollapsed(_ id: String) {
        if collapsedSections.contains(id) {
            collapsedSections.remove(id)
        } else {
            collapsedSections.insert(id)
        }
        savePreferences()
    }

    private func savePreferences() {
        let prefs = SyncablePreferences(
            projects: projects, tags: availableTags,
            collapsedSections: Array(collapsedSections)
        )
        do {
            let data = try encoder.encode(prefs)
            try data.write(to: preferencesURL, options: .atomic)
        } catch {
            print("[LocalStore] ERROR: savePreferences failed — \(error)")
        }
    }

    private func loadPreferences() -> SyncablePreferences? {
        guard FileManager.default.fileExists(atPath: preferencesURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: preferencesURL)
            return try decoder.decode(SyncablePreferences.self, from: data)
        } catch {
            print("[LocalStore] ERROR: preferences.json corrupt — \(error)")
            return nil
        }
    }

    // MARK: - Settings

    func loadSettings() -> LocalSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? decoder.decode(LocalSettings.self, from: data) else {
            return LocalSettings()
        }
        return settings
    }

    func saveSettings(_ settings: LocalSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    // MARK: - Flush (WAL -> disk)

    /// Flush all pending WAL entries to disk.
    func flush() {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        let entries = wal.pendingEntries()
        guard !entries.isEmpty else { return }

        // Truncate WAL BEFORE writing to disk so a concurrent append after
        // truncate starts a new WAL and is not lost.
        try? wal.truncate()

        // Group by meetingId, take latest entry for each
        var latestByMeeting: [String: WALOperation] = [:]
        for entry in entries {
            latestByMeeting[entry.meetingId] = entry
        }

        // Write each meeting's latest state to disk
        for (meetingId, entry) in latestByMeeting {
            switch entry.operation {
            case .create, .update:
                guard let doc = entry.data else { continue }
                let dir = meetingsDirectory.appendingPathComponent(meetingId)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let jsonURL = dir.appendingPathComponent("meeting.json")
                if let data = try? encoder.encode(doc) {
                    try? data.write(to: jsonURL, options: .atomic)
                }
            case .delete:
                let dir = meetingsDirectory.appendingPathComponent(meetingId)
                try? FileManager.default.removeItem(at: dir)
            }
        }

        // Write index
        if let indexData = try? encoder.encode(meetings) {
            try? indexData.write(to: indexURL, options: .atomic)
        }

        print("[LocalStore] Flushed \(entries.count) WAL entries for \(latestByMeeting.count) meetings")
    }

    // MARK: - Flush Timer

    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flush()
            }
        }
    }

    /// Call on app termination / backgrounding.
    func shutdown() {
        flushTimer?.invalidate()
        flushTimer = nil
        flush()
    }
}
