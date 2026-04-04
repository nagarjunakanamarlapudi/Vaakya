# Vaakya (वाक्य) — Product Design Specification

## 1. Overview

Vaakya is a commercial macOS + iOS meeting notepad that captures audio, transcribes locally, identifies speakers, and uses AI to produce structured meeting notes. It competes with Granola.ai by offering speaker identification, local-first privacy, audio playback, and offline mode.

**Name:** Vaakya (Sanskrit: "speech / utterance")
**Platforms:** macOS, iOS (shared Swift/SwiftUI codebase)
**Target:** Individual professionals first → teams → enterprise
**Monetization:** Free local features + paid cloud tier

---

## 2. Architecture

### 2.1 Client (Swift/SwiftUI)

| Component | Technology | Notes |
|---|---|---|
| Audio capture (macOS) | CoreAudio | System audio + microphone |
| Audio capture (iOS) | AVAudioSession | Microphone only (in-person meetings) |
| Transcription | MLX Whisper (mlx-swift) | large-v3-turbo on macOS, small on iPhone |
| Speaker diarization | pyannote via ONNX Runtime | Local speaker identification |
| Calendar | EventKit | Google Calendar + Outlook sync |
| Local storage | SQLite | Notes, transcripts, audio files |
| Editor | Custom block editor (SwiftUI) | Notion-style with slash commands |

### 2.2 Backend (Python)

| Component | Technology | Notes |
|---|---|---|
| Package manager | uv | Fast Python package/project manager |
| API server | FastAPI | REST + WebSocket for sync |
| Database | PostgreSQL (asyncpg) | Notes, users, teams, sharing |
| ORM | SQLAlchemy 2.0 (async) | Type-safe models |
| Cache / pub-sub | Redis (redis-py async) | Sessions, real-time sync |
| Auth | Sign in with Apple + Google OAuth | JWT via python-jose |
| File storage | S3 (boto3) | Transcript archives, exports |
| Hosting | AWS (ECS or Lambda + API Gateway) | |

### 2.3 Environments

| Environment | Infra | Database | Storage | AI | Notes |
|---|---|---|---|---|---|
| **dev** | All local (Docker Compose) | PostgreSQL in Docker | Local filesystem (minio) | Ollama | Zero AWS dependency. Everything runs on laptop. |
| **stg** | AWS (mirrors prod) | RDS PostgreSQL | S3 | Cloud APIs | Pre-prod. Same infra as prod, smaller instances. Used for integration testing and QA. |
| **prod** | AWS | RDS PostgreSQL | S3 | Cloud APIs | Production. Auto-scaling, monitoring, alerts. |

**Dev environment details:**
- `docker-compose.yml` spins up PostgreSQL, Redis, and MinIO (S3-compatible)
- FastAPI server runs via `uv run` with hot reload
- No AWS credentials needed — all services are local containers
- Seed data script for testing with sample meetings/notes
- Environment config via `.env` files (`.env.dev`, `.env.stg`, `.env.prod`)

**Promotion flow:** dev → stg → prod. No code hits prod without passing stg.

### 2.4 AI Enhancement (configurable by user)

| Mode | How it works |
|---|---|
| Platform Default | Backend routes to Claude/GPT — best model for the task |
| BYOK (Bring Your Own Key) | User's own OpenAI/Anthropic API key — direct calls from client |
| Local (Ollama) | Fully offline — user runs models on their machine |

### 2.5 Data Flow

```
Mic/System Audio
  → MLX Whisper (local transcription)
  → pyannote (local speaker diarization)
  → User's quick notes merged with transcript
  → AI Enhancement (cloud or local, user's choice)
  → Structured block notes (summary, decisions, actions, quotes)
  → Local SQLite storage
  → Optional: sync to Go API → PostgreSQL (paid tier)
```

---

## 3. Monetization

### Free (forever)
- Local transcription (MLX Whisper) — unlimited meetings
- Local AI enhancement (Ollama)
- Speaker identification
- Audio playback
- Offline mode
- Block editor with slash commands
- Copy / Export (PDF, Markdown, plain text)
- macOS Share Sheet

### Paid Cloud Tier
- Cloud AI (Claude / GPT — higher quality than local)
- Cross-device sync (Mac ↔ iPhone ↔ iPad)
- Share links (hosted web-viewable notes)
- Email sharing
- Team Spaces / shared folders
- Calendar sync across devices
- Note history / versioning
- Priority support

---

## 4. User Flow

### 4.1 Setup (first launch)
1. Download from Mac App Store
2. Sign in with Apple / Google
3. Grant permissions: microphone, system audio (Screen Recording on macOS), calendar
4. MLX Whisper model downloads in background (~1.6GB for large-v3-turbo)
5. Calendar events appear automatically

