import AuthenticationServices
import Foundation
import SwiftUI

@MainActor
@Observable
final class AuthViewModel: NSObject {
    var isLoading: Bool = false
    var errorMessage: String?
    var currentUser: UserInfo?
    var isLoggedIn: Bool = false

    /// The app works without login. This returns true when not signed in.
    var isAnonymous: Bool { !isLoggedIn }

    override init() {
        super.init()
        // Only set logged in if there's actually a token — non-blocking
        isLoggedIn = APIClient.shared.token != nil
    }

    // MARK: - Sign In with Apple

    func signInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    // MARK: - Sign In with Google (dev-mode placeholder)

    func signInWithGoogle() async {
        // In dev mode, send a UUID as identity_token so the backend auto-creates
        // a user without real Google OAuth verification.
        isLoading = true
        errorMessage = nil

        do {
            let _ = try await APIClient.shared.login(
                provider: "google",
                identityToken: UUID().uuidString,
                name: nil
            )
            currentUser = try await APIClient.shared.fetchMe()
            isLoggedIn = true
            Task { await SyncService.shared.pushAll(); SyncService.shared.startPeriodicSync() }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Token Refresh

    func refreshToken() async -> Bool {
        do {
            let _ = try await APIClient.shared.refreshTokens()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Session Check

    func checkSession() async {
        guard APIClient.shared.token != nil else { return }
        do {
            currentUser = try await APIClient.shared.fetchMe()
            isLoggedIn = true
            SyncService.shared.startPeriodicSync()
        } catch {
            // Access token may be expired — try refreshing
            let refreshed = await refreshToken()
            if refreshed {
                do {
                    currentUser = try await APIClient.shared.fetchMe()
                    isLoggedIn = true
                    return
                } catch {
                    // Refresh succeeded but /me still failed
                }
            }
            // Refresh also failed — force re-login
            logout()
        }
    }

    // MARK: - Logout

    func logout() {
        APIClient.shared.clearTokens()
        SyncService.shared.stopPeriodicSync()
        currentUser = nil
        isLoggedIn = false
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthViewModel: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            Task { @MainActor in
                self.errorMessage = "Failed to get Apple identity token"
                self.isLoading = false
            }
            return
        }

        // Apple only provides the name on the very first sign-in
        let fullName: String? = {
            if let givenName = credential.fullName?.givenName {
                if let familyName = credential.fullName?.familyName {
                    return "\(givenName) \(familyName)"
                }
                return givenName
            }
            return nil
        }()

        Task { @MainActor in
            self.isLoading = true
            self.errorMessage = nil
            do {
                let _ = try await APIClient.shared.login(
                    provider: "apple",
                    identityToken: identityToken,
                    name: fullName
                )
                self.currentUser = try await APIClient.shared.fetchMe()
                self.isLoggedIn = true
                Task { await SyncService.shared.pushAll(); SyncService.shared.startPeriodicSync() }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            if (error as? ASAuthorizationError)?.code == .canceled {
                // User cancelled — not an error
                return
            }
            self.errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
}
