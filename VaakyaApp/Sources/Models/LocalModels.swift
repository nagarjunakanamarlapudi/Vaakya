// VaakyaApp/Sources/Models/LocalModels.swift
import Foundation

// MARK: - Meeting Document (full, stored as JSON file)

struct MeetingDocument: Codable, Identifiable, Sendable {
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
    var blocks: [BlockData]                                          // keep for backward compat
    var translatedTranscripts: [String: [TranscriptSegmentData]]     // NEW
    var enhancedBlocks: [String: [BlockData]]                        // NEW
    var notesLanguage: String?                                        // NEW
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
        self.translatedTranscripts = [:]
        self.enhancedBlocks = [:]
        self.notesLanguage = nil
        self.speakers = []
    }
}

extension MeetingDocument {
    enum CodingKeys: String, CodingKey {
        case id, title, startedAt, endedAt, durationSeconds, speakerCount, source
        case participants, template, aiProvider, isEnhanced, lastModified, userNotes
        case transcript, blocks, translatedTranscripts, enhancedBlocks, notesLanguage, speakers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        speakerCount = try c.decodeIfPresent(Int.self, forKey: .speakerCount) ?? 0
        source = try c.decodeIfPresent(String.self, forKey: .source)
        participants = try c.decodeIfPresent([Participant].self, forKey: .participants)
        template = try c.decodeIfPresent(String.self, forKey: .template)
        aiProvider = try c.decodeIfPresent(String.self, forKey: .aiProvider)
        isEnhanced = try c.decodeIfPresent(Bool.self, forKey: .isEnhanced) ?? false
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
        userNotes = try c.decodeIfPresent(String.self, forKey: .userNotes) ?? ""
        transcript = try c.decodeIfPresent([TranscriptSegmentData].self, forKey: .transcript) ?? []
        blocks = try c.decodeIfPresent([BlockData].self, forKey: .blocks) ?? []
        speakers = try c.decodeIfPresent([SpeakerData].self, forKey: .speakers) ?? []

        // New fields with migration
        translatedTranscripts = try c.decodeIfPresent([String: [TranscriptSegmentData]].self, forKey: .translatedTranscripts) ?? [:]
        notesLanguage = try c.decodeIfPresent(String.self, forKey: .notesLanguage)

        // Migrate: if old `blocks` exist but no `enhancedBlocks`, move them to enhancedBlocks["en"]
        let decoded = try c.decodeIfPresent([String: [BlockData]].self, forKey: .enhancedBlocks)
        if let decoded, !decoded.isEmpty {
            enhancedBlocks = decoded
        } else if !blocks.isEmpty {
            enhancedBlocks = ["en": blocks]
        } else {
            enhancedBlocks = [:]
        }
    }
}

extension MeetingDocument {
    /// Get blocks for the active notes language, falling back to the legacy `blocks` array.
    func activeBlocks(language: String? = nil) -> [BlockData] {
        let lang = language ?? notesLanguage ?? "en"
        return enhancedBlocks[lang] ?? blocks
    }

    /// Languages that have enhanced notes available.
    var availableNotesLanguages: [String] {
        Array(enhancedBlocks.keys).sorted()
    }

    /// Languages that have transcript translations available.
    var availableTranscriptLanguages: [String] {
        Array(translatedTranscripts.keys).sorted()
    }
}

// MARK: - Meeting Metadata (in-memory index, lightweight)

