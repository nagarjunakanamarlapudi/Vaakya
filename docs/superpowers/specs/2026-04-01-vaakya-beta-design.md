# Vaakya (वाक्य) — Public Beta Design Specification

## 1. Overview

Design specification for taking Vaakya from working prototype to public beta (TestFlight, 50-100 users). macOS + iOS, complete and bug-free.

**Target:** Public beta via TestFlight. Strangers can use it without hand-holding.
**Platforms:** macOS + iOS (shared SwiftUI codebase)
**Timeline:** No hard deadline. Ship when it's right.
**Approach:** Vertical slices — each slice delivers a complete, testable user story.

---

## 2. Architecture

### 2.1 Client (Swift/SwiftUI)

| Concern | macOS | iOS |
|---|---|---|
| Audio capture | CoreAudio (system + mic) | AVAudioSession (mic only) |
| Transcription | MLX Whisper large-v3-turbo (16GB+) / medium (8GB) | MLX Whisper small / base |
| Speaker ID | pyannote via ONNX Runtime | pyannote via ONNX Runtime |
| AI Enhancement | Ollama local OR cloud (BYOK / Platform) | Cloud only (BYOK / Platform) |
| Storage | Local SQLite (source of truth) | Local SQLite (source of truth) |
| Calendar | EventKit | EventKit |
| Sync | Optional — paid tier pushes to server | Optional — paid tier pushes to server |

**Key rule:** The app launches, records, transcribes, identifies speakers, and edits notes with zero network calls. Server is only contacted for: auth, cloud AI, sync, sharing.

### 2.2 Server (Python/FastAPI on AWS)

| Concern | AWS Service | Notes |
|---|---|---|
| API Server | App Runner | Auto-scaling, deploys from ECR |
| Database | RDS PostgreSQL (db.t4g.micro, single-AZ) | ~$13/mo |
| File Storage | S3 | Audio files, exports |
| Secrets | Secrets Manager | API keys, DB creds, JWT signing key |
| DNS / TLS | Route 53 + ACM | api.vaakya.app |
| Share Viewer | CloudFront + S3 | Static SPA at share.vaakya.app |
| CI/CD | GitHub Actions → ECR → App Runner | Push to main triggers deploy |
| Monitoring | CloudWatch | Free tier |
| Auth | Self-managed JWT (python-jose) | No Cognito |

**No Redis for beta.** JWT is stateless. No real-time collaboration yet.

**Estimated cost:** ~$22-27/mo for beta.

**Dev environment:** Docker Compose with PostgreSQL + MinIO. No AWS dependency for development.

### 2.3 AI Enhancement Options

| Option | How it works | Tier |
|---|---|---|
| Local (Ollama) | Mac only. Ollama with MLX backend. App auto-detects. | Free |
| Cloud — OpenAI | User's own API key | Free |
| Cloud — Anthropic Sonnet | User's own API key. Sonnet 4. | Free |
| Cloud — Anthropic Claude | User's own API key. Opus 4. | Free |
| Cloud — Platform Default | Vaakya's API key, routes to best model | Paid ($14/mo) |

BYOK (Bring Your Own Key) is available on free tier. Platform Default is paid tier only.

### 2.4 Data Flow

```
Mic / System Audio (on-device)
  → MLX Whisper (on-device transcription, never leaves device)
  → pyannote ONNX (on-device speaker diarization)
  → Timestamped, speaker-labeled transcript
  → User's quick notes merged with transcript
  → AI Enhancement (Ollama local / Cloud BYOK / Cloud Platform)
  → Structured block notes (summary, decisions, actions, quotes)
  → Local SQLite storage
  → Optional: sync to API → PostgreSQL (paid tier)
```

---

## 3. Monetization

### Free (forever)
- Local transcription (MLX Whisper) — unlimited meetings
- Speaker identification (pyannote)
- Audio playback with transcript sync
- Local AI enhancement (Ollama, Mac only)
- Cloud AI enhancement with own API key (BYOK)
- Block editor with slash commands
- Calendar integration
- Copy / Export (PDF, Markdown, plain text)
- Offline mode — fully functional

### Paid ($14/mo)
- Platform Default AI (no API key needed, best model)
- Cross-device sync (Mac ↔ iPhone ↔ iPad)
- Share links (web-viewable notes at share.vaakya.app)
- Note history / versioning
- Priority support

---

## 4. Slice 1: Foundation

