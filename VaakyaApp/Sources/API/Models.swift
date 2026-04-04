import Foundation

// MARK: - Auth

struct UserInfo: Codable, Sendable, Identifiable {
    let id: String
    let email: String
    let name: String
    let provider: String
    let avatar_url: String?
}

// MARK: - Meeting

struct Meeting: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let title: String
    let started_at: String
    let ended_at: String?
    let duration_seconds: Int?
    let speaker_count: Int
    let transcript: String?
    let audio_url: String?
    let template: String?
    let ai_provider: String?
    let source: String?
    let participants_json: String?
    let created_at: String

    static func == (lhs: Meeting, rhs: Meeting) -> Bool {
        lhs.id == rhs.id
        && lhs.title == rhs.title
        && lhs.transcript == rhs.transcript
        && lhs.duration_seconds == rhs.duration_seconds
        && lhs.template == rhs.template
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: started_at) {
            let df = DateFormatter()
            df.dateFormat = "MMM d, h:mm a"
            return df.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: started_at) {
            let df = DateFormatter()
            df.dateFormat = "MMM d, h:mm a"
            return df.string(from: date)
        }
        return started_at
    }

    var durationFormatted: String {
        guard let dur = duration_seconds else { return "" }
        return "\(dur / 60) min"
    }
}

struct CreateMeetingRequest: Codable, Sendable {
    let title: String
    let started_at: String
    let speaker_count: Int
    let source: String?
    let participants_json: String?

    init(title: String, started_at: String, speaker_count: Int, source: String? = nil, participants_json: String? = nil) {
        self.title = title
        self.started_at = started_at
        self.speaker_count = speaker_count
        self.source = source
        self.participants_json = participants_json
    }
}

struct UpdateMeetingRequest: Codable, Sendable {
    let title: String?
    let transcript: String?
    let duration_seconds: Int?
    let template: String?
    let source: String?
    let participants_json: String?

    init(title: String? = nil, transcript: String? = nil, duration_seconds: Int? = nil, template: String? = nil, source: String? = nil, participants_json: String? = nil) {
        self.title = title
        self.transcript = transcript
        self.duration_seconds = duration_seconds
        self.template = template
        self.source = source
        self.participants_json = participants_json
    }
}

// MARK: - Block

struct Block: Codable, Sendable, Identifiable {
    let id: String
    let meeting_id: String
    let type: String          // summary, decision, action, quote
    let content: String
    let speaker: String?
    let timestamp_seconds: Int?
    let position: Int
    let is_checked: Bool
    let is_ai_generated: Bool
    let meta_text: String?
}

struct CreateBlockRequest: Codable, Sendable {
    let type: String
    let content: String
    let speaker: String?
    let position: Int
    let is_ai_generated: Bool
    let meta_text: String?
}

struct UpdateBlockRequest: Encodable, Sendable {
    let content: String?
    let is_checked: Bool?
    let position: Int?
    let speaker: String?
    let meta_text: String?

    // Only encode non-nil fields
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let content { try container.encode(content, forKey: .content) }
        if let is_checked { try container.encode(is_checked, forKey: .is_checked) }
        if let position { try container.encode(position, forKey: .position) }
        if let speaker { try container.encode(speaker, forKey: .speaker) }
        if let meta_text { try container.encode(meta_text, forKey: .meta_text) }
    }

    private enum CodingKeys: String, CodingKey {
        case content, is_checked, position, speaker, meta_text
    }
}

// MARK: - Enhance

struct EnhanceRequest: Codable, Sendable {
    let template: String
    let user_notes: String
}

struct EnhanceResponse: Codable, Sendable {
    let blocks: [Block]
    let re_enhanced: Bool
}

// MARK: - Share

struct ShareCreateRequest: Codable, Sendable {
    let meeting_id: String
    let expires_in_hours: Int
}

struct ShareResponse: Codable, Sendable {
    let token: String
    let url: String
    let expires_at: String?
}

struct SharedNoteView: Codable, Sendable {
    let meeting: Meeting
    let blocks: [Block]
}

// MARK: - Chat

struct ChatRequest: Codable, Sendable {
    let message: String
}

struct ChatResponse: Codable, Sendable {
    let response: String
    let sources: [String]?
}

// MARK: - Chat UI

struct ChatMessage: Identifiable, Sendable {
    let id: String
    let role: ChatRole
    let content: String
    let timestamp: Date
    let sources: [String]?

    init(role: ChatRole, content: String, sources: [String]? = nil) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.sources = sources
    }
}

enum ChatRole: Sendable {
    case user
    case assistant
}

// MARK: - Settings

struct SettingsUpdateRequest: Encodable, Sendable {
    var ai_provider: String?
    var openai_api_key: String?
    var anthropic_api_key: String?
    var ollama_model: String?
    var ollama_base_url: String?
    var default_template: String?
    var auto_enhance: Bool?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let ai_provider { try container.encode(ai_provider, forKey: .ai_provider) }
        if let openai_api_key { try container.encode(openai_api_key, forKey: .openai_api_key) }
        if let anthropic_api_key { try container.encode(anthropic_api_key, forKey: .anthropic_api_key) }
        if let ollama_model { try container.encode(ollama_model, forKey: .ollama_model) }
        if let ollama_base_url { try container.encode(ollama_base_url, forKey: .ollama_base_url) }
        if let default_template { try container.encode(default_template, forKey: .default_template) }
        if let auto_enhance { try container.encode(auto_enhance, forKey: .auto_enhance) }
    }

    private enum CodingKeys: String, CodingKey {
        case ai_provider, openai_api_key, anthropic_api_key, ollama_model, ollama_base_url, default_template, auto_enhance
    }
}

// MARK: - Whisper Models

struct WhisperModel: Codable, Sendable, Identifiable {
    let name: String
    let size_mb: Int
    let downloaded: Bool
    var id: String { name }
}

// MARK: - Speaker (local-only, not sent to server)

struct SpeakerInfo: Codable, Sendable, Identifiable {
    let id: String
    var label: String
    var color: String
    var talkTimeSeconds: Double
    var talkTimePercent: Double

    var talkTimeFormatted: String {
        let mins = Int(talkTimeSeconds) / 60
        let secs = Int(talkTimeSeconds) % 60
        return "\(mins)m \(secs)s"
    }
}
