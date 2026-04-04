# Local-First Phase A — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all server-dependent CRUD with local filesystem storage (JSON files + in-memory index + WAL), client-side AI routing, and make the app work fully offline with zero server dependency.

**Architecture:** `LocalStore` (filesystem + memory index + WAL) replaces `APIClient` for all data operations. `AIService` routes enhance/chat directly to Ollama or AI provider APIs from the client. `AuthViewModel` makes login optional. Server is no longer needed for core app functionality.

**Tech Stack:** Swift, Foundation (FileManager, JSONEncoder/Decoder), Codable structs, URLSession (for AI provider calls)

**Spec:** `docs/superpowers/specs/2026-04-02-local-first-design.md`

---

## Execution Strategy

6 tasks, mostly sequential (each builds on the previous). Tasks 1-2 can be parallel.

```
Task 1: Data models (MeetingDocument, MeetingMetadata, etc.)  ──┐
Task 2: WALWriter                                               ├── parallel
Task 3: LocalStore (depends on 1 + 2)                         ──┘
Task 4: AIService (independent — can parallel with 3)
Task 5: ViewModel migration (depends on 3 + 4)
Task 6: App entry point + onboarding changes (depends on 5)
```

---

## File Structure

### New Files

```
VaakyaApp/Sources/
├── Models/
│   └── LocalModels.swift           # MeetingDocument, MeetingMetadata, BlockData, etc.
├── Services/
│   ├── LocalStore.swift            # Filesystem CRUD + in-memory index
│   ├── WALWriter.swift             # Append-only write-ahead log
│   ├── AIService.swift             # Client-side AI routing (Ollama/BYOK/Platform)
│   └── AIPrompts.swift             # Enhancement + chat prompt templates
```

### Modified Files

```
VaakyaApp/Sources/
├── ViewModels/
│   ├── MeetingViewModel.swift      # Replace APIClient calls with LocalStore
│   └── AuthViewModel.swift         # Make login optional
├── Views/
│   ├── VaakyaApp.swift             # Skip login, go straight to app
│   ├── OnboardingView.swift        # Remove login step
│   ├── ContextualSidebar.swift     # Chat via AIService
│   ├── SettingsView.swift          # Settings from local file
│   └── DashboardView.swift         # Stats from LocalStore
├── API/
│   ├── APIClient.swift             # Strip CRUD methods (keep auth + sync stubs)
│   └── Models.swift                # Keep for API-specific models, add LocalModels import
```

---

### Task 1: Local Data Models

**Files:**
- Create: `VaakyaApp/Sources/Models/LocalModels.swift`

All data types for local storage. These replace the server-dependent `Meeting`, `Block`, etc. from `API/Models.swift`.

- [ ] **Step 1: Create LocalModels.swift with all types**