Unblocks everything. No features — infrastructure to ship and test with real users.

### Auth
- Sign in with Apple: `ASAuthorizationAppleIDProvider` on client, verify identity token server-side via Apple's JWKS endpoint
- Sign in with Google: Google Sign-In SDK on client, verify ID token server-side via Google's tokeninfo endpoint
- Both flows → FastAPI `/auth/login` returns JWT + refresh token
- Token refresh via `/auth/refresh`
- Keychain storage on client (shared between macOS + iOS via iCloud Keychain for paid users)

### Deployment
- Dockerfile for FastAPI app
- GitHub Actions: push to `main` → build container → push to ECR → deploy to App Runner
- RDS PostgreSQL (db.t4g.micro, single-AZ) with Alembic migrations run on deploy
- S3 bucket for audio files + exports
- Secrets Manager for API keys, DB credentials, JWT signing key
- Route 53 + ACM for `api.vaakya.app`
- Staging environment: separate App Runner service + RDS, same ECR image, different env vars

### Swift App Changes
- Replace hardcoded `localhost:8000` with environment-aware base URL (dev/stg/prod)
- Add Sign in with Apple / Google UI to LoginView
- Store tokens in Keychain instead of UserDefaults

### Done When
- Sign in with a real Google/Apple account on deployed staging environment
- CI/CD deploys automatically on push to main
- E2E test suite passes against staging

---

## 5. Slice 2: Local Transcription

The privacy story becomes real. Audio never leaves the device.

### MLX Whisper on macOS
- Integrate `mlx-swift` + Whisper implementation
- Model selection by RAM: `large-v3-turbo` (1.6GB) for 16GB+, `medium` (769MB) for 8GB
- Auto-detect available RAM at launch
- Model download on first launch with progress bar in Settings
- Store in `~/Library/Application Support/Vaakya/Models/`
- Streaming transcription during recording — partial results to transcript view
- Output: timestamped segments with start/end times and text

### MLX Whisper on iOS
- Same `mlx-swift` integration
- `small` (466MB) default, `base` fallback for older phones
- Download on first launch with progress indicator
- Transcription runs after recording completes (not streaming — saves battery)

### What Gets Removed
- Delete `/meetings/{id}/transcribe` server endpoint
- Delete `src/vaakya/services/transcription.py` (Faster-Whisper server-side)
- Transcription is 100% client-side

### Backend Changes
- Meeting model keeps `transcript` field — pushed from client after local transcription
- Client sends transcript to server only for sync (paid tier)

### Shared Swift Code
- `TranscriptionService` protocol with platform-specific implementations
- Common: model management (download, delete, list, disk usage), segment parsing, progress reporting
- Platform-specific: model selection logic based on RAM

### Done When
- Record on Mac → transcript appears in real-time with timestamps, never hits the server
- Record on iPhone → transcript appears after recording stops
- Airplane mode: full record + transcribe works with zero network

---

## 6. Slice 3: Speaker Identification

"Who said what" — the feature Granola can't do on desktop.

### pyannote via ONNX Runtime
- pyannote segmentation model exported to ONNX (~17MB)
- `onnxruntime-swift` (Apple Silicon optimized) runs on-device
- Pipeline: audio → pyannote segments speakers → align with Whisper segments by timestamp → each segment gets a speaker label

### Processing Pipeline
1. After recording completes, run diarization:
   - pyannote segments audio into speaker turns ("Speaker A: 0:00-0:42, Speaker B: 0:42-1:15...")
   - Align speaker turns with Whisper transcript segments by timestamp overlap
   - Assign speaker labels to each transcript segment
2. Result: transcript where every line has a speaker + timestamp

### Speaker Management
- After transcription, speakers show as "Speaker 1", "Speaker 2", etc.
- User can manually rename ("Speaker 1" → "Priya")
- Speaker names persist per meeting
- Speaker colors auto-assigned from palette
- Voice fingerprinting for cross-meeting recognition: post-beta stretch goal

### Platform Details
- macOS: runs comfortably alongside Whisper, ~200MB additional RAM
- iOS: same ONNX model, runs sequentially after transcription (not parallel, manage memory)

### Data Model Changes
- Transcript segments gain `speaker` field (string, nullable)
- Meeting gains `speakers` array ({id, label, color})
- Block model already has `speaker` — AI enhancement uses transcript speaker labels

