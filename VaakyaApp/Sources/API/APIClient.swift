import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "Please log in again."
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .decodingError(let msg): return "Parse error: \(msg)"
        case .networkError(let msg): return "Network: \(msg)"
        }
    }
}

/// APIClient is stripped down to only handle auth and share operations.
/// All CRUD (meetings, blocks, settings) is now handled by LocalStore.
/// All AI operations (enhance, chat) are handled by AIService.
actor APIClient {
    static let shared = APIClient()

    let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private static let accessTokenKey = "access_token"
    private static let refreshTokenKey = "refresh_token"

    /// Track whether a token refresh is already in flight to avoid concurrent refreshes.
    private var isRefreshing = false

    init(baseURL: String? = nil) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            #if DEBUG
            self.baseURL = BuildConfig.apiBaseURL
            #else
            self.baseURL = "https://api.vaakya.app"
            #endif
        }
        self.session = URLSession.shared
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Token (Keychain-backed)

    nonisolated var token: String? {
        KeychainService.load(key: APIClient.accessTokenKey)
    }

    nonisolated func setTokens(access: String, refresh: String) {
        KeychainService.save(key: APIClient.accessTokenKey, value: access)
        KeychainService.save(key: APIClient.refreshTokenKey, value: refresh)
    }

    nonisolated func clearTokens() {
        KeychainService.delete(key: APIClient.accessTokenKey)
        KeychainService.delete(key: APIClient.refreshTokenKey)
    }

    // MARK: - Request Helpers

    private func buildRequest(path: String, method: String, body: Data? = nil, auth: Bool = true) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let token = self.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        return req
    }

    private func perform<T: Decodable & Sendable>(_ req: URLRequest, allowRetry: Bool = true) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.networkError("Invalid response") }

        if http.statusCode == 401 && allowRetry {
            let refreshed = await attemptTokenRefresh()
            if refreshed {
                var retryReq = req
                if let newToken = self.token {
                    retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                }
                return try await perform(retryReq, allowRetry: false)
            }
            throw APIError.unauthorized
        }

        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.serverError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError("\(error)")
        }
    }

    private func performVoid(_ req: URLRequest, allowRetry: Bool = true) async throws {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.networkError("Invalid response") }

        if http.statusCode == 401 && allowRetry {
            let refreshed = await attemptTokenRefresh()
            if refreshed {
                var retryReq = req
                if let newToken = self.token {
                    retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                }
                try await performVoid(retryReq, allowRetry: false)
                return
            }
            throw APIError.unauthorized
        }

        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200...399).contains(http.statusCode) else {
            throw APIError.serverError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Token Refresh

    private func attemptTokenRefresh() async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let refreshToken = KeychainService.load(key: APIClient.refreshTokenKey) else {
            return false
        }

        do {
            let body = try encoder.encode(RefreshRequest(refresh_token: refreshToken))
            let req = try buildRequest(path: "/auth/refresh", method: "POST", body: body, auth: false)
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            let loginResp = try decoder.decode(LoginResponse.self, from: data)
            setTokens(access: loginResp.access_token, refresh: loginResp.refresh_token)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Auth

    func login(provider: String, identityToken: String, name: String?) async throws -> LoginResponse {
        let body = try encoder.encode(OAuthLoginRequest(
            provider: provider,
            identity_token: identityToken,
            name: name
        ))
        let req = try buildRequest(path: "/auth/login", method: "POST", body: body, auth: false)
        let resp: LoginResponse = try await perform(req, allowRetry: false)
        setTokens(access: resp.access_token, refresh: resp.refresh_token)
        return resp
    }

    func refreshTokens() async throws -> LoginResponse {
        guard let refreshToken = KeychainService.load(key: APIClient.refreshTokenKey) else {
            throw APIError.unauthorized
        }
        let body = try encoder.encode(RefreshRequest(refresh_token: refreshToken))
        let req = try buildRequest(path: "/auth/refresh", method: "POST", body: body, auth: false)
        let resp: LoginResponse = try await perform(req, allowRetry: false)
        setTokens(access: resp.access_token, refresh: resp.refresh_token)
        return resp
    }

    func fetchMe() async throws -> UserInfo {
        let req = try buildRequest(path: "/auth/me", method: "GET")
        return try await perform(req)
    }

    // MARK: - Share (requires server for token generation)

    func shareMeeting(id: String) async throws -> ShareResponse {
        let body = try encoder.encode(ShareCreateRequest(meeting_id: id, expires_in_hours: 72))
        let req = try buildRequest(path: "/share", method: "POST", body: body)
        return try await perform(req)
    }

    // MARK: - Server CRUD (kept for E2E tests and future sync; not used by main app)

    func fetchMeetings() async throws -> [Meeting] {
        let req = try buildRequest(path: "/meetings", method: "GET")
        return try await perform(req)
    }

    func createMeeting(title: String, source: String? = nil, participantsJson: String? = nil) async throws -> Meeting {
        let now = ISO8601DateFormatter().string(from: Date())
        let body = try encoder.encode(CreateMeetingRequest(
            title: title,
            started_at: now,
            speaker_count: 0,
            source: source,
            participants_json: participantsJson
        ))
        let req = try buildRequest(path: "/meetings", method: "POST", body: body)
        return try await perform(req)
    }

    func deleteMeeting(id: String) async throws {
        let req = try buildRequest(path: "/meetings/\(id)", method: "DELETE")
        try await performVoid(req)
    }

    func updateMeetingTranscript(id: String, transcript: String) async throws -> Meeting {
        let body = try encoder.encode(UpdateMeetingRequest(title: nil, transcript: transcript, duration_seconds: nil, template: nil))
        let req = try buildRequest(path: "/meetings/\(id)", method: "PATCH", body: body)
        return try await perform(req)
    }

    func fetchBlocks(meetingId: String) async throws -> [Block] {
        let req = try buildRequest(path: "/meetings/\(meetingId)/blocks", method: "GET")
        return try await perform(req)
    }

    func createBlock(meetingId: String, type: String, content: String, speaker: String? = nil, position: Int = 0) async throws -> Block {
        let body = try encoder.encode(CreateBlockRequest(type: type, content: content, speaker: speaker, position: position, is_ai_generated: false, meta_text: nil))
        let req = try buildRequest(path: "/meetings/\(meetingId)/blocks", method: "POST", body: body)
        return try await perform(req)
    }

    func updateBlock(meetingId: String, blockId: String, content: String? = nil, isChecked: Bool? = nil) async throws -> Block {
        let body = try encoder.encode(UpdateBlockRequest(content: content, is_checked: isChecked, position: nil, speaker: nil, meta_text: nil))
        let req = try buildRequest(path: "/meetings/\(meetingId)/blocks/\(blockId)", method: "PATCH", body: body)
        return try await perform(req)
    }

    func deleteBlock(meetingId: String, blockId: String) async throws {
        let req = try buildRequest(path: "/meetings/\(meetingId)/blocks/\(blockId)", method: "DELETE")
        try await performVoid(req)
    }

    func enhanceMeeting(id: String, template: String = "general", userNotes: String = "") async throws -> [Block] {
        let body = try encoder.encode(EnhanceRequest(template: template, user_notes: userNotes))
        let req = try buildRequest(path: "/meetings/\(id)/enhance", method: "POST", body: body)
        let resp: EnhanceResponse = try await perform(req)
        return resp.blocks
    }

    func chatMeeting(id: String, message: String) async throws -> ChatResponse {
        let body = try encoder.encode(ChatRequest(message: message))
        let req = try buildRequest(path: "/meetings/\(id)/chat", method: "POST", body: body)
        return try await perform(req)
    }

    func updateSettings(_ settings: SettingsUpdateRequest) async throws {
        let body = try encoder.encode(settings)
        let req = try buildRequest(path: "/settings", method: "PATCH", body: body)
        try await performVoid(req)
    }
}