struct MeetingMetadata: Codable, Identifiable, Hashable, Sendable {
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
    var isPinned: Bool
    var pinSortOrder: Int?
    var project: String?
    var tags: [String]

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d, h:mm a"
        return df
    }()

    var formattedDate: String {
        Self.dateFormatter.string(from: startedAt)
    }

    var durationFormatted: String {
        guard let dur = durationSeconds else { return "" }
        return "\(dur / 60) min"
    }

    /// Build metadata from a document, optionally preserving sidebar-only fields from an existing entry.
    static func from(_ doc: MeetingDocument, hasAudio: Bool = false,
                     preserving existing: MeetingMetadata? = nil) -> MeetingMetadata {
        return from(doc, hasAudio: hasAudio,
                    isPinned: existing?.isPinned ?? false,
                    pinSortOrder: existing?.pinSortOrder,
                    project: existing?.project,
                    tags: existing?.tags ?? [])
    }

    static func from(_ doc: MeetingDocument, hasAudio: Bool = false,
                     isPinned: Bool = false, pinSortOrder: Int? = nil,
                     project: String? = nil, tags: [String] = []) -> MeetingMetadata {
        let activeBlocks = doc.activeBlocks()
        let blockCounts = Dictionary(grouping: activeBlocks, by: \.type)
            .mapValues { $0.count }
        let pending = activeBlocks.filter { $0.type == "action" && !$0.isChecked }.count
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
            hasAudio: hasAudio,
            isPinned: isPinned,
            pinSortOrder: pinSortOrder,
            project: project,
            tags: tags
        )
    }

    init(id: String, title: String, startedAt: Date, durationSeconds: Int? = nil,
         speakerCount: Int, source: String? = nil, participantNames: [String] = [],
         blockCounts: [String: Int] = [:], pendingActionItems: Int = 0,
         isEnhanced: Bool = false, lastModified: Date, hasAudio: Bool = false,
         isPinned: Bool = false, pinSortOrder: Int? = nil, project: String? = nil,
         tags: [String] = []) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.speakerCount = speakerCount
        self.source = source
        self.participantNames = participantNames
        self.blockCounts = blockCounts
        self.pendingActionItems = pendingActionItems
        self.isEnhanced = isEnhanced
        self.lastModified = lastModified
        self.hasAudio = hasAudio
        self.isPinned = isPinned
        self.pinSortOrder = pinSortOrder
        self.project = project
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        speakerCount = try c.decode(Int.self, forKey: .speakerCount)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        participantNames = try c.decodeIfPresent([String].self, forKey: .participantNames) ?? []
        blockCounts = try c.decodeIfPresent([String: Int].self, forKey: .blockCounts) ?? [:]
        pendingActionItems = try c.decodeIfPresent(Int.self, forKey: .pendingActionItems) ?? 0
        isEnhanced = try c.decodeIfPresent(Bool.self, forKey: .isEnhanced) ?? false
        lastModified = try c.decode(Date.self, forKey: .lastModified)
        hasAudio = try c.decodeIfPresent(Bool.self, forKey: .hasAudio) ?? false
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinSortOrder = try c.decodeIfPresent(Int.self, forKey: .pinSortOrder)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MeetingMetadata, rhs: MeetingMetadata) -> Bool {
        lhs.id == rhs.id && lhs.lastModified == rhs.lastModified
            && lhs.isPinned == rhs.isPinned && lhs.pinSortOrder == rhs.pinSortOrder
            && lhs.project == rhs.project && lhs.tags == rhs.tags
    }
}

// MARK: - Block

struct BlockData: Codable, Identifiable, Sendable {
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

struct TranscriptSegmentData: Codable, Identifiable, Sendable {
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

struct SpeakerData: Codable, Identifiable, Sendable {
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

struct Participant: Codable, Sendable {
    let name: String
    let email: String?
}

// MARK: - Local Settings

struct LocalSettings: Codable {
    var aiProvider: String = "ollama"
    var ollamaURL: String = "http://localhost:11434"
    var ollamaModel: String = "llama3.2"
    var defaultTemplate: String = "general"
    var autoEnhance: Bool = true
    var captureSystemAudio: Bool = false
    var syncOnCellular: Bool = false   // Default: sync only on Wi-Fi
    var launchAtLogin: Bool = false
    var autoStartRecording: Bool = false
    var notesLanguage: String = "en"      // Global default for enhanced notes language
}

// MARK: - Project Folder

struct ProjectFolder: Codable, Identifiable {
    let id: String
    var name: String
    var color: String  // hex, e.g. "#4285F4"
    var sortOrder: Int

    init(id: String = UUID().uuidString, name: String, color: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
    }

    static let presetColors: [(name: String, hex: String)] = [
        ("Green", "#34A853"), ("Blue", "#4285F4"), ("Red", "#EA4335"),
        ("Yellow", "#FBBC04"), ("Purple", "#9334E6"), ("Teal", "#00897B"),
    ]
}
