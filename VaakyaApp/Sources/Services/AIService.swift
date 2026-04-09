// VaakyaApp/Sources/Services/AIService.swift
import Foundation

@MainActor
@Observable
final class AIService {
    static let shared = AIService()

    var isProcessing = false
    var error: String?

    private static var platformBaseURL: String {
        #if DEBUG
        return BuildConfig.apiBaseURL
        #else
        return "https://api.vaakya.app"
        #endif
    }

    // MARK: - Enhance

    func enhance(transcript: [TranscriptSegmentData], userNotes: String, template: String,
                 settings: LocalSettings, language: String = "en") async throws -> [BlockData] {
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        let transcriptText = transcript.map { seg in
            let speaker = seg.speaker.map { "[\($0)] " } ?? ""
            return "[\(seg.startFormatted)] \(speaker)\(seg.text)"
        }.joined(separator: "\n")

        let prompt = AIPrompts.enhancePrompt(transcript: transcriptText, userNotes: userNotes, template: template, language: language)

        let responseText: String
        switch settings.aiProvider {
        case "ollama":
            responseText = try await callOllama(prompt: prompt, settings: settings)
        case "openai":
            let openAIKey = KeychainService.load(key: "vaakya_openai_key") ?? ""
            responseText = try await callOpenAI(prompt: prompt, apiKey: openAIKey)
        case "anthropic":
            let anthropicKey = KeychainService.load(key: "vaakya_anthropic_key") ?? ""
            responseText = try await callAnthropic(prompt: prompt, apiKey: anthropicKey)
        case "platform":
            responseText = try await callPlatform(prompt: prompt, endpoint: "enhance")
        default:
            throw AIServiceError.unknownProvider(settings.aiProvider)
        }

        return parseBlocks(from: responseText)
    }

    // MARK: - Chat

    func chat(transcript: [TranscriptSegmentData], message: String,
              settings: LocalSettings, language: String = "en") async throws -> String {
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        let transcriptText = transcript.map { "[\($0.startFormatted)] \($0.text)" }.joined(separator: "\n")
        let prompt = AIPrompts.chatPrompt(transcript: transcriptText, message: message, language: language)

        switch settings.aiProvider {
        case "ollama":
            return try await callOllama(prompt: prompt, settings: settings)
        case "openai":
            let openAIKey = KeychainService.load(key: "vaakya_openai_key") ?? ""
            return try await callOpenAI(prompt: prompt, apiKey: openAIKey)
        case "anthropic":
            let anthropicKey = KeychainService.load(key: "vaakya_anthropic_key") ?? ""
            return try await callAnthropic(prompt: prompt, apiKey: anthropicKey)
        case "platform":
            return try await callPlatform(prompt: prompt, endpoint: "chat")
        default:
            throw AIServiceError.unknownProvider(settings.aiProvider)
        }
    }

    // MARK: - Translate

    func translateTranscript(transcript: [TranscriptSegmentData], targetLanguage: String,
                             settings: LocalSettings) async throws -> [TranscriptSegmentData] {
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        let transcriptText = transcript.map { seg in
            let speaker = seg.speaker.map { "[\($0)] " } ?? ""
            let speakerLabel = seg.speaker ?? ""
            return "{\"start\": \(seg.start), \"end\": \(seg.end), \"text\": \"\(speaker)\(seg.text)\", \"speaker\": \"\(speakerLabel)\"}"
        }.joined(separator: ",\n")

        let prompt = AIPrompts.translatePrompt(transcript: "[\n\(transcriptText)\n]", language: targetLanguage)

        let responseText: String
        switch settings.aiProvider {
        case "ollama":
            responseText = try await callOllama(prompt: prompt, settings: settings)
        case "openai":
            let key = KeychainService.load(key: "vaakya_openai_key") ?? ""
            responseText = try await callOpenAI(prompt: prompt, apiKey: key)
        case "anthropic":
            let key = KeychainService.load(key: "vaakya_anthropic_key") ?? ""
            responseText = try await callAnthropic(prompt: prompt, apiKey: key)
        case "platform":
            responseText = try await callPlatform(prompt: prompt, endpoint: "enhance")
        default:
            throw AIServiceError.unknownProvider(settings.aiProvider)
        }

        return try parseTranscriptSegments(from: responseText, originalSegments: transcript)
    }

    private func parseTranscriptSegments(from text: String, originalSegments: [TranscriptSegmentData]) throws -> [TranscriptSegmentData] {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: "\n")
            jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        if let rangeStart = jsonString.range(of: "["),
           let rangeEnd = jsonString.range(of: "]", options: .backwards) {
            jsonString = String(jsonString[rangeStart.lowerBound...rangeEnd.lowerBound])
        }

        guard let data = jsonString.data(using: .utf8),
              let rawSegments = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("[AIService] Failed to parse translation JSON, response was: \(text.prefix(300))")
            throw AIServiceError.invalidResponse
        }

        return rawSegments.enumerated().map { index, raw in
            let original = index < originalSegments.count ? originalSegments[index] : nil
            return TranscriptSegmentData(
                id: original?.id ?? UUID().uuidString,
                start: raw["start"] as? Double ?? original?.start ?? 0,
                end: raw["end"] as? Double ?? original?.end ?? 0,
                text: raw["text"] as? String ?? "",
                speaker: raw["speaker"] as? String ?? original?.speaker,
                isConfirmed: true
            )
        }
    }

    // MARK: - Provider Calls

    private func callOllama(prompt: String, settings: LocalSettings) async throws -> String {
        guard let url = URL(string: "\(settings.ollamaURL)/api/generate") else {
            throw AIServiceError.providerError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300  // 5 min — large models on long transcripts need time

        let body: [String: Any] = [
            "model": settings.ollamaModel,
            "prompt": prompt,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[AIService] Ollama request: model=\(settings.ollamaModel) url=\(settings.ollamaURL) prompt_length=\(prompt.count)")
        let startTime = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            print("[AIService] Ollama request failed after \(String(format: "%.1f", elapsed))s: \(error)")
            throw AIServiceError.providerError("Ollama request failed: \(error.localizedDescription)")
        }
        let elapsed = Date().timeIntervalSince(startTime)
        print("[AIService] Ollama responded in \(String(format: "%.1f", elapsed))s, data=\(data.count) bytes")
        guard let httpResp = response as? HTTPURLResponse else {
            throw AIServiceError.providerError("Ollama: no HTTP response")
        }
        if httpResp.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[AIService] Ollama error: status=\(httpResp.statusCode) body=\(body)")
            throw AIServiceError.providerError("Ollama returned \(httpResp.statusCode): \(body)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            print("[AIService] Ollama: invalid response JSON")
            throw AIServiceError.invalidResponse
        }
        print("[AIService] Ollama response: \(responseText.prefix(200))...")
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
            "model": "claude-sonnet-4-6-20250514",
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
        guard let token = KeychainService.load(key: "access_token") else {
            throw AIServiceError.notSignedIn
        }
        let baseURL = Self.platformBaseURL
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw AIServiceError.providerError("Invalid URL")
        }
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

        // Try to find a JSON array in the text
        if let rangeStart = jsonString.range(of: "["),
           let rangeEnd = jsonString.range(of: "]", options: .backwards) {
            jsonString = String(jsonString[rangeStart.lowerBound...rangeEnd.lowerBound])
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
