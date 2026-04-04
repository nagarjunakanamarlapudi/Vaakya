// VaakyaApp/Sources/Services/SyncService.swift
import Foundation
import Network

// MARK: - JSON Encoder/Decoder with ISO8601 dates (matching LocalStore)

extension JSONEncoder {
    static let vaakya: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let vaakya: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - SyncService (thin Vaakya wrapper around FileSync)

@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    var isSyncing: Bool { fileSync.isSyncing }
    var lastSyncDate: Date? { fileSync.lastSyncDate }
    var syncError: String? { fileSync.error }
    var isWifi = true

    private let fileSync: FileSync
    private let monitor = NWPathMonitor()
    private var periodicSyncTimer: Timer?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let baseDir = appSupport.appendingPathComponent("Vaakya")

        fileSync = FileSync(localDirectory: baseDir, presignURL: SyncService.presign)

        // Monitor network type for audio sync policy
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isWifi = path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: DispatchQueue(label: "vaakya.network"))
    }

    // MARK: - Periodic Sync

    /// Start periodic sync every 5 minutes (call after sign-in).
    func startPeriodicSync() {
        stopPeriodicSync()
        periodicSyncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard KeychainService.load(key: "access_token") != nil else { return }
                let settings = LocalStore.shared.loadSettings()
                if self.isWifi || settings.syncOnCellular {
                    print("[SyncService] Periodic sync triggered (\(self.isWifi ? "Wi-Fi" : "cellular"))")
                    await self.sync()
                } else {
                    print("[SyncService] Periodic sync skipped (cellular, user setting: Wi-Fi only)")
                }
            }
        }
        print("[SyncService] Periodic sync started (every 5 minutes)")
    }

    /// Stop periodic sync (call on sign-out).
    func stopPeriodicSync() {
        periodicSyncTimer?.invalidate()
        periodicSyncTimer = nil
    }

    // MARK: - Full Sync

    /// Pull server index, diff with local by lastModified, push/pull changed meetings.
    func sync() async {
        guard !fileSync.isSyncing else { return }
        guard KeychainService.load(key: "access_token") != nil else { return }

        fileSync.isSyncing = true
        fileSync.error = nil
        defer { fileSync.isSyncing = false }

        do {
            // 1. Build local and remote item lists
            let localMeetings = LocalStore.shared.meetings
            let serverIndex = try await fetchServerIndex()

            let localItems = localMeetings.map { (id: $0.id, lastModified: $0.lastModified) }
            let remoteItems = serverIndex.map { (id: $0.id, lastModified: $0.lastModified) }

            // 2. Bidirectional diff via FileSync
            let result = try await fileSync.syncAll(
                localItems: localItems,
                remoteItems: remoteItems,
                subdirectoryPrefix: "meetings"
            )

            // 3. Pull meetings that are remote-newer or new-on-server
            for id in result.pulled {
                try await pullMeeting(id: id)
            }

            // 4. Push updated index only if something changed
            if !result.pushed.isEmpty || !result.pulled.isEmpty {
                try await pushIndex()
            }

            // 5. Sync preferences (projects + tags)
            await pullPreferences()
            try await pushPreferences()

            fileSync.lastSyncDate = Date()
            print("[SyncService] Sync complete")
        } catch {
            fileSync.error = error.localizedDescription
            print("[SyncService] Sync failed: \(error)")
        }
    }

    /// Push all meetings (first sync after sign-in).
    func pushAll() async {
        for meeting in LocalStore.shared.meetings {
            try? await pushMeeting(id: meeting.id)
        }
        try? await pushIndex()
        try? await pushPreferences()
    }

    // MARK: - Individual Operations

    /// Push a single meeting's all files (JSON + audio). LocalStore already writes meeting.json
    /// to disk, and FileSync's manifest skips unchanged files (including already-uploaded audio).
    func pushMeeting(id: String) async throws {
        guard LocalStore.shared.loadMeeting(id: id) != nil else { return }
        try await fileSync.push(subdirectory: "meetings/\(id)")
        print("[SyncService] Pushed meeting \(id)")
    }

    /// Push the Vaakya-specific index.json.
    func pushIndex() async throws {
        let data = try JSONEncoder.vaakya.encode(LocalStore.shared.meetings)
        try await fileSync.pushFile(relativePath: "index.json", data: data)
    }

    /// Push preferences (projects + tags) so they sync across devices.
    func pushPreferences() async throws {
        let prefs = LocalStore.SyncablePreferences(
            projects: LocalStore.shared.projects,
            tags: LocalStore.shared.availableTags
        )
        let data = try JSONEncoder.vaakya.encode(prefs)
        try await fileSync.pushFile(relativePath: "preferences.json", data: data)
    }

    /// Pull preferences from S3 and merge into local state.
    func pullPreferences() async {
        do {
            let data = try await fileSync.pullData(key: "preferences.json")
            let prefs = try JSONDecoder.vaakya.decode(LocalStore.SyncablePreferences.self, from: data)
            // Merge: add any remote projects/tags not already local
            for project in prefs.projects {
                if !LocalStore.shared.projects.contains(where: { $0.id == project.id }) {
                    LocalStore.shared.addProject(project)
                }
            }
            for tag in prefs.tags {
                if !LocalStore.shared.availableTags.contains(tag) {
                    LocalStore.shared.createTag(tag)
                }
            }
        } catch let error as FileSyncError where error.isDownloadFailed {
            // 404 — no remote preferences yet, skip
        } catch {
            print("[SyncService] pullPreferences failed: \(error)")
        }
    }

    // MARK: - Pull

    private func pullMeeting(id: String) async throws {
        let data = try await fileSync.pullData(key: "meetings/\(id)/meeting.json")
        let doc = try JSONDecoder.vaakya.decode(MeetingDocument.self, from: data)
        LocalStore.shared.createMeeting(doc)
        print("[SyncService] Pulled meeting \(id)")
    }

    // MARK: - Helpers

    private func fetchServerIndex() async throws -> [MeetingMetadata] {
        do {
            let data = try await fileSync.pullData(key: "index.json")
            return try JSONDecoder.vaakya.decode([MeetingMetadata].self, from: data)
        } catch let error as FileSyncError where error.isDownloadFailed {
            // 404 = no index yet (first sync). Other errors propagate so sync aborts cleanly.
            return []
        }
    }

    /// Pre-sign closure passed to FileSync. Calls the Vaakya `/sync/presign` endpoint.
    private static func presign(action: String, key: String) async throws -> URL {
        guard let token = KeychainService.load(key: "access_token") else {
            throw SyncError.notSignedIn
        }

        #if DEBUG
        let baseURL = BuildConfig.apiBaseURL
        #else
        let baseURL = "https://api.vaakya.app"
        #endif

        var request = URLRequest(url: URL(string: "\(baseURL)/sync/presign")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["action": action, "key": key])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.presignFailed
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = json["url"] as? String,
              let url = URL(string: urlString) else {
            throw SyncError.invalidPresignResponse
        }
        return url
    }

    // MARK: - Errors

    enum SyncError: Error, LocalizedError {
        case notSignedIn
        case presignFailed
        case invalidPresignResponse
        case pushFailed(String)
        case pullFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to sync"
            case .presignFailed: return "Failed to get sync URL"
            case .invalidPresignResponse: return "Invalid sync response"
            case .pushFailed(let id): return "Failed to push meeting \(id)"
            case .pullFailed(let id): return "Failed to pull meeting \(id)"
            }
        }
    }
}
