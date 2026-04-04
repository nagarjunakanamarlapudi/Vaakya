# Vaakya — Implementation Roadmap

## Completed

### Phase A: Local-First Data Layer ✅
- LocalModels (MeetingDocument, MeetingMetadata, BlockData, etc.)
- WALWriter (append-only log, fsync, crash safety)
- LocalStore (filesystem CRUD, in-memory index, 30s flush timer)
- AIService (client-side Ollama/OpenAI/Anthropic/Platform routing)
- ViewModel migration (all APIClient CRUD → LocalStore)
- App entry (no login required, model pre-load, loading screen)

### Phase B: AIService ✅ (merged into Phase A)
- Client calls AI providers directly (no server for Ollama/BYOK)
- Prompt templates ported from Python to Swift

### Phase C: ViewModel Migration ✅ (merged into Phase A)
- All views use local types (MeetingDocument, BlockData, etc.)
- Dashboard stats from LocalStore
- Settings from local filesystem

### Audio Pipeline ✅
- VoiceProcessingIO for hardware AEC (echo cancellation)
- ScreenCaptureKit for system audio capture
- Separate mic/system transcription (no mixing — clean separation)
- Transcript-level dedup as safety net
- WhisperKit chunk-based streaming (5s intervals)
- Real-time diarization (energy-based, 2-pass)

### Code Reviews ✅
- Audio expert review: 7/7 critical+high fixed
- Swift/macOS expert review: 10/10 critical+high fixed

### Phase D: Backend Simplification ✅
- Stripped FastAPI to 4 stateless routers (auth, enhance, share, sync)
- Deleted: models/, schemas/, db.py, alembic/, docker-compose.yml, DB routers
- Stateless JWT auth (no DB user creation)
- Enhance accepts transcript in request body (no DB read)
- Share uses signed JWT tokens (no DB lookup)
- Mangum Lambda adapter

### Phase E: SyncService ✅
- S3 sync via pre-signed URLs (SyncService.swift)
- Push/pull meetings, Wi-Fi-only audio sync
- Last-write-wins conflict resolution
- Sync triggers: sign-in, meeting save, app launch, manual button

### Phase F: Terraform ✅
- Lambda + API Gateway + S3 (replaced App Runner + RDS)
- Dockerfile.lambda, ECR, CloudFront, SSM, IAM
- Estimated cost: ~$4-5/mo (down from $22/mo)

---

### Phase G: Cloud Integration Testing ✅
**Tested on staging (2026-04-03).** All 11 tests pass.

**What to do:**
- Deploy Lambda + S3 via Terraform (`make deploy-dev`)
- Test auth flow: Sign in with Apple/Google → JWT issued → stored in Keychain
- Test sync: local meeting → push to S3 → verify in S3 → pull from another device/clean install
- Test share: create share link → open in browser → share viewer renders meeting
- Test platform AI: enhance via Lambda → Anthropic/OpenAI API → blocks returned
- Test audio sync: Wi-Fi pushes audio, cellular skips
- Test conflict: edit on two devices → last-write-wins
- Test offline → online transition: queue changes while offline, sync when back online
- Load test: 50+ meetings, verify sync performance
- Verify costs match estimate (~$4-5/mo)
- Security: verify S3 bucket is private, pre-signed URLs expire, JWT tokens validated

**Depends on:** Phases D + E + F all complete

---

### Sidebar Redesign ✅
- Two view modes: By Date (Today/Yesterday/This Week/Earlier) and By Project folders
- Pinned section with drag-to-reorder
- Status indicators (enhanced, action items, audio)
- Project folders with CRUD, color picker, drag-and-drop assignment
- Collapsible sections with persistent state
- Context menus for pin/unpin, move to project, delete

### Settings Redesign + UX Fixes ✅
- 3-tab Settings (Recording/Intelligence/Account) replacing 5 confusing tabs
- Hybrid component pattern: grouped rows + section labels
- Radio-list model selection (quality-focused, auto-download on select)
- Auto-save (no Save/Cancel footer)
- "Identify Speakers" (was "Diarize") with progress bar
- "Record Meeting" (was "New Note")
- Delete confirmation dialogs (all data + individual meetings)
- Consistent button sizes (primary 36pt + compact 28pt tokens)

### UI Polish ✅
- Dark mode: all colors now adaptive (NSColor/UIColor dynamic providers)
- ModelManager init spam removed
- Share feature: fixed URL construction, proper typed request
- Settings: appearance mode picker (System/Light/Dark)
- Entitlements + Info.plist updated for TestFlight
- 10 share tests (up from 5), 22/22 backend tests pass

---

## Post-Beta Polish (not blocking launch)

- [ ] 14 medium code review issues (unbounded buffers, prompt injection, force-unwraps, etc.)
- [ ] 11 low code review issues
- [ ] iOS testing on device/simulator
- [ ] TestFlight provisioning + App Store Connect
- [ ] VoiceProcessingIO → proper AEC with `kAudioUnitSubType_VoiceProcessingIO` multi-channel handling (done)
- [ ] Chunk interval tuning (5s → 10s for better Whisper accuracy)
- [ ] WhisperKit SpeakerKit integration (built-in pyannote, better than energy-based)
- [ ] Custom domain (GoDaddy → CloudFront/API Gateway)
