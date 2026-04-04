# Google Sign-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dev-mode Google Sign-In placeholder with real Google OAuth using the Google Sign-In SDK on both macOS and iOS.

**Architecture:** The Google Sign-In SDK handles the OAuth flow client-side, returning a Google ID token. That token is sent to the existing `POST /auth/login` endpoint, which verifies it via Google's tokeninfo API and issues a JWT. No new backend endpoints or database changes.

**Tech Stack:** Google Sign-In SDK (SPM), SwiftUI, FastAPI backend (unchanged except config)

**Spec:** `docs/superpowers/specs/2026-04-03-google-signin-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `infra/config/stg.yaml` | Modify | Disable skip_verification for staging |
| `VaakyaApp/Package.swift` | Modify | Add GoogleSignIn-iOS SPM dependency (macOS) |
| `VaakyaApp/project.yml` | Modify | Add GoogleSignIn-iOS dependency, URL scheme, GIDClientID (iOS) |
| `VaakyaApp/Sources/Resources/Info.plist` | Modify | Add URL scheme + GIDClientID (macOS SPM builds) |
| `VaakyaApp/Sources/ViewModels/AuthViewModel.swift` | Modify | Replace UUID placeholder with real SDK sign-in flow |
| `VaakyaApp/Sources/VaakyaApp.swift` | Modify | Add `onOpenURL` handler for OAuth callback |

---

### Task 1: Backend — Disable skip_verification for staging

**Files:**
- Modify: `infra/config/stg.yaml:8`

- [ ] **Step 1: Update stg.yaml**

Change line 8 from:
```yaml
  skip_verification: true  # TEMPORARY — for testing. Revert to false before real users.
```
to:
```yaml
  skip_verification: false
```

- [ ] **Step 2: Verify dev.yaml still has skip_verification: true**

Read `infra/config/dev.yaml` and confirm line 13 still says `skip_verification: true`. Do NOT change this — local dev needs it.

- [ ] **Step 3: Commit**

```bash
git add infra/config/stg.yaml
git commit -m "config: disable skip_verification for staging auth"
```

---

### Task 2: Backend — Store Google Client ID in SSM

This is a **manual step** — the user runs this CLI command. Do not automate it.

- [ ] **Step 1: Store the client ID in SSM**

The user must run:
```bash
aws ssm put-parameter \
  --name /vaakya/stg/google-client-id \
  --value "646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6.apps.googleusercontent.com" \
  --type SecureString \
  --profile vaakya-dev \
  --region us-east-1
```

- [ ] **Step 2: Verify it was stored**

```bash
aws ssm get-parameter \
  --name /vaakya/stg/google-client-id \
  --with-decryption \
  --profile vaakya-dev \
  --region us-east-1 \
  --query 'Parameter.Value' \
  --output text
```

Expected output: `646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6.apps.googleusercontent.com`

---

### Task 3: Swift — Add GoogleSignIn-iOS SPM dependency

**Files:**
- Modify: `VaakyaApp/Package.swift`
- Modify: `VaakyaApp/project.yml`

- [ ] **Step 1: Add dependency to Package.swift (macOS)**

In `VaakyaApp/Package.swift`, add the GoogleSignIn-iOS package to the `dependencies` array:

```swift
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.18.0"),
    .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.17.0"),
    .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "8.0.0"),
],
```

And add `GoogleSignIn` to the target's dependencies:

```swift
dependencies: [
    .product(name: "WhisperKit", package: "WhisperKit"),
    .product(name: "SpeakerKit", package: "WhisperKit"),
    .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
    .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
],
```

- [ ] **Step 2: Add dependency to project.yml (iOS)**

In `VaakyaApp/project.yml`, add the package under `packages:`:

```yaml
packages:
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit.git
    from: "0.18.0"
  onnxruntime:
    url: https://github.com/microsoft/onnxruntime-swift-package-manager
    from: "1.17.0"
  GoogleSignIn-iOS:
    url: https://github.com/google/GoogleSignIn-iOS.git
    from: "8.0.0"
```

And add the dependency under the target's `dependencies:`:

```yaml
    dependencies:
      - package: WhisperKit
        product: WhisperKit
      - package: WhisperKit
        product: SpeakerKit
      - package: onnxruntime
        product: onnxruntime
      - package: GoogleSignIn-iOS
        product: GoogleSignIn