### UI Changes
- TranscriptView: real speaker labels instead of placeholder
- Speaker filter dropdown works with real data
- MeetingDetailView: speaker breakdown with talk-time percentages
- Enhance flow: speaker names passed to AI ("Priya suggested..." not "Speaker 1 suggested...")

### Done When
- Record meeting with 2+ people → transcript shows distinct speakers with correct turn boundaries
- Rename a speaker → propagates through transcript and enhanced notes
- Speaker filter in transcript panel works

---

## 7. Slice 4: Calendar Integration

The app becomes ambient — knows your meetings before you do.

### EventKit (macOS + iOS)
- Request calendar access on first launch
- Read events from all calendars (Google Calendar, Outlook, iCloud — EventKit handles all)
- Watch for changes via `EKEventStoreChangedNotification`

### Menu Bar (macOS)
- Shows next upcoming meeting: title, time, participants
- "Start Capture" button: auto-creates meeting and begins recording
- If event has video link (Zoom/Meet/Teams URL in notes or location), show it
- Auto-start option: when event with video link begins, prompt "Start recording?" notification. Full auto-start toggle in Settings.
- Recent meetings list (real data, replaces hardcoded placeholder)

### Meeting Creation from Calendar
- Recording started from calendar event pre-populates:
  - Title from event title
  - Participants from event attendees (names + emails)
  - Duration from event duration
  - Template auto-suggested from title keywords ("standup" → Standup, "1:1" → 1-on-1)

### Speaker Matching (ties into Slice 3)
- After transcription + diarization, if started from calendar event:
  - Speaker matching screen: "We detected N speakers. Match them to participants:"
  - Each speaker shows 5-second audio sample with play button
  - Participant names as tap targets
  - "Someone not on the invite" option for unexpected attendees
- No calendar event (quick recording): fall back to manual rename from Slice 3

### iOS
- No menu bar — "Next Meeting" card at top of meetings list
- Notification 1 minute before meeting: "Meeting with Priya in 1 min — tap to start recording"

### Data Model Changes
- Meeting gains: `calendar_event_id` (string, nullable), `participants` (JSON array of {name, email})
- Participants are local-only — not synced to server (privacy)

### Done When
- Calendar events appear in menu bar with correct title, time, participants
- "Start Capture" on calendar event → meeting created with pre-filled metadata
- After transcription, speaker matching screen shows participant names from calendar
- iOS shows next meeting card and sends pre-meeting notification
- Works with Google Calendar, Outlook, iCloud calendars (all via EventKit)

---

## 8. Slice 5: iOS App

Shared SwiftUI codebase. iPhone handles in-person meetings.

### Shared Code (already works)
- All SwiftUI views (sidebar, detail, block editor, transcript, chat, settings, login, share)
- API client, models, auth flow
- Audio player for playback

### Platform-Specific Work

| Concern | macOS | iOS |
|---|---|---|
| Audio capture | CoreAudio (system + mic) | AVAudioSession (mic only) |
| Whisper model | large-v3-turbo / medium | small / base |
| Floating pill | NSPanel (always on top) | N/A |
| Menu bar | NSStatusBarButton | N/A |
| Background recording | Not needed | `UIBackgroundModes: audio` |
| Layout | Sidebar + detail side by side | NavigationStack push/pop |

### iOS-Specific Features
- Background recording: continues when user switches apps or locks screen. `AVAudioSession.Category.record` with background audio entitlement.
- Lock screen controls: recording status + stop button via `MPNowPlayingInfoCenter`
- Haptic feedback on record start/stop
- Compact layout: no sidebar — meetings list pushes to detail. Transcript is a sheet.
- Share: native `UIActivityViewController`

### Audio Device Management (macOS + iOS)

**macOS:**
- Auto-detect input/output devices via CoreAudio (`AudioObjectGetPropertyData`)
- List all: built-in mic, external mics, AirPods, Bluetooth headsets, audio interfaces
- Watch for device changes (plug/unplug, Bluetooth connect/disconnect) via `AudioObjectAddPropertyListener`
- Default: follow system default. User can override per-recording in floating notepad.
- Device disconnect mid-recording: auto-switch to next available, toast "Switched to Built-in Microphone"

**iOS:**
- Auto-detect via `AVAudioSession.availableInputs`
- Watch for route changes via `AVAudioSession.routeChangeNotification`
- Bluetooth devices appear automatically when paired
- Default: follow system route. Show current device name in recording UI.
- Same disconnect handling: auto-fallback + toast

