# Vaakya Local-First Architecture — Design Specification

## 1. Overview

Redesign Vaakya's data layer from server-dependent (API calls for all CRUD) to local-first (filesystem storage, in-memory index, optional cloud sync). The app works fully offline with zero server dependency. Signing in with Apple/Google is the explicit opt-in to cloud features (sync, share links, platform AI).

**Scope:** Data storage, sync, AI routing, backend simplification, Terraform changes.

**Not in scope:** UI changes (views stay the same), transcription, diarization, calendar, recording — these already work locally.

---

## 2. Architecture

### 2.0 System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           macOS / iOS App                                   │
│                                                                             │
│  ┌──────────┐  ┌──────────────┐  ┌─────────────┐  ┌──────────────────────┐ │
│  │ SwiftUI  │  │ MeetingVM    │  │ AIService   │  │ TranscriptionService │ │
│  │ Views    │──│ CalendarVM   │──│             │  │ DiarizationService   │ │
│  │          │  │ AuthVM       │  │             │  │ SystemAudioCapture   │ │
│  └──────────┘  └──────┬───────┘  └──────┬──────┘  └──────────────────────┘ │
│                       │                 │                                    │
│                ┌──────▼───────┐  ┌──────▼──────┐                            │
│                │  LocalStore  │  │   Keychain  │                            │
│                │  (in-memory  │  │  (API keys) │                            │
│                │   index +    │  └─────────────┘                            │
│                │   WAL +      │                                              │
│                │   filesystem)│                                              │
│                └──────┬───────┘                                              │
│                       │                                                      │
│    ┌──────────────────▼───────────────────────────┐                         │
│    │  {applicationSupport}/Vaakya/        │                         │
│    │  ├── meetings/{id}/meeting.json + audio.m4a   │                         │
│    │  ├── index.json                               │                         │
│    │  ├── wal.jsonl                                │                         │
│    │  ├── settings.json                            │                         │
│    │  └── models/ (WhisperKit)                     │                         │
│    └───────────────────────────────────────────────┘                         │
│                                                                              │
│         ▲ Works fully offline up to this point ▲                             │
│ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│
│         ▼ Optional: only when signed in ▼                                    │
│                                                                              │
│                ┌──────────────┐                                              │
│                │ SyncService  │                                              │
│                └──────┬───────┘                                              │
└───────────────────────┼──────────────────────────────────────────────────────┘
                        │
                        │ HTTPS (pre-signed URLs)
                        │
┌───────────────────────▼──────────────────────────────────────────────────────┐
│                         AWS (Lambda + S3)                                     │
│                                                                              │
│  ┌─────────────────────────────┐      ┌────────────────────────────────────┐ │
│  │  API Gateway + Lambda       │      │  S3 (vaakya-data)                  │ │
│  │                             │      │                                    │ │
│  │  POST /auth/login     ──────│──┐   │  users/{uid}/                     │ │
│  │  POST /auth/refresh   ──────│──│   │    ├── index.json                 │ │
│  │  POST /sync/presign   ──────│──┼──►│    ├── settings.json              │ │
│  │  POST /enhance        ──────│──│   │    └── meetings/{id}/             │ │
│  │  POST /chat           ──────│──│   │         ├── meeting.json          │ │
│  │  POST /share          ──────│──│   │         └── audio.m4a             │ │
│  │  GET  /share/{token}  ──────│──┘   │                                    │ │
│  │                             │      └────────────────────────────────────┘ │
│  └─────────────────────────────┘                                             │
│                                       ┌────────────────────────────────────┐ │
│  ┌─────────────────────────────┐      │  CloudFront                        │ │
│  │  SSM Parameter Store        │      │  CloudFront → S3 share-viewer      │ │
│  │  (JWT secret, OAuth creds)  │      └────────────────────────────────────┘ │
│  └─────────────────────────────┘                                             │
│                                                                              │
│  Custom domain (GoDaddy) added later — use default AWS URLs for beta         │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 2.0.1 Data Flow — Anonymous Mode (No Server)