```swift
// VaakyaApp/Sources/Models/LocalModels.swift
import Foundation

// MARK: - Meeting Document (full, stored as JSON file)

struct MeetingDocument: Codable, Identifiable {
    let id: String
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Int?
    var speakerCount: Int
    var source: String?
    var participants: [Participant]?
    var template: String?
    var aiProvider: String?
    var isEnhanced: Bool
    var lastModified: Date
    var userNotes: String

    var transcript: [TranscriptSegmentData]
    var blocks: [BlockData]
    var speakers: [SpeakerData]

    init(id: String = UUID().uuidString, title: String, startedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = nil
        self.durationSeconds = nil
        self.speakerCount = 0
        self.source = nil
        self.participants = nil
        self.template = nil
        self.aiProvider = nil
        self.isEnhanced = false
        self.lastModified = Date()
        self.userNotes = ""
        self.transcript = []
        self.blocks = []
        self.speakers = []
    }
}

// MARK: - Meeting Metadata (in-memory index, lightweight)

struct MeetingMetadata: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var startedAt: Date
    var durationSeconds: Int?
    var speakerCount: Int
    var source: String?
    var participantNames: [String]
    var blockCounts: [String: Int]
    var pendingActionItems: Int
    var isEnhanced: Bool
    var lastModified: Date
    var hasAudio: Bool

    var formattedDate: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, h:mm a"
        return df.string(from: startedAt)
    }

    var durationFormatted: String {
        guard let dur = durationSeconds else { return "" }
        return "\(dur / 60) min"
    }

    static func from(_ doc: MeetingDocument, hasAudio: Bool = false) -> MeetingMetadata {
        let blockCounts = Dictionary(grouping: doc.blocks, by: \.type)
            .mapValues { $0.count }
        let pending = doc.blocks.filter { $0.type == "action" && !$0.isChecked }.count
        return MeetingMetadata(
            id: doc.id,
            title: doc.title,
            startedAt: doc.startedAt,
            durationSeconds: doc.durationSeconds,
            speakerCount: doc.speakerCount,
            source: doc.source,
            participantNames: doc.participants?.map(\.name) ?? [],
            blockCounts: blockCounts,
            pendingActionItems: pending,
            isEnhanced: doc.isEnhanced,
            lastModified: doc.lastModified,
            hasAudio: hasAudio
        )
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MeetingMetadata, rhs: MeetingMetadata) -> Bool {
        lhs.id == rhs.id && lhs.lastModified == rhs.lastModified
    }
}

// MARK: - Block

struct BlockData: Codable, Identifiable {
    let id: String
    var type: String
    var content: String
    var speaker: String?
    var timestampSeconds: Int?
    var position: Int
    var isChecked: Bool
    var isAIGenerated: Bool
    var metaText: String?

    init(id: String = UUID().uuidString, type: String, content: String, speaker: String? = nil,
         position: Int = 0, isChecked: Bool = false, isAIGenerated: Bool = false, metaText: String? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.speaker = speaker
        self.timestampSeconds = nil
        self.position = position
        self.isChecked = isChecked
        self.isAIGenerated = isAIGenerated
        self.metaText = metaText
    }
}

// MARK: - Transcript Segment (stored in meeting document)

struct TranscriptSegmentData: Codable, Identifiable {
    let id: String
    var start: Double
    var end: Double
    var text: String
    var speaker: String?
    var isConfirmed: Bool

    init(id: String = UUID().uuidString, start: Double, end: Double, text: String,
         speaker: String? = nil, isConfirmed: Bool = true) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.isConfirmed = isConfirmed
    }

    var startFormatted: String {
        let mins = Int(start) / 60
        let secs = Int(start) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Speaker

struct SpeakerData: Codable, Identifiable {
    let id: String
    var label: String
    var color: String
    var talkTimeSeconds: Double

    init(id: String = UUID().uuidString, label: String, color: String, talkTimeSeconds: Double = 0) {
        self.id = id
        self.label = label
        self.color = color
        self.talkTimeSeconds = talkTimeSeconds
    }
}

// MARK: - Participant

struct Participant: Codable {
    let name: String
    let email: String?
}

// MARK: - Local Settings

struct LocalSettings: Codable {
    var aiProvider: String = "ollama"
    var openAIKey: String = ""
    var anthropicKey: String = ""
    var ollamaURL: String = "http://localhost:11434"
    var ollamaModel: String = "llama3.2"
    var defaultTemplate: String = "general"
    var autoEnhance: Bool = true
    var captureSystemAudio: Bool = false
    var launchAtLogin: Bool = false
    var autoStartRecording: Bool = false
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build
```

- [ ] **Step 3: Commit**

```bash
git add VaakyaApp/Sources/Models/LocalModels.swift
git commit -m "feat: local data models — MeetingDocument, MeetingMetadata, BlockData, etc."
```

---

### Task 2: WAL Writer

**Files:**
- Create: `VaakyaApp/Sources/Services/WALWriter.swift`

Append-only write-ahead log for crash safety. Each line is a JSON-encoded operation.

- [ ] **Step 1: Create WALWriter.swift**

```swift
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
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(data)
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
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build
```

- [ ] **Step 3: Commit**

```bash
git add VaakyaApp/Sources/Services/WALWriter.swift
git commit -m "feat: WALWriter — append-only write-ahead log for crash safety"
```

---

### Task 3: LocalStore

**Files:**
- Create: `VaakyaApp/Sources/Services/LocalStore.swift`

The core data layer. Manages filesystem, in-memory index, WAL, and flush cycle.

- [ ] **Step 1: Create LocalStore.swift**

