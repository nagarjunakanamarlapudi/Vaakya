# Google Sign-In for Vaakya — Design Spec

**Date:** 2026-04-03 (updated 2026-04-05)
**Status:** Implemented

## Goal

Replace the dev-mode placeholder (`skip_verification=true`, UUID as identity token) with real Google OAuth sign-in on both macOS and iOS, backed by Firebase Auth for user management.

## Approach

**ASWebAuthenticationSession + PKCE** for the OAuth flow (Apple's native API, no third-party SDK). After obtaining Google tokens, sign into **Firebase Auth** with a credential — Firebase creates/manages the user and issues ID tokens. **API Gateway JWT Authorizer** verifies Firebase tokens at the gateway level — no auth code in Lambda.

### Why this approach

- GoogleSignIn-iOS SDK was incompatible with SPM executable builds (ObjC class loading crash)
- Switched macOS builds from SPM to xcodegen + xcodebuild to support ObjC frameworks (Firebase SDK)
- Firebase Auth gives: user dashboard, email dedup across providers, auto token refresh, path to Facebook + Phone OTP later
- ASWebAuthenticationSession works on both macOS and iOS with zero dependencies
- API Gateway JWT Authorizer verifies tokens natively — no auth code in Lambda

## Firebase Project

- **Project ID:** `vaakya-a5abf`
- **Project number:** `300782895784`
- **OAuth Client ID:** `300782895784-nvqvp3daoj5qko6q7st6rm79dhhd31bp.apps.googleusercontent.com`
- **Bundle ID:** `ai.vaakya.app`
- **Auth providers enabled:** Google, Apple

## Scopes

Requested at sign-in time:
- `openid` — identity verification
- `email` — user's email address
- `profile` — name and profile photo
- `https://www.googleapis.com/auth/calendar.readonly` — read-only calendar access (scope requested now, feature built later)

## Auth Flow

```
User taps "Sign In with Google"
    → ASWebAuthenticationSession opens Google OAuth (PKCE)
    → User authenticates with Google
    → Google redirects back via URL scheme with auth code
    → App exchanges code for id_token + access_token (Google token endpoint)
    → App creates GoogleAuthProvider.credential(withIDToken:accessToken:)
    → Firebase Auth signs in with credential → creates/links user
    → App gets Firebase ID token (auto-refreshed every ~55 min)
    → App sends Firebase ID token as Bearer token to API
    → API Gateway JWT Authorizer verifies (issuer: securetoken.google.com/vaakya-a5abf)
    → Lambda reads claims from event.requestContext.authorizer.jwt.claims
    → /auth/me returns user info (email, name, provider from Firebase claims)
```

## Architecture

### Client (Swift)
- `AuthViewModel.swift` — ASWebAuthenticationSession + PKCE → Firebase credential sign-in
- `APIClient.swift` — Bearer token from Firebase, auto-refresh via `getIDToken(forcingRefresh:)` on 401
- `VaakyaApp.swift` — `FirebaseApp.configure()` in AppDelegate (macOS) / .task (iOS)
- `GoogleService-Info.plist` — Firebase config (project vaakya-a5abf)

### Backend (Python)
- `deps.py` — reads Firebase JWT claims from API Gateway authorizer context; dev mode uses `skip_verification`
- `routers/auth.py` — only `/auth/me` endpoint; reads `sub`, `email`, `name`, `picture`, `firebase.sign_in_provider` from claims
- `services/oauth.py` — **deleted** (Firebase handles verification)

### Infrastructure (Terraform)
- API Gateway JWT Authorizer: issuer `https://securetoken.google.com/vaakya-a5abf`, audience `vaakya-a5abf`
- `$default` route requires JWT auth
- Public routes (no auth): `GET /health`, `GET /share/{token}`
- SSM: only `share-secret` and AI keys remain (auth secrets deleted)

## Build System

macOS switched from `swift build` (SPM executable) to `xcodegen + xcodebuild`:
- SPM executables can't load ObjC frameworks (Firebase SDK)
- `project.yml` defines both iOS and macOS targets
- `make build` runs `xcodegen generate && xcodebuild`
- Proper code signing with Keychain Sharing entitlement (required by Firebase on macOS)
- `DEVELOPMENT_TEAM: WBKK5SBPY7`

## Login Providers (Phased)

- **Phase 1 (done):** Google Sign-In
- **Phase 2 (next):** Apple Sign-In (requires Apple Developer Program enrollment)
- **Phase 3 (later):** Facebook, Phone + OTP

## Not in Scope

- Calendar feature (pull meetings from Google Calendar) — scope requested but feature deferred
- Production deployment — staying on dev/stg
- Google consent screen verification / publishing — stays in Testing mode