```
Mic/System Audio
  → WhisperKit (on-device transcription, streaming)
  → Energy-based diarization (real-time speaker labels)
  → User's quick notes (floating notepad)
  → AI Enhancement:
      ├── Ollama (local) ─── client calls localhost:11434 directly
      └── BYOK (OpenAI/Anthropic) ─── client calls API directly, key from Keychain
  → Structured blocks (summary, decisions, actions, quotes)
  → LocalStore → filesystem (meeting.json + audio.m4a)
  → Done. Zero network calls.
```

### 2.0.2 Data Flow — Signed-In Mode (With Sync)

```
Same as above, plus:

After meeting saved to LocalStore:
  → SyncService detects change
  → POST /sync/presign → get pre-signed S3 URL
  → PUT meeting.json directly to S3 (client → S3, server never sees content)
  → PUT audio.m4a to S3 (Wi-Fi only, queued on cellular)

On app launch (other device):
  → SyncService pulls server index.json
  → Diffs with local index
  → Downloads new/updated meetings from S3
  → Updates local filesystem + in-memory index

Share link:
  → POST /share → signed JWT token containing {user_id, meeting_id, exp}
  → {cloudfront-url}/{token} → SPA verifies JWT → fetches meeting.json from S3
```

### 2.0.3 Recording Pipeline (Real-Time)

```
Recording starts
  │
  ├── WhisperKit AVAudioEngine ─── captures mic audio
  ├── ScreenCaptureKit ─────────── captures system audio (calls)
  ├── AudioMixer ───────────────── mixes mic + system
  │
  ▼ Every 5 seconds (chunk-based transcription)
  ├── Mixed audio → WhisperKit transcribe(audioArray:) → new segments
  ├── New segments → LiveTranscriptView (immediate)
  ├── Energy-based diarization → speaker labels (Pass 1: approximate)
  │
  ▼ Every 30 seconds (unified flush)
  ├── Audio buffer → audio-chunks/chunk-NNN.raw (crash safety)
  ├── Transcript snapshot → WAL (crash safety)
  │
  ▼ Recording stops
  ├── Merge chunks → audio.m4a
  ├── Full diarization on complete audio (Pass 2: refinement)
  ├── Speaker matching view (if calendar participants)
  ├── WAL flush → meeting.json
  ├── If signed in: SyncService pushes to S3
  └── Auto-enhance if enabled
```

### 2.1 Two Modes

| Mode | Trigger | Server needed? | Features |
|---|---|---|---|
| **Anonymous** (default) | App launches, no login | No | Record, transcribe, diarize, enhance (Ollama/BYOK), edit, search, export |
| **Signed In** | User taps Sign in with Apple/Google | Yes (Lambda) | Everything above + cross-device sync, share links, platform AI |

### 2.2 Client Data Layer

**Base directory** (resolved via `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`):

| Platform | Resolves to |
|---|---|
| macOS | `~/Library/Application Support/Vaakya/` |
| iOS | `<app-sandbox>/Library/Application Support/Vaakya/` |

```
{applicationSupport}/Vaakya/
├── meetings/
│   ├── {uuid}/
│   │   ├── meeting.json          # Full meeting document (metadata + transcript + blocks + speakers)
│   │   └── audio.m4a             # Recording
│   └── {uuid}/
│       ├── meeting.json
│       └── audio.m4a
├── index.json                    # Metadata index (rebuilt from meeting files on launch)
├── wal.jsonl                     # Write-ahead log (append-only, flushed periodically)
├── settings.json                 # User preferences (AI provider, templates, UI prefs)
└── models/                       # WhisperKit models (already exists)
```

### 2.3 In-Memory Index

On launch, read all `meeting.json` files and build a metadata index in memory:

```swift
struct MeetingMetadata: Codable, Identifiable {
    let id: String
    var title: String
    var startedAt: Date
    var durationSeconds: Int?
    var speakerCount: Int
    var source: String?
    var participantNames: [String]
    var blockCounts: [String: Int]   // {"summary": 1, "action": 3, "decision": 2}
    var pendingActionItems: Int
    var isEnhanced: Bool
    var lastModified: Date
    var hasAudio: Bool
}
```

- 1,000 meetings × ~500 bytes = 500KB in memory
- All list views, dashboard stats, search by title/date/speaker use this index
- Full meeting data (transcript, blocks) loaded on demand from disk

### 2.4 Meeting Document

One self-contained JSON file per meeting. No foreign keys, no normalization.

