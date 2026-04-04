import AuthenticationServices
import CommonCrypto
import FirebaseAuth
import FirebaseCore
import Foundation
import SwiftUI

@MainActor
@Observable
final class AuthViewModel {
    var isLoading: Bool = false
    var errorMessage: String?
    var currentUser: UserInfo?
    var isLoggedIn: Bool = false

    var isAnonymous: Bool { !isLoggedIn }

    @ObservationIgnored private var _appleSignInDelegate: AppleSignInDelegate?
    private var appleSignInDelegate: AppleSignInDelegate {
        if let delegate = _appleSignInDelegate { return delegate }
        let delegate = AppleSignInDelegate(auth: self)
        _appleSignInDelegate = delegate
        return delegate
    }

    init() {
        // Check keychain — Firebase isn't configured yet at @State init time
        isLoggedIn = APIClient.shared.token != nil
    }

    // MARK: - Sign In with Apple

    func signInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = appleSignInDelegate
        controller.performRequests()
    }

    // MARK: - Sign In with Google (via ASWebAuthenticationSession + PKCE)

    func signInWithGoogle() {
        isLoading = true
        errorMessage = nil

        let clientID = BuildConfig.googleClientID
        let redirectScheme = "com.googleusercontent.apps.\(clientID.components(separatedBy: ".apps.googleusercontent.com").first ?? clientID)"
        let redirectURI = "\(redirectScheme):/oauth2redirect"

        // PKCE: generate code verifier and challenge
        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.generateCodeChallenge(from: codeVerifier)

        let scopes = "openid email profile https://www.googleapis.com/auth/calendar.readonly"
        let encodedScopes = scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes
        let encodedRedirectURI = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI

        let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth"
            + "?client_id=\(clientID)"
            + "&redirect_uri=\(encodedRedirectURI)"
            + "&response_type=code"
            + "&scope=\(encodedScopes)"
            + "&code_challenge=\(codeChallenge)"
            + "&code_challenge_method=S256"
            + "&access_type=offline"
        )!

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: redirectScheme) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    self.isLoading = false
                    return
                }
                if let error = error {
                    self.errorMessage = "Google Sign In failed: \(error.localizedDescription)"
                    self.isLoading = false
                    return
                }
                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    self.errorMessage = "Failed to get authorization code from Google"
                    self.isLoading = false
                    return
                }

                await self.exchangeCodeForToken(code: code, codeVerifier: codeVerifier, redirectURI: redirectURI)
            }
        }

        #if os(macOS)
        // macOS needs a presentation anchor but ASWebAuthenticationSession handles it
        session.presentationContextProvider = MacPresentationAnchor.shared
        #endif

        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    private func exchangeCodeForToken(code: String, codeVerifier: String, redirectURI: String) async {
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "code=\(code)"
            + "&client_id=\(BuildConfig.googleClientID)"
            + "&redirect_uri=\(redirectURI)"
            + "&grant_type=authorization_code"
            + "&code_verifier=\(codeVerifier)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let idToken = json["id_token"] as? String,
                  let accessToken = json["access_token"] as? String
            else {
                errorMessage = "Failed to get ID token from Google"
                isLoading = false
                return
            }

            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            let authResult = try await Auth.auth().signIn(with: credential)
            let firebaseToken = try await authResult.user.getIDToken()
            APIClient.shared.setToken(firebaseToken)
            currentUser = try await APIClient.shared.fetchMe()
            isLoggedIn = true
            Task { await SyncService.shared.pushAll(); SyncService.shared.startPeriodicSync() }
        } catch {
            errorMessage = "Google Sign In failed: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - PKCE Helpers

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Session Check

    func checkSession() async {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        do {
            let token = try await firebaseUser.getIDToken()
            APIClient.shared.setToken(token)
            currentUser = try await APIClient.shared.fetchMe()
            isLoggedIn = true
            SyncService.shared.startPeriodicSync()
        } catch {
            logout()
        }
    }

    // MARK: - Logout

    func logout() {
        try? Auth.auth().signOut()
        APIClient.shared.clearTokens()
        SyncService.shared.stopPeriodicSync()
        currentUser = nil
        isLoggedIn = false
    }
}

// MARK: - Base64 URL Encoding

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - macOS Presentation Anchor

#if os(macOS)
private class MacPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = MacPresentationAnchor()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
#endif

// MARK: - Apple Sign-In Delegate

private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private weak var auth: AuthViewModel?

    init(auth: AuthViewModel) {
        self.auth = auth
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            Task { @MainActor [weak self] in
                self?.auth?.errorMessage = "Failed to get Apple identity token"
                self?.auth?.isLoading = false
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let auth = self?.auth else { return }
            auth.isLoading = true
            auth.errorMessage = nil
            do {
                let credential = OAuthProvider.credential(providerID: .apple, idToken: identityToken, rawNonce: "")
                let authResult = try await Auth.auth().signIn(with: credential)
                let firebaseToken = try await authResult.user.getIDToken()
                APIClient.shared.setToken(firebaseToken)
                auth.currentUser = try await APIClient.shared.fetchMe()
                auth.isLoggedIn = true
                Task { await SyncService.shared.pushAll(); SyncService.shared.startPeriodicSync() }
            } catch {
                auth.errorMessage = error.localizedDescription
            }
            auth.isLoading = false
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            if (error as? ASAuthorizationError)?.code == .canceled {
                return
            }
            self?.auth?.errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
            self?.auth?.isLoading = false
        }
    }
}