**UI (both):**
- Small mic icon in recording UI showing current input device name
- Tap/click for dropdown of available devices to switch
- Contextual — only visible when recording

### What iOS Does NOT Do (beta)
- No system audio capture (iOS doesn't allow it)
- No local AI enhancement (cloud only or defer to Mac)
- No floating pill

### Build Setup
- Single Swift Package with macOS + iOS platform targets
- `#if os(macOS)` / `#if os(iOS)` for platform-specific views
- Shared: ViewModels, API client, models, TranscriptionService protocol, DiarizationService protocol
- TestFlight for iOS beta distribution
- Separate scheme for macOS (.app bundle, Mac App Store later)

### Done When
- iPhone records in-person meeting, transcribes locally with Whisper small, shows speaker-labeled transcript
- Recording continues in background when app backgrounded or screen locked
- Enhance notes via cloud AI (BYOK or Platform)
- Calendar integration shows upcoming meetings
- Same account works on Mac and iPhone
- Paid tier: meetings sync between Mac and iPhone
- Audio device auto-detection works (AirPods, Bluetooth headsets, wired mics)

---

## 9. Slice 6: Share & Polish

Makes it TestFlight-ready for strangers.

### Web Share Viewer
- Static SPA (HTML + JS + CSS) on CloudFront + S3
- Route: `share.vaakya.app/{token}`
- Fetches from `GET /api/share/{token}`
- Renders: title, date, participants, all blocks with same design system (light mode default, matches app)
- Read-only
- "Get Vaakya" CTA at bottom (App Store link) — viral loop
- Expired links: clean "This link has expired" message

### Floating Pill Hardening (macOS)
- Fix window management issues (ghost toolbar buttons, tab bars, NSPanel boundary)
- States: recording dot, timer, waveform, current speaker name
- Draggable, stays on top of all windows including fullscreen
- Smooth pill ↔ notepad transition via `Cmd+Shift+V`
- Test across: Zoom fullscreen, Google Meet in Chrome fullscreen, Teams, FaceTime

### Onboarding (first launch)
1. Sign in with Apple / Google
2. Grant permissions — microphone, system audio (Screen Recording on macOS), calendar. Plain language explanation for each.
3. Whisper model download — progress bar, size estimate, "This enables private on-device transcription"
4. Quick tour — 3-4 screens: menu bar icon, floating notepad, enhance flow, transcript panel
5. Done — menu bar active, ready for first meeting

### Polish
- Menu bar "Recent Notes" shows real recent meetings
- Quick Recording from menu bar works (creates meeting + starts recording)
- Error states: no mic permission, model download failed, cloud AI key invalid, network offline during cloud enhance
- Empty states: no meetings yet, no transcript yet, no enhanced notes yet
- Loading states: transcription in progress, enhancement in progress, sync in progress
- App icon and branding

### TestFlight Readiness
- Provisioning profiles, App Store Connect setup
- Privacy nutrition labels (microphone, calendar)
- App Review notes explaining system audio capture (Screen Recording permission)
- Crash reporting (Apple's built-in crash logs for beta)

### Done When
- Share a meeting link → opens in browser, looks professional, shows all blocks
- First-time user launches → onboarding guides through setup without confusion
- Record via menu bar → full flow works end-to-end without touching main window
- Floating pill works reliably across Zoom, Meet, Teams in fullscreen
- 10 minutes of use with no crashes, no broken states, no confusing moments

---

## 10. UI Design System (Revised)

### 10.1 Design Philosophy

Shifted from Linear-developer aesthetic to Apple-native calm aesthetic. The app should feel like an Apple first-party productivity tool — light, airy, comfortable for all-day use.

- **Comfort over style.** People live in this app all day. Prioritize readability and calm over visual impact.
- **Light mode default.** Dark mode available as an option, not the identity.
- **Apple-native feel.** Rounded corners, generous whitespace, soft shadows, native controls.
- **User text is primary.** User-written content in strong black. AI-generated content in secondary gray.
- **Progressive disclosure.** Metadata and actions appear contextually, not all at once.
- **Trust badges.** Constantly reinforce the privacy story: "Processed on your Mac", "Audio never leaves your device."

### 10.2 Color Palette

**Light Mode (default):**

| Token | Value | Usage |
|---|---|---|
| `--bg-app` | `#FFFFFF` | App background |
| `--bg-sidebar` | `#F7F7F8` | Sidebar background |
| `--bg-content` | `#FFFFFF` | Content areas |
| `--bg-card` | `#F5F5F7` | Cards, stat blocks, quick start |
| `--bg-hover` | `rgba(0,0,0,0.04)` | Hover states |
| `--bg-active` | `rgba(0,0,0,0.06)` | Active/selected states |
| `--bg-accent` | `rgba(52,168,83,0.10)` | Accent backgrounds |
| `--text-primary` | `#1A1A1A` | Headings, user-written content |
| `--text-secondary` | `#6B6B6B` | Descriptions, AI-generated text |
| `--text-tertiary` | `#9B9B9B` | Timestamps, placeholders |
| `--accent` | `#34A853` | Primary actions, active states, recording indicators |
| `--accent-hover` | `#2D9249` | Hover on accent |
| `--green` | `#34A853` | Primary accent, success, active recording |
| `--red` | `#EA4335` | Action items, urgent, stop recording |
| `--blue` | `#4285F4` | Decisions, info, links |
| `--yellow` | `#FBBC04` | Warnings, in-progress |
| `--border` | `rgba(0,0,0,0.08)` | Subtle dividers |
| `--border-strong` | `rgba(0,0,0,0.15)` | Input borders |
| `--shadow-card` | `0 1px 3px rgba(0,0,0,0.08)` | Card elevation |
| `--shadow-elevated` | `0 4px 12px rgba(0,0,0,0.10)` | Modals, dropdowns |

**Dark Mode (optional):**

| Token | Value | Usage |
|---|---|---|
| `--bg-app` | `#1A1A1A` | App background |
| `--bg-sidebar` | `#222222` | Sidebar background |
| `--bg-content` | `#1A1A1A` | Content areas |
| `--bg-card` | `#2A2A2A` | Cards |
| `--text-primary` | `#EDEDEF` | Headings, user content |
| `--text-secondary` | `#9B9B9B` | AI-generated text |
| `--accent` | `#4ECB71` | Lighter green for dark backgrounds |

### 10.3 Typography

| Role | Size | Weight | Line Height |
|---|---|---|---|
| Page title | 24px | 700 | 32px |
| Section heading | 16px | 600 | 22px |
| Body | 15px | 400 | 1.6 |
| Body medium | 15px | 500 | 1.6 |
| Caption | 13px | 400 | 18px |
| Label | 12px | 500 | 16px |

Font: SF Pro (system font) — feels native, no custom font loading.
Larger sizes than v1 (15px body vs 14px) for comfort.

### 10.4 Spacing

8px base grid (more generous than v1's 4px grid):

| Token | Value |
|---|---|
| `--space-1` | 4px |
| `--space-2` | 8px |
| `--space-3` | 12px |
| `--space-4` | 16px |
| `--space-6` | 24px |
| `--space-8` | 32px |
| `--space-12` | 48px |

### 10.5 Border Radius

| Token | Value | Usage |
|---|---|---|
| `--radius-sm` | 6px | Tags, badges |
| `--radius-md` | 10px | Inputs, buttons, cards |
| `--radius-lg` | 14px | Modals, panels |
| `--radius-xl` | 20px | Large cards, stat blocks |

More rounded than v1 — feels softer, more Apple-native.

### 10.6 Buttons

| Variant | Background | Color | Height |
|---|---|---|---|
| Primary | `#34A853` | `#FFFFFF` | 36px |
| Secondary | `#F5F5F7` | `#1A1A1A` | 36px |
| Tertiary | `transparent` | `#6B6B6B` | 36px |

Font: 14px, weight 500, padding 0 16px, border-radius 10px.
Taller (36px vs 32px) with more padding — easier to tap.

### 10.7 Block Editor

| Block Type | Left Border | Badge Color |
|---|---|---|
| Summary | 3px `--accent` (green) | Green |
| Decision | 3px `--blue` | Blue |
| Action Item | 3px `--red` | Red |
| Quote | 3px `--yellow` | Yellow |

- Block padding: 16px 20px (more generous than v1)
- Block margin-bottom: 12px
- Block border-radius: 12px
- Block background: `--bg-card`
- Soft shadow: `--shadow-card`
- Notes area max-width: 720px, centered (wider than v1's 680px)

### 10.8 Motion

| Action | Duration | Easing |
|---|---|---|
| Hover color | 150ms | ease-out |
| Panel slide | 250ms | spring(0.5, 0.8, 0) |
| Modal enter | 200ms | spring |
| Card press | 100ms | scale(0.98) |

Use SwiftUI spring animations — feels native.

---

## 11. UX Patterns (New)

### 11.1 Dashboard (Home Screen)

Replaces the plain meeting list as the default view.

**Stats bar (top):**
- 4 cards in a row: Meetings this week, Total captured (hours), Action items, AI enhanced
- Each card: icon, number (large), label (small)
- Background: `--bg-card` with `--shadow-card`
- Updates automatically

**Quick Start (below stats):**
- 3 action cards: "Record meeting" (mic icon), "Search notes" (search icon), "Action items" (checkbox icon)
- Tap to act immediately

**Recently Enhanced (below Quick Start):**
- List of recent meetings with: title, date, duration, source tag (Zoom/Meet/Teams/In Person/Manual)
- Tap to open meeting detail

### 11.2 Meeting Source Tags

Every meeting shows how it was captured:

| Source | Tag | Detected from |
|---|---|---|
| Zoom | "Zoom" | Calendar event URL or active Zoom process |
| Google Meet | "Meet" | Calendar event URL or Chrome tab title |
| Microsoft Teams | "Teams" | Calendar event URL or active Teams process |
| FaceTime | "FaceTime" | Active FaceTime call |
| Webex | "Webex" | Calendar event URL or active Webex process |
| In Person | "In Person" | iOS recording (mic only, no system audio) |
| Manual | "Manual" | Quick recording with no detected meeting source |

Tags shown in sidebar meeting list and meeting detail metadata bar.

### 11.3 Privacy Badges

Visible in three places:
- **Meeting detail:** "Processed on your Mac" or "Processed on your iPhone" badge in metadata bar
- **Menu bar dropdown:** "Audio never leaves your Mac" at bottom
- **Settings:** "Audio never leaves your device" in transcription section

Badge design: lock icon + text, muted green background, small caption size.

### 11.4 Contextual Action Sidebar (Meeting Detail)

Right side of meeting detail view, always visible (not a toggle panel):

**Share Notes:**
- Copy text (rich text to clipboard)
- Email (opens compose with formatted notes)
- Copy for Slack (Slack-formatted markdown)

**Ask Vaakya:**
- Quick action buttons: "List action items", "Write follow-up", "Summarize"
- "Ask about the meeting..." text input for freeform questions
- Responses appear inline below the input

This replaces the separate Chat panel toggle. Chat is now integrated into the contextual sidebar.

### 11.5 Settings

Horizontal tab layout with clear groupings:
- **General:** Launch at Login, Appearance (Light/Dark/System), Theme
- **Recording:** Microphone, System audio, Auto-start
- **Calendar:** Calendar Access toggle, auto-detect meetings
- **AI Enhancement:** Provider dropdown, API key fields, Auto-enhance toggle
- **Transcription:** Whisper Model dropdown, download/manage models
- **Account:** Sign out, Delete all data

Toggle switches use green accent. Native macOS/iOS settings feel.

---

## 12. Differentiators vs. Granola (Beta)

| Feature | Granola | MeetingMind | Vaakya (Beta) |
|---|---|---|---|
| Speaker identification | "Me" vs "Them" on desktop | Text-based extraction | Full multi-speaker diarization with names |
| Audio playback | No audio stored | No audio player visible | Full playback with transcript sync |
| Offline mode | Requires internet for AI | Local Whisper + Sonnet | Fully functional offline (Ollama + MLX Whisper) |
| Privacy | Cloud transcription | "Processed on your Mac" | 100% on-device transcription |
| AI provider choice | Locked to their models | Sonnet (possibly configurable) | Ollama / OpenAI / Anthropic Sonnet / Anthropic Claude / Platform |
| Free tier | 30-day history limit | Unknown | Unlimited, genuinely useful (BYOK cloud AI included) |
| Calendar speaker matching | No | No | Match detected voices to calendar participants |
| Dashboard with stats | No | Yes — meetings, hours, action items | Yes — meetings, hours, action items, AI enhanced |
| Meeting source tags | No | Yes (Webex, Manual) | Yes (Zoom, Meet, Teams, In Person, Manual) |
| Design | Dark, developer-aesthetic | Light, Apple-native, clean | Light default (dark option), Apple-native, green accent |
| iOS | Yes | Unknown | Yes (in-person meetings, mic only) |
| Windows | Yes | No (macOS only) | No (macOS + iOS only) |
| Web app | No | No | Share viewer only |