```swift
struct MeetingDocument: Codable {
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

    var transcript: [TranscriptSegment]
    var blocks: [BlockData]
    var speakers: [SpeakerData]
    var userNotes: String
}

struct Participant: Codable {
    let name: String
    let email: String?
}

struct BlockData: Codable, Identifiable {
    let id: String
    var type: String         // summary, decision, action, quote
    var content: String
    var speaker: String?
    var timestampSeconds: Int?
    var position: Int
    var isChecked: Bool
    var isAIGenerated: Bool
    var metaText: String?
}

struct SpeakerData: Codable {
    let id: String
    var label: String
    var color: String
    var talkTimeSeconds: Double
}
```

### 2.5 Write-Ahead Log (WAL)

Every mutation appends to `wal.jsonl` before updating the in-memory index:

```jsonl
{"ts":"2026-04-02T10:00:00Z","op":"create","meetingId":"abc-123","data":{...}}
{"ts":"2026-04-02T10:01:00Z","op":"update","meetingId":"abc-123","data":{...}}
{"ts":"2026-04-02T10:05:00Z","op":"delete","meetingId":"def-456"}
```

**Flush strategy:**
- Every 30 seconds if there are pending entries
- On app backgrounding / will-terminate
- On explicit save (Cmd+S)

**Flush process:**
1. For each WAL entry, write the meeting's full `meeting.json` to disk
2. Rebuild `index.json` from in-memory state
3. Truncate `wal.jsonl`

**Crash recovery:**
1. On launch, read all `meeting.json` files → build index
2. If `wal.jsonl` has entries, replay them on top of the loaded state
3. Flush to ensure consistency

---

## 3. LocalStore — The Core API

```swift
@MainActor
@Observable
final class LocalStore {
    static let shared = LocalStore()

    private(set) var meetings: [MeetingMetadata] = []
    private var wal: WALWriter
    private let baseDirectory: URL

    // MARK: - Read
    func allMeetings() -> [MeetingMetadata]           // From memory index
    func loadMeeting(id: String) -> MeetingDocument?   // From disk
    func searchMeetings(query: String) -> [MeetingMetadata]  // Title/speaker search in memory

    // MARK: - Write
    func createMeeting(_ meeting: MeetingDocument)     // WAL + index
    func updateMeeting(_ meeting: MeetingDocument)     // WAL + index
    func deleteMeeting(id: String)                     // WAL + index

    // MARK: - Stats (from memory index)
    var meetingsThisWeek: Int
    var totalCapturedSeconds: Int
    var pendingActionItems: Int
    var aiEnhancedCount: Int

    // MARK: - Lifecycle
    func initialize() async                            // Load index, replay WAL
    func flush()                                       // WAL → disk
}
```

### WAL Writer

```swift
final class WALWriter {
    private let fileURL: URL
    private let fileHandle: FileHandle

    func append(operation: WALOperation)               // Append one line to wal.jsonl
    func pendingEntries() -> [WALOperation]            // Read unflushed entries
    func truncate()                                    // Clear after flush
}

struct WALOperation: Codable {
    let timestamp: Date
    let operation: String      // "create", "update", "delete"
    let meetingId: String
    let data: MeetingDocument?  // nil for delete
}
```

---

## 4. Real-Time Recording Pipeline

During a recording, audio, transcript, and speaker labels are produced continuously. All use a **unified 30-second flush interval** for crash safety.

### 4.1 On-Disk Layout During Recording

```
meetings/{id}/
├── meeting.json              # Stub (created on recording start, full data on stop)
├── audio.m4a                 # Final mixed audio (written on stop)
└── audio-chunks/             # Incremental crash safety
    ├── chunk-000.raw         # First 30 seconds (16kHz mono float32)
    ├── chunk-001.raw         # Next 30 seconds
    └── ...
```

### 4.2 Unified Flush Timer (30 seconds)

One timer drives all periodic writes during recording:

```
Every 30 seconds:
  1. Write current audio buffer → audio-chunks/chunk-NNN.raw
  2. Append transcript snapshot (all segments so far) → WAL
  3. Both happen in the same timer tick
```