```

- [ ] **Step 3: Resolve packages**

```bash
cd VaakyaApp && swift package resolve
```

Expected: GoogleSignIn-iOS resolves and downloads. No errors.

- [ ] **Step 4: Commit**

```bash
git add VaakyaApp/Package.swift VaakyaApp/project.yml
git commit -m "deps: add GoogleSignIn-iOS SDK via SPM"
```

---

### Task 4: Swift — Configure URL scheme and GIDClientID

**Files:**
- Modify: `VaakyaApp/project.yml` (iOS — xcodegen generates Info.plist)
- Modify: `VaakyaApp/Sources/Resources/Info.plist` (macOS — SPM uses this directly)

The Google Sign-In SDK needs two things in Info.plist:
1. A URL scheme matching the reversed client ID (so Google's OAuth can redirect back to the app)
2. The `GIDClientID` key (so the SDK knows which client to use)

- [ ] **Step 1: Add URL scheme and GIDClientID to project.yml (iOS)**

In `VaakyaApp/project.yml`, add to the target's `settings.base:` section:

```yaml
    settings:
      base:
        # ... existing settings ...
        INFOPLIST_KEY_CFBundleURLTypes: |
          <array>
            <dict>
              <key>CFBundleURLSchemes</key>
              <array>
                <string>com.googleusercontent.apps.646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6</string>
              </array>
            </dict>
          </array>
```

Actually, xcodegen handles URL schemes differently. Add a top-level `info:` section to the target instead:

```yaml
  Vaakya:
    type: application
    platform: [iOS, macOS]
    info:
      properties:
        CFBundleURLTypes:
          - CFBundleURLSchemes:
              - com.googleusercontent.apps.646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6
        GIDClientID: "646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6.apps.googleusercontent.com"
```

Place the `info:` block right after `platform: [iOS, macOS]` and before `sources:`.

- [ ] **Step 2: Add URL scheme and GIDClientID to Info.plist (macOS)**

In `VaakyaApp/Sources/Resources/Info.plist`, add these entries inside the top-level `<dict>`:

```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>com.googleusercontent.apps.646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6</string>
			</array>
		</dict>
	</array>
	<key>GIDClientID</key>
	<string>646777782566-sca7f62gcuohtjngsr3o8den9nve8ko6.apps.googleusercontent.com</string>
```

Add these right before the closing `</dict>` tag.

- [ ] **Step 3: Regenerate Xcode project for iOS**

```bash
cd VaakyaApp && xcodegen generate
```

Expected: `Vaakya.xcodeproj` regenerated with URL schemes and GIDClientID in the generated Info.plist.

- [ ] **Step 4: Verify URL scheme is in the generated project**

Open the generated `Vaakya.xcodeproj` in Xcode briefly, go to the target > Info > URL Types, and confirm the reversed client ID URL scheme is listed. Or check via:

```bash
grep -r "googleusercontent" VaakyaApp/Vaakya.xcodeproj/
```

Expected: Should find the reversed client ID URL scheme.

- [ ] **Step 5: Commit**

```bash
git add VaakyaApp/project.yml VaakyaApp/Sources/Resources/Info.plist
git commit -m "config: add Google OAuth URL scheme and client ID to Info.plist"
```

---

### Task 5: Swift — Implement real Google Sign-In flow in AuthViewModel

**Files:**
- Modify: `VaakyaApp/Sources/ViewModels/AuthViewModel.swift`

This replaces the UUID placeholder (lines 34-56) with the real Google Sign-In SDK flow.

- [ ] **Step 1: Add GoogleSignIn import**

At the top of `AuthViewModel.swift`, add:

```swift
import GoogleSignIn
```

So the imports become:

```swift
import AuthenticationServices
import Foundation
import GoogleSignIn
import SwiftUI
```

- [ ] **Step 2: Replace signInWithGoogle() method**

Replace the entire `// MARK: - Sign In with Google (dev-mode placeholder)` section (lines 34-56) with:

```swift
    // MARK: - Sign In with Google

    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil

        do {
            // Get the root view controller for the sign-in presentation
            guard let presentingWindow = Self.getPresentingWindow() else {
                errorMessage = "Cannot present Google Sign-In"
                isLoading = false
                return
            }

            // Configure additional scopes (calendar.readonly for future use)
            let additionalScopes = ["https://www.googleapis.com/auth/calendar.readonly"]

            // The SDK reads GIDClientID from Info.plist automatically
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingWindow,
                hint: nil,
                additionalScopes: additionalScopes
            )

            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Failed to get Google ID token"
                isLoading = false
                return
            }

            // Send the real Google ID token to the backend
            let _ = try await APIClient.shared.login(
                provider: "google",
                identityToken: idToken,
                name: result.user.profile?.name
            )
            currentUser = try await APIClient.shared.fetchMe()
            isLoggedIn = true
            Task { await SyncService.shared.pushAll(); SyncService.shared.startPeriodicSync() }
        } catch let error as GIDSignInError where error.code == .canceled {
            // User cancelled — not an error
        } catch {
            errorMessage = "Google Sign In failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Presenting Window Helper

    private static func getPresentingWindow() -> PlatformWindow? {
        #if os(macOS)
        return NSApplication.shared.keyWindow
        #else
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        #endif
    }
```