```swift
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
    private let settingsURL: URL
    private let wal: WALWriter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var flushTimer: Timer?

    // In-memory cache of full documents for currently open meetings
    private var documentCache: [String: MeetingDocument] = [:]

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDirectory = appSupport.appendingPathComponent("Vaakya")
        meetingsDirectory = baseDirectory.appendingPathComponent("meetings")
        indexURL = baseDirectory.appendingPathComponent("index.json")
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
                    loadedMeetings.append(.from(doc, hasAudio: audioExists))
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
                    let meta = MeetingMetadata.from(doc)
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
        isInitialized = true
        print("[LocalStore] Initialized with \(meetings.count) meetings")

        // 4. Start periodic flush timer
        startFlushTimer()
    }

    // MARK: - Read

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
        try? wal.append(op)

        // Update in-memory
        documentCache[meeting.id] = meeting
        let meta = MeetingMetadata.from(meeting)
        meetings.insert(meta, at: 0)
    }

    /// Update an existing meeting.
    func updateMeeting(_ meeting: MeetingDocument) {
        var updated = meeting
        updated.lastModified = Date()

        // Write WAL
        let op = WALOperation(timestamp: Date(), operation: .update, meetingId: meeting.id, data: updated)
        try? wal.append(op)

        // Update in-memory
        documentCache[meeting.id] = updated
        let meta = MeetingMetadata.from(updated, hasAudio: audioURL(for: meeting.id) != nil)
        if let idx = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[idx] = meta
        }
    }

    /// Delete a meeting and its files.
    func deleteMeeting(id: String) {
        // Write WAL
        let op = WALOperation(timestamp: Date(), operation: .delete, meetingId: id, data: nil)
        try? wal.append(op)

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
        try? FileManager.default.copyItem(at: sourceURL, to: destURL)

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

    // MARK: - Flush (WAL → disk)

    /// Flush all pending WAL entries to disk.
    func flush() {
        let entries = wal.pendingEntries()
        guard !entries.isEmpty else { return }

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

        // Truncate WAL
        try? wal.truncate()
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
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build
```

- [ ] **Step 3: Commit**

```bash
git add VaakyaApp/Sources/Services/LocalStore.swift
git commit -m "feat: LocalStore — filesystem CRUD + in-memory index + WAL flush"
```

---

### Task 4: AIService — Client-Side AI Routing

**Files:**
- Create: `VaakyaApp/Sources/Services/AIService.swift`
- Create: `VaakyaApp/Sources/Services/AIPrompts.swift`

Calls AI providers directly from the client. No server needed for Ollama or BYOK.

- [ ] **Step 1: Create AIPrompts.swift**

Port the prompt templates from `src/vaakya/services/ai.py` to Swift.

```swift
// VaakyaApp/Sources/Services/AIPrompts.swift
import Foundation

enum AIPrompts {

    static func enhancePrompt(transcript: String, userNotes: String, template: String) -> String {
        """
        You are an AI meeting assistant. Analyze the following meeting transcript and user notes, \
        then produce structured meeting notes.

        Template: \(template)

        Transcript:
        \(transcript)

        User Notes:
        \(userNotes.isEmpty ? "(none)" : userNotes)

        Respond with a JSON array of blocks. Each block has:
        - "type": one of "summary", "decision", "action", "quote"
        - "content": the text content
        - "speaker": the speaker name if attributable (or null)
        - "meta_text": additional context (or null)

        For action items, make them specific and actionable.
        For decisions, state what was decided and by whom.
        For quotes, include notable or important statements verbatim.
        Provide exactly one summary block first.

        Respond ONLY with valid JSON. No markdown, no explanation.
        Example: [{"type":"summary","content":"...","speaker":null,"meta_text":null}]
        """
    }

    static func chatPrompt(transcript: String, message: String) -> String {
        """
        You are an AI assistant helping a user understand their meeting. \
        Answer the user's question based on the transcript below.

        Transcript:
        \(transcript)

        User's question: \(message)

        Respond concisely. Cite specific parts of the transcript when relevant.
        """
    }
}
```

- [ ] **Step 2: Create AIService.swift**