**On clean recording stop:**
1. Flush remaining audio buffer → last chunk
2. Merge all chunks → `audio.m4a` (AAC encoded)
3. Delete `audio-chunks/` directory
4. Full transcript + metadata written to `meeting.json` via WAL flush

**On crash recovery:**
1. Find `audio-chunks/` directory → concatenate all chunks → reconstruct audio
2. Replay WAL → recover transcript segments (at most 30 seconds stale)
3. Re-transcribe the last 30 seconds from recovered audio if needed

### 4.3 Two-Pass Speaker Diarization

**Pass 1 — Real-time (during recording):**

Runs on each audio chunk as it arrives. Uses the energy-based backend to detect speaker changes by audio energy patterns and silence gaps. Labels new transcript segments immediately ("Speaker 1", "Speaker 2"). `LiveTranscriptView` shows colored speaker labels in real-time.

This is approximate — it can't look ahead, so speaker boundaries may be slightly off.

```
Chunk arrives (30s of audio)
  → Energy-based speaker change detection
  → Label new transcript segments since last chunk
  → Update LiveTranscriptView immediately
```

**Pass 2 — Refinement (after recording stops):**

Runs on the complete audio file. Re-analyzes the full conversation with full context, corrects speaker boundaries, and re-labels all segments. Takes 2-3 seconds for a 1-hour file (energy-based is fast).

```
Recording stops
  → Full audio available (merged from chunks or streaming buffer)
  → Run energy-based diarization on complete file
  → Re-label ALL segments with corrected speaker boundaries
  → Update speaker talk-time percentages
  → Show speaker matching view (map to calendar participants)
```

The user sees speaker labels immediately during recording. They might shift slightly when the refinement pass runs — a brief "refining speakers..." indicator, then the corrected labels appear.

### 4.4 Crash Loss Summary

| Data | Flush interval | Worst-case loss on crash |
|---|---|---|
| Audio | 30 seconds | Last 30s (chunks have the rest) |
| Transcript | 30 seconds | Last 30s (re-transcribable from audio chunks) |
| Speaker labels | With transcript | Last 30s (re-derivable from audio) |
| Meeting metadata | With transcript | Last 30s of edits |
| Blocks (post-enhance) | Immediate WAL write | None |

---

## 5. AI Service — Unified Routing

Replace the current flow (all AI goes through backend) with direct client-side routing:

```swift
@MainActor
@Observable
final class AIService {
    static let shared = AIService()

    func enhance(transcript: [TranscriptSegment], userNotes: String, template: String) async throws -> [BlockData]
    func chat(transcript: [TranscriptSegment], message: String) async throws -> String
}
```

**Routing logic:**

| Provider | How it works | Server involved? |
|---|---|---|
| Ollama | Client calls `http://localhost:11434/api/chat` directly | No |
| OpenAI (BYOK) | Client calls `https://api.openai.com/v1/chat/completions` with user's key from Keychain | No |
| Anthropic (BYOK) | Client calls `https://api.anthropic.com/v1/messages` with user's key from Keychain | No |
| Platform | Client calls our Lambda `/enhance` endpoint (our API key, paid tier) | Yes |

For Ollama/BYOK: the AI prompt template (system prompt + transcript + user notes → structured JSON) moves into the client. Currently it's in `src/vaakya/services/ai.py` — port the prompt to Swift.

---

## 5. Sync Service — S3 via Pre-Signed URLs

Only active when user is signed in. Client never talks to S3 directly — gets pre-signed URLs from Lambda.

### S3 Structure

```
s3://vaakya-data/
└── users/
    └── {user-id}/
        ├── index.json
        └── meetings/
            ├── {meeting-id}/
            │   ├── meeting.json
            │   └── audio.m4a
            └── {meeting-id}/
                ├── meeting.json
                └── audio.m4a
```

### Sync Protocol

```swift
class SyncService {
    /// Get the server's index and diff with local.
    func sync() async {
        // 1. GET /sync/index → pre-signed URL for user's index.json
        // 2. Download index.json from S3
        // 3. Diff with local index by lastModified timestamps
        // 4. For each local-newer: upload meeting.json + audio.m4a
        // 5. For each server-newer: download meeting.json + audio.m4a
        // 6. Upload updated local index.json
    }

    func pushMeeting(id: String) async       // Upload one meeting
    func pullMeeting(id: String) async        // Download one meeting
    func pushAll() async                      // First sync after sign-in
}
```