### 4.2 Before a Meeting
- Menu bar icon shows upcoming meetings (EventKit)
- Dropdown: next meeting with participants, "Start Capture" button, recent notes
- Auto-start option when calendar event with video link begins

### 4.3 During a Meeting
- **Floating notepad window** appears (always on top, resizable)
- User jots quick keywords/bullets (optional — guides AI later)
- Live transcript runs in background with speaker labels
- Audio waveform indicator shows capture is active
- Audio stored locally for playback
- **Minimized state:** floating pill — recording dot, timer, waveform, current speaker name
- Toggle: `Cmd+Shift+V`
- Pill is draggable, stays on top of all windows including fullscreen

### 4.4 Meeting Ends — Enhancement
- "Enhance Notes" screen appears with:
  - Meeting stats: duration, speakers, notes count, bookmarks
  - Speaker breakdown with talk-time percentages
  - Template picker: Standup, 1-on-1, Sales Call, Interview, General, Custom
  - AI provider dropdown: Platform AI / Your API Key / Local Ollama
- One click "Enhance Notes" or `Cmd+E`

### 4.5 Enhanced Notes — Block Editor
- Main app window opens with structured notes
- Block types: Summary, Decision, Action Item, Quote
- Each block has speaker attribution
- Quotes have audio timestamp links
- Slash commands to add new blocks: `/decision`, `/action`, `/quote`, `/heading`, `/text`
- Drag handles to reorder blocks
- Content is editable inline

### 4.6 Transcript Panel
- Right panel (340px), toggled via button or `Cmd+]`
- Audio player at top: play/pause, progress bar, speed controls (0.5x–2x)
- Full transcript with speaker labels and timestamps
- **Sync behavior:**
  - Currently playing segment highlighted with accent glow
  - Past segments dimmed
  - Word-level highlighting within active segment
  - Auto-scrolls as audio plays
- **Click any segment** → audio seeks to that timestamp
- **Attribution tags** on transcript lines show which note blocks they fed into (Quote, Action Item, Decision, Summary)
- **Click an attribution tag** → audio seeks + linked note block scrolls into view and glows

### 4.7 Chat
- Right panel (360px), toggled via Chat button
- Ask questions about the meeting: "What did Priya say about pricing?"
- AI responds with citations and transcript references
- Powered by same AI provider as enhancement

### 4.8 Sharing
- **Copy:** Rich text to clipboard
- **Share link:** Web-viewable hosted notes (paid)
- **Email:** Formatted notes in email body
- **Export:** PDF, Markdown
- **macOS Share Sheet:** AirDrop, Messages, Mail, etc.

### 4.9 Organization
- **Sidebar views:** All Notes, People, Companies, Action Items
- **Folders:** User-created, with subfolders
- **Spaces:** Team workspaces with access controls (paid)
- Notes auto-indexed under People & Companies

---

## 5. UI Design System

### 5.1 Design Philosophy
- **Calm and invisible.** The app should feel like it barely exists until you need it.
- **Linear meets Notion.** Linear's dark mode, typography, and spacing. Notion's block editor model.
- **User text is primary.** User-written content in primary text color. AI-generated content in secondary (gray).
- **Progressive disclosure.** Secondary metadata hidden until hover. Actions appear on interaction.

### 5.2 Color Palette

Cool-toned dark greys with blue undertone (hue ~240, 2-5% saturation).

| Token | Value | Usage |
|---|---|---|
| `--bg-app` | `#0A0A0B` | Deepest background |
| `--bg-sidebar` | `#111113` | Sidebar |
| `--bg-content` | `#18181B` | Content areas, blocks |
| `--bg-elevated` | `#1C1C1F` | Modals, dropdowns |
| `--bg-hover` | `rgba(255,255,255,0.05)` | Hover states |
| `--bg-active` | `rgba(255,255,255,0.08)` | Active/selected states |
| `--bg-accent` | `rgba(94,106,210,0.15)` | Accent backgrounds |
| `--text-primary` | `#EDEDEF` | Headings, primary content |
| `--text-secondary` | `#A0A0AB` | Descriptions, AI-generated text |
| `--text-tertiary` | `#6E6E7A` | Timestamps, placeholders |
| `--text-ghost` | `#4E4E59` | Subtle indicators |
| `--accent` | `#5E6AD2` | Primary actions, links, active nav |
| `--accent-hover` | `#6E7AE2` | Hover on accent |
| `--green` | `#4CB782` | Quotes, success, completed |
| `--red` | `#E5484D` | Action items, urgent |
| `--blue` | `#53A3F3` | Decisions, info |
| `--yellow` | `#F2C94C` | Warnings, in-progress |
| `--border` | `rgba(255,255,255,0.06)` | Subtle dividers |
| `--border-strong` | `rgba(255,255,255,0.10)` | Input borders |
| `--border-focus` | `rgba(94,106,210,0.5)` | Focus rings |

### 5.3 Typography