```swift
// VaakyaApp/Sources/Services/AIService.swift
import Foundation

@MainActor
@Observable
final class AIService {
    static let shared = AIService()

    var isProcessing = false
    var error: String?

    // MARK: - Enhance

    func enhance(transcript: [TranscriptSegmentData], userNotes: String, template: String,
                 settings: LocalSettings) async throws -> [BlockData] {
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        let transcriptText = transcript.map { seg in
            let speaker = seg.speaker.map { "[\($0)] " } ?? ""
            return "[\(seg.startFormatted)] \(speaker)\(seg.text)"
        }.joined(separator: "\n")

        let prompt = AIPrompts.enhancePrompt(transcript: transcriptText, userNotes: userNotes, template: template)

        let responseText: String
        switch settings.aiProvider {
        case "ollama":
            responseText = try await callOllama(prompt: prompt, settings: settings)
        case "openai":
            responseText = try await callOpenAI(prompt: prompt, apiKey: settings.openAIKey)
        case "anthropic":
            responseText = try await callAnthropic(prompt: prompt, apiKey: settings.anthropicKey)
        case "platform":
            responseText = try await callPlatform(prompt: prompt, endpoint: "enhance")
        default:
            throw AIServiceError.unknownProvider(settings.aiProvider)
        }

        return parseBlocks(from: responseText)
    }

    // MARK: - Chat

    func chat(transcript: [TranscriptSegmentData], message: String,
              settings: LocalSettings) async throws -> String {
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        let transcriptText = transcript.map { "[\($0.startFormatted)] \($0.text)" }.joined(separator: "\n")
        let prompt = AIPrompts.chatPrompt(transcript: transcriptText, message: message)

        switch settings.aiProvider {
        case "ollama":
            return try await callOllama(prompt: prompt, settings: settings)
        case "openai":
            return try await callOpenAI(prompt: prompt, apiKey: settings.openAIKey)
        case "anthropic":
            return try await callAnthropic(prompt: prompt, apiKey: settings.anthropicKey)
        case "platform":
            return try await callPlatform(prompt: prompt, endpoint: "chat")
        default:
            throw AIServiceError.unknownProvider(settings.aiProvider)
        }
    }

    // MARK: - Provider Calls

    private func callOllama(prompt: String, settings: LocalSettings) async throws -> String {
        let url = URL(string: "\(settings.ollamaURL)/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": settings.ollamaModel,
            "prompt": prompt,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw AIServiceError.providerError("Ollama returned non-200")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw AIServiceError.invalidResponse
        }
        return responseText
    }

    private func callOpenAI(prompt: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey("OpenAI") }
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.3
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw AIServiceError.providerError("OpenAI returned non-200")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.invalidResponse
        }
        return content
    }

    private func callAnthropic(prompt: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.missingAPIKey("Anthropic") }
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw AIServiceError.providerError("Anthropic returned non-200")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw AIServiceError.invalidResponse
        }
        return text
    }

    private func callPlatform(prompt: String, endpoint: String) async throws -> String {
        // Platform AI goes through our Lambda — requires auth token
        // This is the only path that needs the server
        guard let token = KeychainService.load(key: "access_token") else {
            throw AIServiceError.notSignedIn
        }
        let baseURL = APIClient.shared.baseURL
        let url = URL(string: "\(baseURL)/\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let body: [String: Any] = ["prompt": prompt]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw AIServiceError.providerError("Platform returned non-200")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw AIServiceError.invalidResponse
        }
        return responseText
    }

    // MARK: - Parse

    private func parseBlocks(from text: String) -> [BlockData] {
        // Extract JSON array from response (may be wrapped in markdown code blocks)
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```") {
            // Strip markdown code fence
            let lines = jsonString.components(separatedBy: "\n")
            jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = jsonString.data(using: .utf8),
              let rawBlocks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // Return single summary block with raw text as fallback
            return [BlockData(type: "summary", content: text, isAIGenerated: true)]
        }
        return rawBlocks.enumerated().map { index, raw in
            BlockData(
                type: raw["type"] as? String ?? "summary",
                content: raw["content"] as? String ?? "",
                speaker: raw["speaker"] as? String,
                position: index,
                isAIGenerated: true,
                metaText: raw["meta_text"] as? String
            )
        }
    }

    // MARK: - Errors

    enum AIServiceError: Error, LocalizedError {
        case unknownProvider(String)
        case missingAPIKey(String)
        case providerError(String)
        case invalidResponse
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .unknownProvider(let p): return "Unknown AI provider: \(p)"
            case .missingAPIKey(let p): return "No API key configured for \(p). Add it in Settings."
            case .providerError(let msg): return msg
            case .invalidResponse: return "Invalid response from AI provider"
            case .notSignedIn: return "Sign in to use Platform AI"
            }
        }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build