**Conflict resolution:** Last-write-wins by `lastModified` timestamp. Simple, correct for single-user (multi-device is last-edited-wins, which matches user expectation).

**Sync triggers:**
- After sign-in (full push)
- After each meeting save (push that meeting)
- On app launch if signed in (pull changes from other devices)
- Manual "Sync Now" button in Settings

### Audio Sync Policy

Audio files are large (30-50MB per hour of recording). Sync policy:

| Network | meeting.json | audio.m4a |
|---|---|---|
| Wi-Fi | Sync immediately | Sync immediately |
| Cellular | Sync immediately | **Skip** — download on demand when user taps play |
| Offline | Queue for later | Queue for later |

Detected via `NWPathMonitor`:
```swift
let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    let isWifi = path.usesInterfaceType(.wifi)
    SyncService.shared.audioSyncEnabled = isWifi
}
```

When audio isn't synced, the meeting shows on the other device with full transcript and blocks but a "Download audio" button instead of the play bar. Tapping it downloads the M4A on demand.

### What Syncs vs What Doesn't

| Data | Syncs to S3? | Notes |
|---|---|---|
| meeting.json | Yes, always | Core data — needed on all devices |
| audio.m4a | Yes, Wi-Fi only | Large files — download on demand over cellular |
| settings.json | Yes, always | Consistent preferences across devices |
| WhisperKit models | No | 1.6GB — each device downloads independently |
| WAL | No | Local crash safety only |
| audio-chunks/ | No | Temporary — merged into audio.m4a on stop |

### Pre-Signed URL API

```
POST /sync/presign
Body: { "action": "put", "key": "meetings/{id}/meeting.json" }
Response: { "url": "https://s3.../vaakya-data/users/{uid}/meetings/{id}/meeting.json?X-Amz-..." }
```

Server validates JWT, scopes the key to the user's prefix, returns a pre-signed URL (5 min expiry). Client uploads/downloads directly to S3.

---

## 6. Share Links — Signed JWT Tokens

No database lookup needed. The share token IS the data:

```python
# Generate
token = jwt.encode({
    "user_id": "abc",
    "meeting_id": "def",
    "exp": datetime.utcnow() + timedelta(hours=72)
}, SHARE_SECRET, algorithm="HS256")

# Resolve (stateless)
payload = jwt.decode(token, SHARE_SECRET, algorithms=["HS256"])
# → Generate pre-signed S3 URL for users/{user_id}/meetings/{meeting_id}/meeting.json
```

**Share flow:**
1. Client calls `POST /share` with meeting_id → server returns signed token + URL
2. Share URL: `https://{cloudfront-url}/{token}` (custom domain added later)
3. Share viewer SPA calls `GET /share/{token}` → server verifies JWT, returns pre-signed S3 URL → viewer fetches meeting.json directly from S3

---

## 7. Backend — Lambda Functions

Replace App Runner + RDS with Lambda + API Gateway.

### Functions

| Endpoint | Lambda | Purpose |
|---|---|---|
| `POST /auth/login` | `auth` | Verify Apple/Google token, issue JWT |
| `POST /auth/refresh` | `auth` | Refresh JWT |
| `POST /sync/presign` | `sync` | Generate pre-signed S3 URLs (requires JWT) |
| `GET /sync/index` | `sync` | Pre-signed URL for user's index.json |
| `POST /enhance` | `ai` | Platform AI enhancement (paid tier, our API key) |
| `POST /chat` | `ai` | Platform AI chat (paid tier) |
| `POST /share` | `share` | Generate signed share token |
| `GET /share/{token}` | `share` | Verify token, return pre-signed URL |
| `GET /health` | `health` | Health check |

### What's Deleted from Backend

- `models/` — all SQLAlchemy models (User, Meeting, Block, ShareLink, Settings)
- `schemas/` — all Pydantic request/response schemas (replaced by simpler Lambda schemas)
- `db.py` — database connection
- `deps.py` — FastAPI dependency injection
- `routers/meetings.py` — meeting CRUD (now client-side)
- `routers/notes.py` — block CRUD (now client-side)
- `routers/settings.py` — settings CRUD (now client-side)
- `alembic/` — database migrations
- `seed.py` — seed data
- Docker Compose PostgreSQL + MinIO
- Dependencies: SQLAlchemy, asyncpg, alembic, redis

