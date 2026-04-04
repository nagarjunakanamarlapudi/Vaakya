# Google Sign-In for Vaakya — Design Spec

**Date:** 2026-04-03
**Status:** Approved

## Goal

Replace the dev-mode placeholder (`skip_verification=true`, UUID as identity token) with real Google OAuth sign-in on both macOS and iOS using the Google Sign-In SDK.

## Approach

Use the official **Google Sign-In SDK** (`google/GoogleSignIn-iOS`) via SPM. The SDK handles the OAuth flow, presents the Google login UI, and returns a Google ID token. That token is sent to the existing backend `POST /auth/login` endpoint, which verifies it against Google's tokeninfo API and issues a JWT session.

### Why SDK over manual OAuth

- Officially supported by Google for iOS/macOS
- Handles token refresh, account switching, revocation edge cases
- ~30 lines of integration code vs ~150 for manual `ASWebAuthenticationSession` flow
- Backend `verify_google_id_token` already expects the ID token format the SDK produces

## Google Cloud Console (manual setup)

**Project:** Vaakya (`vaakya-492304`, project number `646777782566`)

### Already done
- OAuth consent screen configured (External, Testing mode)
- OAuth 2.0 Client ID (iOS type) created:
  - **Client ID:** `646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6.apps.googleusercontent.com`
  - **Reversed Client ID (URL scheme):** `com.googleusercontent.apps.646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6`
  - **Bundle ID:** `ai.vaakya.app`

### Still needed
- Enable **Google Calendar API** in APIs & Services > Library

## Scopes

Requested at sign-in time via the SDK:
- `openid` — identity verification
- `email` — user's email address
- `profile` — name and profile photo
- `https://www.googleapis.com/auth/calendar.readonly` — read-only calendar access (scope requested now, feature built later)

## Auth Flow

```
User taps "Sign In with Google"
    → SDK shows Google login (in-app browser)
    → User authenticates with Google
    → Google redirects back via URL scheme
    → SDK returns GIDGoogleUser with idToken
    → App sends idToken to POST /auth/login {provider: "google", identity_token: idToken}
    → Backend calls Google tokeninfo, validates audience matches google_client_id
    → Backend creates JWT (24h access, 7d refresh)
    → App stores tokens in Keychain
    → App calls GET /auth/me for user info
    → User is logged in, sync starts
```

## Changes

### 1. Backend — AWS SSM

Store real Google Client ID:
```
aws ssm put-parameter \
  --name /vaakya/stg/google-client-id \
  --value "646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6.apps.googleusercontent.com" \
  --type SecureString \
  --profile vaakya-dev \
  --region us-east-1
```

### 2. Backend — Config

**File:** `infra/config/stg.yaml`
- Set `skip_verification: false`
- Keep `skip_verification: true` in `dev.yaml` for local development without Google credentials

**No changes to `services/oauth.py`** — `verify_google_id_token` already works correctly. It calls Google's tokeninfo endpoint, checks audience matches `google_client_id`, and returns `{sub, email, name, avatar_url}`.

### 3. Swift — Dependencies

Add `google/GoogleSignIn-iOS` SPM package to:
- `Package.swift` (macOS builds)
- `project.yml` (iOS builds via xcodegen)

### 4. Swift — Info.plist / project.yml

Add to Info.plist (both platforms):
- **URL scheme:** `com.googleusercontent.apps.646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6`
- **GIDClientID:** `646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6.apps.googleusercontent.com`

For iOS, these are configured in `project.yml` which generates the Info.plist via xcodegen.

### 5. Swift — AuthViewModel.swift

Replace the UUID placeholder in `signInWithGoogle()` with real SDK flow:
- Configure `GIDSignIn` with the client ID
- Call `GIDSignIn.sharedInstance.signIn(withPresenting:)` with additional `calendar.readonly` scope
- Extract `idToken` from `GIDSignInResult.user.idToken.tokenString`
- Send to backend via existing `APIClient.login(provider: "google", identityToken: idToken)`
- Handle errors (user cancelled, network failure, etc.)

### 6. Swift — App Lifecycle (URL handling)

Add `onOpenURL` handler to pass the OAuth callback URL to the SDK:
```swift
.onOpenURL { url in
    GIDSignIn.sharedInstance.handle(url)
}
```

This goes in the main app entry point (`VaakyaApp.swift` or equivalent) so the SDK can complete the OAuth redirect flow.

## Files Modified

| File | Change |
|------|--------|
| `infra/config/stg.yaml` | `skip_verification: false` |
| `VaakyaApp/Package.swift` | Add GoogleSignIn-iOS dependency |
| `VaakyaApp/project.yml` | Add GoogleSignIn-iOS dependency, URL scheme, GIDClientID |
| `VaakyaApp/Sources/Resources/Info.plist` | URL scheme + GIDClientID (macOS) |
| `VaakyaApp/Sources/ViewModels/AuthViewModel.swift` | Real Google Sign-In SDK flow |
| `VaakyaApp/Sources/Views/LoginView.swift` | No changes (existing button is fine) |
| `VaakyaApp/Sources/App/VaakyaApp.swift` (or equivalent) | `onOpenURL` handler |

## Not in Scope

- Calendar feature (pull meetings from Google Calendar) — scope is requested but feature deferred
- Apple Sign-In — requires Apple Developer Program enrollment ($99/yr)
- Production deployment — staying on dev/stg
- Google consent screen verification / publishing — stays in Testing mode for now
