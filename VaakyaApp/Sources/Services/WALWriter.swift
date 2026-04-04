// VaakyaApp/Sources/Services/WALWriter.swift
import Foundation

struct WALOperation: Codable {
    let timestamp: Date
    let operation: WALOperationType
    let meetingId: String
    let data: MeetingDocument?

    enum WALOperationType: String, Codable {
        case create
        case update
        case delete
    }
}

@MainActor
final class WALWriter {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("wal.jsonl")
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    /// Append one operation to the WAL. This is an atomic append — safe even if app crashes mid-write.
    func append(_ operation: WALOperation) throws {
        var data = try encoder.encode(operation)
        data.append(0x0A) // newline
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    /// Read all pending (unflushed) entries from the WAL.
    func pendingEntries() -> [WALOperation] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        let lines = data.split(separator: 0x0A)
        return lines.compactMap { line in
            try? decoder.decode(WALOperation.self, from: Data(line))
        }
    }

    /// Clear the WAL after a successful flush. Atomic — write empty then rename.
    func truncate() throws {
        try Data().write(to: fileURL, options: .atomic)
    }

    /// Whether there are any unflushed entries.
    var hasPendingEntries: Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        return !data.isEmpty
    }
}