### What Stays (simplified)

- `routers/auth.py` — OAuth verification + JWT (no DB user creation — stateless)
- `routers/enhance.py` — AI routing (transcript in request body, not from DB)
- `services/ai.py` — AI prompt + provider routing
- `config.py` — settings from env vars

### New

- `routers/sync.py` — pre-signed URL generation
- `routers/share.py` — rewritten for signed JWT tokens (stateless)

### Deployment

Lambda functions via API Gateway HTTP API. Each endpoint is a Lambda handler.

Can use either:
- **Single Lambda** with FastAPI + Mangum adapter (simplest — reuse existing FastAPI code)
- **Separate Lambdas** per function (more granular scaling/permissions)

Recommend: **Single Lambda + Mangum** for beta. One container, all routes, deployed via ECR. Switch to separate functions later if needed.

---

## 8. AWS Stack (Revised Terraform)

| Service | Purpose | Cost (beta) |
|---|---|---|
| Lambda + API Gateway HTTP API | Auth, sync, AI, share | ~$0 (free tier covers beta) |
| S3 | All data — meetings, audio, share viewer | ~$2/mo |
| CloudFront | Share viewer SPA | ~$1/mo |
| ~~Route 53 + ACM~~ | ~~DNS + TLS~~ | Deferred — use default AWS URLs, custom domain via GoDaddy later |
| SSM Parameter Store | Secrets (JWT key, OAuth creds) | $0 |

**Total: ~$4-5/mo** (down from $22/mo)

**Removed:** App Runner, RDS, ECR (Lambda uses container images from ECR, but image is tiny)

---

## 9. First Launch Flow (Revised)

```
Download App
    → Onboarding (permissions, model download)
    → Dashboard (no login required!)
    → Record first meeting
    → Transcribe locally
    → Enhance with Ollama or BYOK key
    → All stored locally

Later, optionally:
    → "Sign in to sync across devices"
    → Sign in with Apple/Google
    → All local meetings pushed to S3
    → Paid features unlocked
```

---

## 10. Migration Path

Existing users (from testing) have data in PostgreSQL. For beta launch with a clean slate, this is fine — wipe the test DB. No migration needed.

If we did need migration: export meetings from PostgreSQL as JSON files → place in the local filesystem structure.

---

## 11. What Changes in the Swift App

### New Files
- `Services/LocalStore.swift` — filesystem CRUD + in-memory index + WAL
- `Services/WALWriter.swift` — append-only log
- `Services/SyncService.swift` — S3 sync via pre-signed URLs
- `Services/AIService.swift` — unified AI routing (Ollama / BYOK / Platform)

### Modified Files
- `ViewModels/MeetingViewModel.swift` — replace all `APIClient` CRUD with `LocalStore`
- `ViewModels/AuthViewModel.swift` — login is optional, not required on launch
- `VaakyaApp.swift` — skip login screen, go straight to onboarding → app
- `API/APIClient.swift` — strip CRUD methods, keep auth + sync + platform AI only
- `Views/ContextualSidebar.swift` — chat via `AIService`
- `Views/SettingsView.swift` — settings from `settings.json` not API
- `Views/OnboardingView.swift` — no login step, add optional "sync" step at end
- `API/Models.swift` — simplify (remove server-specific models)

### Deleted Files
- None deleted, but `APIClient` becomes much smaller

### Backend
- Delete: `models/`, `schemas/`, `db.py`, `deps.py`, `routers/meetings.py`, `routers/notes.py`, `routers/settings.py`, `alembic/`, `seed.py`
- Rewrite: `routers/auth.py` (stateless), `routers/enhance.py` (transcript in body), `routers/share.py` (signed JWT)
- Add: `routers/sync.py`, Mangum adapter for Lambda

### Terraform
- Remove: App Runner, RDS, VPC, security groups
- Add: Lambda function, API Gateway HTTP API
- Keep: S3, CloudFront, SSM, IAM
- Deferred: Route 53, ACM (custom domain via GoDaddy later)