```

- [ ] **Step 4: Commit**

```bash
git add VaakyaApp/Sources/Services/AIService.swift VaakyaApp/Sources/Services/AIPrompts.swift
git commit -m "feat: AIService — client-side AI routing for Ollama, OpenAI, Anthropic, Platform"
```

---

### Task 5: ViewModel Migration

**Files:**
- Modify: `VaakyaApp/Sources/ViewModels/MeetingViewModel.swift`
- Modify: `VaakyaApp/Sources/ViewModels/AuthViewModel.swift`
- Modify: `VaakyaApp/Sources/Views/ContextualSidebar.swift`
- Modify: `VaakyaApp/Sources/Views/SettingsView.swift`
- Modify: `VaakyaApp/Sources/Views/DashboardView.swift`

Replace all `APIClient` CRUD calls with `LocalStore` and `AIService`.

- [ ] **Step 1: Rewrite MeetingViewModel**

The entire MeetingViewModel needs to be rewritten. Every method currently calls `APIClient.shared.*` — replace with `LocalStore.shared.*` and `AIService.shared.*`.

Key changes:
- `fetchMeetings()` → `LocalStore.shared.meetings` (already in memory, no async needed)
- `createMeeting(title:)` → `LocalStore.shared.createMeeting(MeetingDocument(title:))`
- `deleteMeeting(id:)` → `LocalStore.shared.deleteMeeting(id:)`
- `enhanceMeeting(id:userNotes:)` → load doc from LocalStore, call `AIService.shared.enhance()`, save blocks back to doc via LocalStore
- `shareMeeting(id:)` → only works when signed in (calls APIClient for share token)
- `updateTitle(id:title:)` → load doc, update title, `LocalStore.shared.updateMeeting()`
- `toggleBlockCheck(id:blockId:)` → load doc, toggle check, update via LocalStore
- `chat(meetingId:message:)` → load doc transcript, call `AIService.shared.chat()`

Read `VaakyaApp/Sources/ViewModels/MeetingViewModel.swift` fully, then rewrite every method to use LocalStore + AIService. The ViewModel should NOT import or use `APIClient` at all for data operations.

The `selectedMeeting` property changes from `Meeting?` (API model) to `MeetingDocument?` (local model). This will require updating all views that reference `selectedMeeting` — but since `MeetingDocument` has the same fields (title, startedAt, blocks, transcript, etc.), the changes are mostly type renames.

**For blocks:** Currently blocks are fetched separately via `fetchBlocks(meetingId:)`. In the local model, blocks are embedded in `MeetingDocument.blocks`. So `fetchBlocks` becomes just `selectedMeeting?.blocks`.

**For transcription/diarization:** The existing `TranscriptionService` and `DiarizationService` produce `TranscriptSegment` and `Speaker` types. After processing, convert these to `TranscriptSegmentData` and `SpeakerData` and save into the `MeetingDocument`.

- [ ] **Step 2: Update AuthViewModel — make login optional**

Currently `AuthViewModel.checkSession()` verifies the JWT on launch. In local-first mode:
- `isLoggedIn` defaults to `false` but the app works regardless
- `checkSession()` only runs if there's a token in Keychain
- Login is only needed for: sync, share links, platform AI
- Add `isAnonymous` computed property: `!isLoggedIn`

- [ ] **Step 3: Update ContextualSidebar — chat via AIService**

Replace `APIClient.shared.chatMeeting()` with `AIService.shared.chat()`. Load the transcript from the current meeting document (LocalStore), pass to AIService.

- [ ] **Step 4: Update SettingsView — local settings**

Replace all `APIClient.shared.fetchSettings()` / `updateSettings()` calls with `LocalStore.shared.loadSettings()` / `saveSettings()`. Settings are read/written from `settings.json` locally.

- [ ] **Step 5: Update DashboardView — stats from LocalStore**

Replace computed stats (which currently call into MeetingViewModel which calls API) with direct `LocalStore.shared` properties: `meetingsThisWeek`, `totalCapturedSeconds`, `pendingActionItems`, `aiEnhancedCount`.

- [ ] **Step 6: Verify build**

```bash
cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build
```

This will likely produce many type errors since views reference the old `Meeting` and `Block` types. Fix each one by updating to `MeetingDocument`, `MeetingMetadata`, `BlockData`, etc. The fields are the same — it's mostly renaming.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: migrate ViewModels from APIClient to LocalStore + AIService"
```