- [ ] **Step 3: Add PlatformWindow typealias**

At the top of `AuthViewModel.swift`, after the imports, add a cross-platform typealias:

```swift
#if os(macOS)
private typealias PlatformWindow = NSWindow
#else
private typealias PlatformWindow = UIWindow
#endif
```

- [ ] **Step 4: Add Google Sign-Out to logout()**

In the `logout()` method (around line 96), add `GIDSignIn.sharedInstance.signOut()` so Google's session is also cleared:

```swift
    func logout() {
        GIDSignIn.sharedInstance.signOut()
        APIClient.shared.clearTokens()
        SyncService.shared.stopPeriodicSync()
        currentUser = nil
        isLoggedIn = false
    }
```

- [ ] **Step 5: Build to verify compilation**

```bash
cd VaakyaApp && swift build 2>&1 | tail -20
```

Expected: Build succeeds. If there are type errors with `GIDSignIn.sharedInstance.signIn(withPresenting:)`, check the SDK version's API — the method signature may differ slightly between v7 and v8. The v8 API uses `withPresenting:` which takes `NSWindow` on macOS and `UIWindow` on iOS.

- [ ] **Step 6: Commit**

```bash
git add VaakyaApp/Sources/ViewModels/AuthViewModel.swift
git commit -m "feat: implement real Google Sign-In with GoogleSignIn SDK"
```

---

### Task 6: Swift — Add onOpenURL handler for OAuth callback

**Files:**
- Modify: `VaakyaApp/Sources/VaakyaApp.swift`

When Google Sign-In completes, the OAuth flow redirects back to the app via the custom URL scheme. The SDK needs to handle this URL to complete the sign-in.

- [ ] **Step 1: Add GoogleSignIn import**

At the top of `VaakyaApp.swift`, add:

```swift
import GoogleSignIn
```

- [ ] **Step 2: Add onOpenURL to macOS WindowGroup**

In `VaakyaApp.swift`, find the macOS `WindowGroup` (line 110). Add `.onOpenURL` to the outermost `Group` inside it. The modifier goes right after `.task { ... }` (around line 196):

```swift
            .task {
                // ... existing loading code ...
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
```

- [ ] **Step 3: Add onOpenURL to iOS WindowGroup**

Find the iOS `WindowGroup` (line 422). Add `.onOpenURL` to the `Group` inside it, right after `.task { ... }` (around line 448):

```swift
            .task {
                await LocalStore.shared.initialize()
                await auth.checkSession()
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
```

- [ ] **Step 4: Build to verify**

```bash
cd VaakyaApp && swift build 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add VaakyaApp/Sources/VaakyaApp.swift
git commit -m "feat: handle Google OAuth callback URL in app lifecycle"
```

---

### Task 7: Manual — Enable Google Calendar API and add test user

This is a **manual step** — the user does this in the Google Cloud Console.

- [ ] **Step 1: Enable Google Calendar API**

Go to Google Cloud Console > APIs & Services > Library. Search for "Google Calendar API" and click Enable.

- [ ] **Step 2: Add yourself as a test user**

Go to APIs & Services > OAuth consent screen > Test users. Add your Google email as a test user. While the app is in "Testing" mode, only users on this list can sign in.

---

### Task 8: End-to-end verification

- [ ] **Step 1: Deploy backend with new config**

```bash
make backend-deploy-stg
```

This deploys the Lambda with `skip_verification: false` and the real `google-client-id` from SSM.

- [ ] **Step 2: Run the macOS app against staging**

```bash
cd VaakyaApp && make app-run-stg
```

- [ ] **Step 3: Test Google Sign-In flow**

1. Click "Sign in with Google" button
2. Google login screen should appear (in-app browser)
3. Sign in with a Google account that's on the test users list
4. After authenticating, you should be redirected back to the app
5. The app should show your name/email from Google
6. Check that sync starts (cloud icon or sync status indicator)

- [ ] **Step 4: Test sign-out and re-sign-in**

1. Go to Settings > Account > Sign Out
2. Verify you're logged out (anonymous mode)
3. Sign in again — should be a one-tap flow since Google remembers consent

- [ ] **Step 5: Test on iOS Simulator**

```bash
cd VaakyaApp && xcodegen generate && open Vaakya.xcodeproj
```

Run on an iOS simulator. Repeat the sign-in test. Note: Google Sign-In on simulator may show a web-based flow instead of the native Google app flow — this is expected.

- [ ] **Step 6: Commit any fixes**

If any tweaks were needed during testing, commit them:

```bash
git add -A
git commit -m "fix: Google Sign-In adjustments from e2e testing"
```