| Role | Size | Weight | Line Height | Spacing |
|---|---|---|---|---|
| Page title | 20px | 700 | 28px | -0.3px |
| Section heading | 14px | 600 | 20px | -0.1px |
| Body | 14px | 400 | 1.6 | 0 |
| Body medium | 14px | 500 | 1.6 | 0 |
| Caption | 12px | 400 | 16px | 0 |
| Label | 11px | 500 | 16px | 0.5px (uppercase) |
| Mono | 12px | 400 | 18px | 0 (JetBrains Mono) |

Font: Inter with `font-feature-settings: "cv02", "cv03", "cv04", "cv11"`

### 5.4 Spacing (4px grid)

| Token | Value |
|---|---|
| `--space-1` | 4px |
| `--space-2` | 8px |
| `--space-3` | 12px |
| `--space-4` | 16px |
| `--space-5` | 20px |
| `--space-6` | 24px |
| `--space-8` | 32px |

### 5.5 Border Radius

| Token | Value | Usage |
|---|---|---|
| `--radius-sm` | 4px | Tags, badges |
| `--radius-md` | 6px | Inputs, buttons |
| `--radius-lg` | 8px | Cards, blocks |
| `--radius-xl` | 12px | Modals |

### 5.6 Borders
- Never use opaque borders (`#333`). Always `rgba(255,255,255,0.06)` or `0.10`.
- Use `box-shadow: 0 0 0 1px rgba(255,255,255,0.06)` for card outlines.
- Separate sections with spacing, not lines.

### 5.7 Buttons

| Variant | Background | Color | Height |
|---|---|---|---|
| Primary | `#5E6AD2` | `#FFFFFF` | 32px |
| Secondary | `rgba(255,255,255,0.06)` | `#EDEDEF` | 32px |
| Tertiary | `transparent` | `#A0A0AB` | 32px |

Font: 13px, weight 500, padding 0 12px, border-radius 6px.

### 5.8 Motion

| Action | Duration | Easing |
|---|---|---|
| Hover color | 120ms | ease |
| Panel slide | 200ms | cubic-bezier(0.16, 1, 0.3, 1) |
| Modal enter | 150ms | scale(0.98) → scale(1) |

### 5.9 Block Editor

| Block Type | Left Border | Label Color |
|---|---|---|
| Summary | 3px `--accent` | `--accent` |
| Decision | 3px `--blue` | `--blue` |
| Action Item | 3px `--red` | `--red` |
| Quote | 3px `--green` | `--green` |

- Block padding: 14px 16px
- Block margin-bottom: 10px
- Block border-radius: 8px
- Block background: `--bg-content`
- Notes area max-width: 680px, centered
- User content: `--text-primary`
- AI-generated content: `--text-secondary`

---

## 6. Layout States

### Default (~600px content)
```
[Icon Sidebar 44px] [Notes (flex, max-width 680px centered)]
```

### With Transcript
```
[Icon Sidebar 44px] [Notes (flex)] [Transcript 340px]
```

### Expanded Sidebar
```
[Icon Sidebar 44px] [Full Sidebar 240px] [Notes (flex)]
```

### Full
```
[Icon Sidebar 44px] [Full Sidebar 240px] [Notes (flex)] [Transcript 340px]
```

Keyboard shortcuts: `Cmd+[` toggle sidebar, `Cmd+]` toggle transcript.

---

## 7. Differentiators vs. Granola

| Feature | Granola | Vaakya |
|---|---|---|
| Speaker identification | Weak / unreliable | Core feature with pyannote |
| Audio playback | No audio stored | Full playback with transcript sync |
| Offline mode | Requires internet for AI | Fully functional offline (Ollama) |
| Privacy | Cloud transcription | Local-first (MLX Whisper) |
| AI provider choice | Locked to their models | Platform / BYOK / Local |
| Action items | Plain text | Interactive checkboxes |
| Transcript attribution | No visual link | Tags linking transcript → note blocks |
| Free tier | 30-day history limit | Unlimited, genuinely useful |
| Android | No | Not at launch (possible later) |

---

## 8. Whisper Model Strategy

| Platform | Default Model | Size | RAM | Fallback |
|---|---|---|---|---|
| macOS (16GB+) | large-v3-turbo | 1.6GB | ~3.5GB | — |
| macOS (8GB) | medium | 769MB | ~3GB | — |
| iPhone | small | 466MB | ~1.2GB | base (older phones) |
| iPad (M-series) | medium | 769MB | ~3GB | small |

All models run via MLX Whisper using Apple's mlx-swift bindings for native Swift integration.

---

## 9. Prototype Reference

Interactive prototype: `.superpowers/brainstorm/59425-1774998729/content/vaakya-final.html`

This prototype demonstrates the full block editor, transcript panel with audio sync, tag-click-to-highlight, sidebar toggle, chat panel, share modal, and slash commands.
