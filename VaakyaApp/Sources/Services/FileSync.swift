// VaakyaApp/Sources/Services/FileSync.swift
import Foundation

// MARK: - SyncManifest

/// Tracks which files have been synced and when, so unchanged files can be skipped.
struct SyncManifest: Codable {
    var files: [String: Date] = [:]  // relativePath -> lastSyncedModificationDate

    static func load(from url: URL) -> SyncManifest {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(SyncManifest.self, from: data) else {
            return SyncManifest()
        }
        return manifest
    }

    func save(to url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - FileSync

/// Generic bidirectional file sync between a local directory and a remote store.
/// Uses pre-signed URLs for upload/download — works with S3, GCS, Azure, or any
/// storage that supports pre-signed URLs.
///
/// Usage:
///   let sync = FileSync(
///       localDirectory: myDir,
///       presignURL: { action, key in /* return pre-signed URL */ }
///   )
///   try await sync.push(subdirectory: "folder1")
///   await sync.syncAll(localItems: [...], remoteItems: [...])
@MainActor
@Observable
final class FileSync {
    var isSyncing = false
    var lastSyncDate: Date?
    var error: String?

    private let localDirectory: URL
    private let presignURL: (String, String) async throws -> URL  // (action: "put"|"get", key) -> URL
    private var manifest: SyncManifest
    private let manifestURL: URL

    init(localDirectory: URL, presignURL: @escaping (String, String) async throws -> URL) {
        self.localDirectory = localDirectory
        self.presignURL = presignURL
        self.manifestURL = localDirectory.appendingPathComponent(".sync-manifest.json")
        self.manifest = SyncManifest.load(from: localDirectory.appendingPathComponent(".sync-manifest.json"))
    }

    // MARK: - Push

    /// Push all files in a single subdirectory. Skips hidden files and unchanged files.
    /// Continues on single-file failure, saves manifest incrementally, and streams uploads from disk.
    func push(subdirectory: String) async throws {
        let dirURL = localDirectory.appendingPathComponent(subdirectory)
        let fm = FileManager.default

        guard fm.fileExists(atPath: dirURL.path) else { return }

        guard let contents = try? fm.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        var errors: [(String, Error)] = []

        for fileURL in contents {
            let filename = fileURL.lastPathComponent
            guard !filename.hasPrefix(".") else { continue }

            let relativePath = "\(subdirectory)/\(filename)"
            let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let localModified = attrs?.contentModificationDate ?? Date.distantPast
            let lastSynced = manifest.files[relativePath]

            if lastSynced == nil || localModified > lastSynced! {
                do {
                    let url = try await presignURL("put", relativePath)
                    var request = URLRequest(url: url)
                    request.httpMethod = "PUT"
                    request.setValue(Self.contentType(for: fileURL), forHTTPHeaderField: "Content-Type")
                    // Stream from disk — no memory allocation for large files
                    let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        throw FileSyncError.uploadFailed(relativePath)
                    }
                    manifest.files[relativePath] = localModified
                    manifest.save(to: manifestURL)
                    print("[FileSync] Pushed: \(relativePath)")
                } catch {
                    print("[FileSync] Failed to push: \(relativePath) — \(error)")
                    errors.append((relativePath, error))
                }
            } else {
                print("[FileSync] Skip (unchanged): \(relativePath)")
            }
        }

        if !errors.isEmpty {
            let failedFiles = errors.map(\.0).joined(separator: ", ")
            throw FileSyncError.uploadFailed("Multiple files failed: \(failedFiles)")
        }
    }

    /// Push a single file by its relative path (e.g. "index.json").
    func pushFile(relativePath: String, data: Data) async throws {
        let url = try await presignURL("put", relativePath)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(Self.contentType(for: URL(fileURLWithPath: relativePath)), forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FileSyncError.uploadFailed(relativePath)
        }
        manifest.files[relativePath] = Date()
        manifest.save(to: manifestURL)
        print("[FileSync] Pushed file: \(relativePath)")
    }

    // MARK: - Pull

    /// Pull specific files by their remote keys and write them into localDirectory.
    func pull(keys: [String]) async throws {
        let fm = FileManager.default

        for key in keys {
            let url = try await presignURL("get", key)
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw FileSyncError.downloadFailed(key)
            }
            let destURL = localDirectory.appendingPathComponent(key)
            let parentDir = destURL.deletingLastPathComponent()
            try? fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try data.write(to: destURL, options: .atomic)
            manifest.files[key] = Date()
            print("[FileSync] Pulled: \(key)")
        }

        manifest.save(to: manifestURL)
    }

    /// Download a single file by key and return its data (does not write to disk).
    func pullData(key: String) async throws -> Data {
        let url = try await presignURL("get", key)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FileSyncError.downloadFailed(key)
        }
        return data
    }

    // MARK: - Push All

    /// Push all subdirectories in the local directory. Skips hidden directories.
    func pushAll() async throws {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: localDirectory, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        for itemURL in contents {
            let name = itemURL.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            try await push(subdirectory: name)
        }
    }

    // MARK: - Sync All (bidirectional)

    /// Full bidirectional sync. Compares local and remote item lists, then pushes/pulls as needed.
    /// `localItems` and `remoteItems` are (id, lastModified) tuples representing subdirectories.
    /// The caller provides these indexes — FileSync does not fetch them.
    ///
    /// Returns lists of IDs that were pushed and pulled so the caller can act on them.
    @discardableResult
    func syncAll(
        localItems: [(id: String, lastModified: Date)],
        remoteItems: [(id: String, lastModified: Date)],
        subdirectoryPrefix: String = ""
    ) async throws -> (pushed: [String], pulled: [String]) {
        let localById = Dictionary(uniqueKeysWithValues: localItems.map { ($0.id, $0.lastModified) })
        let remoteById = Dictionary(uniqueKeysWithValues: remoteItems.map { ($0.id, $0.lastModified) })

        var pushed: [String] = []
        var pulled: [String] = []

        // Push local-newer and new-local items
        for (id, localDate) in localById {
            let subdir = subdirectoryPrefix.isEmpty ? id : "\(subdirectoryPrefix)/\(id)"
            if let remoteDate = remoteById[id] {
                if localDate > remoteDate {
                    try await push(subdirectory: subdir)
                    pushed.append(id)
                }
            } else {
                try await push(subdirectory: subdir)
                pushed.append(id)
            }
        }

        // Pull remote-newer and new-remote items (return IDs — caller handles deserialization)
        for (id, remoteDate) in remoteById {
            if let localDate = localById[id] {
                if remoteDate > localDate {
                    pulled.append(id)
                }
            } else {
                pulled.append(id)
            }
        }

        return (pushed, pulled)
    }

    // MARK: - Helpers

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "json": return "application/json"
        case "m4a":  return "audio/mp4"
        case "mp3":  return "audio/mpeg"
        case "wav":  return "audio/wav"
        case "txt":  return "text/plain"
        default:     return "application/octet-stream"
        }
    }
}

// MARK: - FileSyncError

enum FileSyncError: Error, LocalizedError {
    case uploadFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let key):   return "Failed to upload \(key)"
        case .downloadFailed(let key): return "Failed to download \(key)"
        }
    }

    var isDownloadFailed: Bool {
        if case .downloadFailed = self { return true }
        return false
    }
}