---

### Task 6: App Entry Point + Onboarding Changes

**Files:**
- Modify: `VaakyaApp/Sources/VaakyaApp.swift`
- Modify: `VaakyaApp/Sources/Views/OnboardingView.swift`
- Modify: `VaakyaApp/Sources/Views/MainView.swift`

Make the app launch without login. Initialize LocalStore on startup.

- [ ] **Step 1: Update VaakyaApp.swift**

The current flow: launch → check auth → login screen → main app.
New flow: launch → initialize LocalStore → onboarding (first time) → dashboard.

```swift
// Key changes in VaakyaApp body:
WindowGroup {
    Group {
        if !localStore.isInitialized {
            // Loading screen while LocalStore initializes
            ProgressView("Loading...")
        } else if !onboardingComplete {
            OnboardingView { onboardingComplete = true }
        } else {
            MainView()
                .environment(auth)
        }
    }
    .environment(themeManager)
    .preferredColorScheme(themeManager.resolvedColorScheme)
    .task {
        await LocalStore.shared.initialize()
        // Check auth status (non-blocking, optional)
        await auth.checkSession()
    }
}
```

Remove the `if auth.isLoggedIn` gate. The app works regardless of auth status.

Add `LocalStore.shared.shutdown()` to `applicationWillTerminate`.

- [ ] **Step 2: Update OnboardingView — remove login step**

The onboarding flow currently starts with login. Remove that step. Onboarding is now:
1. Welcome
2. Permissions (mic, system audio, calendar)
3. Model download
4. Quick tour
5. Done → dashboard

Login becomes an optional action in Settings: "Sign in to sync across devices."

- [ ] **Step 3: Update MainView — initialize from LocalStore**

The MainView currently passes a `MeetingViewModel` that fetches from API on appear. Update it to use `LocalStore.shared.meetings` for the sidebar list. The `MeetingViewModel` should call `LocalStore.shared.initialize()` on appear if not already initialized.

- [ ] **Step 4: Verify the full app flow**

```bash
cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build
```

The app should now:
1. Launch without login
2. Show onboarding (first time)
3. Show dashboard with empty stats
4. Allow creating meetings, recording, transcribing, enhancing — all offline
5. No server calls for any core functionality

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: local-first app entry — no login required, LocalStore initialization"
```

---

## Verification Checklist

After all 6 tasks are complete:

- [ ] App launches without backend running — no errors, no login screen
- [ ] Create a meeting → shows in sidebar
- [ ] Record → transcript appears (WhisperKit)
- [ ] Enhance with Ollama → blocks appear
- [ ] Edit a block → change persists after app restart
- [ ] Delete a meeting → gone from sidebar and filesystem
- [ ] Dashboard stats update correctly
- [ ] Settings save/load from `settings.json`
- [ ] Kill the app mid-recording → WAL recovers on next launch
- [ ] `ls ~/Library/Application\ Support/Vaakya/meetings/` shows meeting directories
- [ ] No `APIClient` calls for any of the above (check with network proxy or by stopping backend)

---

## File Ownership (No Conflicts for Parallel Tasks)

| File | Task |
|---|---|
| `Models/LocalModels.swift` | 1 |
| `Services/WALWriter.swift` | 2 |
| `Services/LocalStore.swift` | 3 |
| `Services/AIService.swift` | 4 |
| `Services/AIPrompts.swift` | 4 |
| `ViewModels/MeetingViewModel.swift` | 5 |
| `ViewModels/AuthViewModel.swift` | 5 |
| `Views/ContextualSidebar.swift` | 5 |
| `Views/SettingsView.swift` | 5 |
| `Views/DashboardView.swift` | 5 |
| `VaakyaApp.swift` | 6 |
| `Views/OnboardingView.swift` | 6 |
| `Views/MainView.swift` | 6 |
