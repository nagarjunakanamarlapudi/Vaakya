# Multilingual Meeting Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add transcript translation, multilingual notes enhancement, and language toggle UI — original always preserved, translations and notes cached per language.

**Architecture:** LLM translates transcripts and generates notes in chosen languages. Data model stores translations/notes as dictionaries keyed by language code. UI shows language toggles above transcript and notes panels.

**Tech Stack:** SwiftUI, existing AIService (Ollama/OpenAI/Anthropic), existing LocalStore filesystem

**Spec:** `docs/superpowers/specs/2026-04-05-multilingual-notes-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/Models/LocalModels.swift` | Modify | Add `translatedTranscripts`, `enhancedBlocks` dict, migrate `blocks` |
| `Sources/Services/AIPrompts.swift` | Modify | Add translate prompt, add language param to enhance/chat prompts |
| `Sources/Services/AIService.swift` | Modify | Add `translateTranscript()` method |
| `Sources/ViewModels/MeetingViewModel.swift` | Modify | Add translate/enhance-in-language methods |
| `Sources/Views/MeetingDetailView.swift` | Modify | Add language toggle above transcript and notes panels |
| `Sources/Views/ContextualSidebar.swift` | Modify | Chat respects notes language |
| `Sources/Views/SettingsView.swift` | Modify | Add "Notes Language" default in Intelligence tab |

---

### Task 1: Data Model — Add multilingual fields to MeetingDocument

**Files:**
- Modify: `VaakyaApp/Sources/Models/LocalModels.swift`

- [ ] **Step 1: Add new fields to MeetingDocument**

Add three new fields after the existing `blocks` field:

```swift
struct MeetingDocument: Codable, Identifiable, Sendable {
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
    var userNotes: String

    var transcript: [TranscriptSegmentData]
    var blocks: [BlockData]                                          // keep for backward compat
    var translatedTranscripts: [String: [TranscriptSegmentData]]     // NEW
    var enhancedBlocks: [String: [BlockData]]                        // NEW
    var notesLanguage: String?                                        // NEW
    var speakers: [SpeakerData]
```

- [ ] **Step 2: Update MeetingDocument init**

Add default values for the new fields in the `init`:

```swift
    init(id: String = UUID().uuidString, title: String, startedAt: Date = Date()) {
        // ... existing assignments ...
        self.blocks = []
        self.translatedTranscripts = [:]
        self.enhancedBlocks = [:]
        self.notesLanguage = nil
        self.speakers = []
    }
```

- [ ] **Step 3: Add backward-compatible decoding**

Add a custom `init(from decoder:)` to `MeetingDocument` so old JSON files (without the new fields) still load:

```swift
extension MeetingDocument {
    enum CodingKeys: String, CodingKey {
        case id, title, startedAt, endedAt, durationSeconds, speakerCount, source
        case participants, template, aiProvider, isEnhanced, lastModified, userNotes
        case transcript, blocks, translatedTranscripts, enhancedBlocks, notesLanguage, speakers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        speakerCount = try c.decodeIfPresent(Int.self, forKey: .speakerCount) ?? 0
        source = try c.decodeIfPresent(String.self, forKey: .source)
        participants = try c.decodeIfPresent([Participant].self, forKey: .participants)
        template = try c.decodeIfPresent(String.self, forKey: .template)
        aiProvider = try c.decodeIfPresent(String.self, forKey: .aiProvider)
        isEnhanced = try c.decodeIfPresent(Bool.self, forKey: .isEnhanced) ?? false
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
        userNotes = try c.decodeIfPresent(String.self, forKey: .userNotes) ?? ""
        transcript = try c.decodeIfPresent([TranscriptSegmentData].self, forKey: .transcript) ?? []
        blocks = try c.decodeIfPresent([BlockData].self, forKey: .blocks) ?? []
        speakers = try c.decodeIfPresent([SpeakerData].self, forKey: .speakers) ?? []

        // New fields with migration
        translatedTranscripts = try c.decodeIfPresent([String: [TranscriptSegmentData]].self, forKey: .translatedTranscripts) ?? [:]
        notesLanguage = try c.decodeIfPresent(String.self, forKey: .notesLanguage)

        // Migrate: if old `blocks` exist but no `enhancedBlocks`, move them to enhancedBlocks["en"]
        let decoded = try c.decodeIfPresent([String: [BlockData]].self, forKey: .enhancedBlocks)
        if let decoded, !decoded.isEmpty {
            enhancedBlocks = decoded
        } else if !blocks.isEmpty {
            enhancedBlocks = ["en": blocks]
        } else {
            enhancedBlocks = [:]
        }
    }
}
```

- [ ] **Step 4: Add helper to get active blocks**

Add a computed property to `MeetingDocument` that returns the blocks for the current notes language (falling back to `blocks` for compatibility):

```swift
extension MeetingDocument {
    /// Get blocks for the active notes language, falling back to the legacy `blocks` array.
    func activeBlocks(language: String? = nil) -> [BlockData] {
        let lang = language ?? notesLanguage ?? "en"
        return enhancedBlocks[lang] ?? blocks
    }

    /// Languages that have enhanced notes available.
    var availableNotesLanguages: [String] {
        Array(enhancedBlocks.keys).sorted()
    }

    /// Languages that have transcript translations available.
    var availableTranscriptLanguages: [String] {
        Array(translatedTranscripts.keys).sorted()
    }
}
```

- [ ] **Step 5: Update MeetingMetadata.from() to use enhancedBlocks**

In `MeetingMetadata.from(_:hasAudio:isPinned:...)`, update the block counting to use `enhancedBlocks`:

```swift
    static func from(_ doc: MeetingDocument, hasAudio: Bool = false,
                     isPinned: Bool = false, pinSortOrder: Int? = nil,
                     project: String? = nil, tags: [String] = []) -> MeetingMetadata {
        let activeBlocks = doc.activeBlocks()
        let blockCounts = Dictionary(grouping: activeBlocks, by: \.type)
            .mapValues { $0.count }
        let pending = activeBlocks.filter { $0.type == "action" && !$0.isChecked }.count
        // ... rest unchanged
    }
```

- [ ] **Step 6: Add notesLanguage to LocalSettings**

In the `LocalSettings` struct, add:

```swift
struct LocalSettings: Codable {
    // ... existing fields ...
    var notesLanguage: String = "en"      // NEW: global default for enhanced notes language
}
```

- [ ] **Step 7: Build to verify**

```bash
cd VaakyaApp && make build 2>&1 | grep -E "BUILD FAILED|error:" | head -5
```

Expected: Build succeeds. Existing meetings still load (backward compat via custom decoder).

- [ ] **Step 8: Commit**

```bash
git add VaakyaApp/Sources/Models/LocalModels.swift
git commit -m "feat: add multilingual fields to MeetingDocument

Add translatedTranscripts, enhancedBlocks (dict by language),
notesLanguage. Backward-compatible decoding migrates old blocks
to enhancedBlocks['en']. Add notesLanguage to LocalSettings.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: AI Layer — Translation prompt and language-aware enhance/chat

**Files:**
- Modify: `VaakyaApp/Sources/Services/AIPrompts.swift`
- Modify: `VaakyaApp/Sources/Services/AIService.swift`

- [ ] **Step 1: Add language parameter to enhancePrompt**

In `AIPrompts.swift`, change the `enhancePrompt` signature to accept a language:

```swift
    static func enhancePrompt(transcript: String, userNotes: String, template: String, language: String) -> String {
        let languageName = TranscriptionLanguage(rawValue: language)?.displayName ?? "English"
        return """
        You are a meeting notes assistant. Analyze this meeting transcript and produce structured notes.
        Produce all notes in \(languageName).

        IMPORTANT: You MUST respond with ONLY a valid JSON array. No code, no explanations, no markdown.

        Each element in the array must have these fields:
        - "type": "summary" or "decision" or "action" or "quote"
        - "content": a clear sentence describing what was said or decided (in \(languageName))
        - "speaker": the person's name (use null for summary)
        - "timestamp_seconds": null
        - "meta_text": null

        Example output for a short meeting:
        [
          {"type": "summary", "content": "The team discussed project deadlines and assigned tasks.", "speaker": null, "timestamp_seconds": null, "meta_text": null},
          {"type": "decision", "content": "Launch date set for April 15th.", "speaker": "Sarah", "timestamp_seconds": null, "meta_text": "Agreed by all"},
          {"type": "action", "content": "Prepare the launch presentation.", "speaker": "Mike", "timestamp_seconds": null, "meta_text": "Due next Monday"},
          {"type": "quote", "content": "We need to move fast on this.", "speaker": "Sarah", "timestamp_seconds": null, "meta_text": null}
        ]

        Now analyze this transcript and return ONLY a JSON array like the example above:

        <transcript>
        \(transcript)
        </transcript>

        <user_notes>
        \(userNotes.isEmpty ? "(none)" : userNotes)
        </user_notes>

        Template style: \(template)

        Respond with ONLY the JSON array in \(languageName). Nothing else.
        """
    }
```

- [ ] **Step 2: Add language parameter to chatPrompt**

```swift
    static func chatPrompt(transcript: String, message: String, language: String) -> String {
        let languageName = TranscriptionLanguage(rawValue: language)?.displayName ?? "English"
        return """
        You are a meeting notes assistant. The user is asking a question about a meeting transcript.
        Respond in \(languageName).

        <transcript>
        \(transcript)
        </transcript>

        <user_question>
        \(message)
        </user_question>

        Provide a clear, concise answer based only on the transcript. If the answer is not in the transcript, say so.
        Respond in \(languageName). Respond in plain text, not JSON.
        """
    }
```

- [ ] **Step 3: Add translatePrompt**

```swift
    static func translatePrompt(transcript: String, language: String) -> String {
        let languageName = TranscriptionLanguage(rawValue: language)?.displayName ?? "English"
        return """
        Translate this meeting transcript to \(languageName).
        Preserve speaker labels and timestamps exactly as they appear.
        Do NOT summarize or modify content — translate each segment verbatim.

        IMPORTANT: You MUST respond with ONLY a valid JSON array. No explanations, no markdown.

        Each element must have these fields:
        - "start": the timestamp in seconds (number)
        - "end": the end timestamp in seconds (number)
        - "text": the translated text
        - "speaker": the speaker label (keep unchanged)

        <transcript>
        \(transcript)
        </transcript>

        Respond with ONLY the JSON array. Nothing else.
        """
    }
```

- [ ] **Step 4: Update AIService.enhance to accept language**

In `AIService.swift`, update the `enhance` method signature:

```swift
    func enhance(transcript: [TranscriptSegmentData], userNotes: String, template: String,
                 settings: LocalSettings, language: String = "en") async throws -> [BlockData] {
```

Update the prompt construction line:

```swift
        let prompt = AIPrompts.enhancePrompt(transcript: transcriptText, userNotes: userNotes, template: template, language: language)
```

- [ ] **Step 5: Update AIService.chat to accept language**

```swift
    func chat(transcript: [TranscriptSegmentData], message: String,
              settings: LocalSettings, language: String = "en") async throws -> String {
```

Update the prompt construction:

```swift
        let prompt = AIPrompts.chatPrompt(transcript: transcriptText, message: message, language: language)
```

- [ ] **Step 6: Add translateTranscript method to AIService**

```swift
    func translateTranscript(transcript: [TranscriptSegmentData], targetLanguage: String,
                             settings: LocalSettings) async throws -> [TranscriptSegmentData] {
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        let transcriptText = transcript.map { seg in
            let speaker = seg.speaker.map { "[\($0)] " } ?? ""
            return "{\\"start\\": \(seg.start), \\"end\\": \(seg.end), \\"text\\": \\"\(speaker)\(seg.text)\\", \\"speaker\\": \\"\(seg.speaker ?? "")\\"},"
        }.joined(separator: "\n")

        let prompt = AIPrompts.translatePrompt(transcript: transcriptText, language: targetLanguage)

        let responseText: String
        switch settings.aiProvider {
        case "ollama":
            responseText = try await callOllama(prompt: prompt, settings: settings)
        case "openai":
            let key = KeychainService.load(key: "vaakya_openai_key") ?? ""
            responseText = try await callOpenAI(prompt: prompt, apiKey: key)
        case "anthropic":
            let key = KeychainService.load(key: "vaakya_anthropic_key") ?? ""
            responseText = try await callAnthropic(prompt: prompt, apiKey: key)
        case "platform":
            responseText = try await callPlatform(prompt: prompt, endpoint: "enhance")
        default:
            throw AIServiceError.unknownProvider(settings.aiProvider)
        }

        return parseTranscriptSegments(from: responseText, originalSegments: transcript)
    }

    private func parseTranscriptSegments(from text: String, originalSegments: [TranscriptSegmentData]) -> [TranscriptSegmentData] {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: "\n")
            jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        if let rangeStart = jsonString.range(of: "["),
           let rangeEnd = jsonString.range(of: "]", options: .backwards) {
            jsonString = String(jsonString[rangeStart.lowerBound...rangeEnd.lowerBound])
        }

        guard let data = jsonString.data(using: .utf8),
              let rawSegments = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // Fallback: return original with a note
            return originalSegments
        }

        return rawSegments.enumerated().map { index, raw in
            let original = index < originalSegments.count ? originalSegments[index] : nil
            return TranscriptSegmentData(
                id: original?.id ?? UUID().uuidString,
                start: raw["start"] as? Double ?? original?.start ?? 0,
                end: raw["end"] as? Double ?? original?.end ?? 0,
                text: raw["text"] as? String ?? "",
                speaker: raw["speaker"] as? String ?? original?.speaker,
                isConfirmed: true
            )
        }
    }
```

- [ ] **Step 7: Build to verify**

```bash
cd VaakyaApp && make build 2>&1 | grep -E "BUILD FAILED|error:" | head -5
```

- [ ] **Step 8: Commit**

```bash
git add VaakyaApp/Sources/Services/AIPrompts.swift VaakyaApp/Sources/Services/AIService.swift
git commit -m "feat: add translation and language-aware enhance/chat prompts

AIPrompts: add translatePrompt, language param to enhance/chat.
AIService: add translateTranscript() with JSON segment parsing.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: ViewModel — Translate and enhance-in-language methods

**Files:**
- Modify: `VaakyaApp/Sources/ViewModels/MeetingViewModel.swift`

- [ ] **Step 1: Update enhanceMeeting to accept language and store in enhancedBlocks**

Replace the existing `enhanceMeeting` method:

```swift
    func enhanceMeeting(meetingId: String, template: String? = nil, userNotes: String = "", language: String? = nil) async {
        guard var doc = LocalStore.shared.loadMeeting(id: meetingId) else {
            errorMessage = "Meeting not found"
            return
        }
        let settings = LocalStore.shared.loadSettings()
        let tmpl = template ?? settings.defaultTemplate
        let lang = language ?? settings.notesLanguage
        isLoadingBlocks = true

        do {
            let enhancedBlocks = try await AIService.shared.enhance(
                transcript: doc.transcript,
                userNotes: userNotes.isEmpty ? doc.userNotes : userNotes,
                template: tmpl,
                settings: settings,
                language: lang
            )
            doc.enhancedBlocks[lang] = enhancedBlocks
            doc.blocks = enhancedBlocks  // keep legacy field in sync
            doc.isEnhanced = true
            doc.notesLanguage = lang
            doc.aiProvider = settings.aiProvider
            LocalStore.shared.updateMeeting(doc)
            selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)

            if KeychainService.load(key: "access_token") != nil {
                Task {
                    do {
                        try await SyncService.shared.pushMeeting(id: meetingId)
                        try await SyncService.shared.pushIndex()
                    } catch {
                        print("[Sync] Push failed for \(meetingId): \(error)")
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingBlocks = false
    }
```

- [ ] **Step 2: Add translateTranscript method**

```swift
    var isTranslating = false

    func translateTranscript(meetingId: String, targetLanguage: String) async {
        guard var doc = LocalStore.shared.loadMeeting(id: meetingId) else {
            errorMessage = "Meeting not found"
            return
        }

        // Already translated — skip
        if doc.translatedTranscripts[targetLanguage] != nil { return }

        let settings = LocalStore.shared.loadSettings()
        isTranslating = true

        do {
            let translated = try await AIService.shared.translateTranscript(
                transcript: doc.transcript,
                targetLanguage: targetLanguage,
                settings: settings
            )
            doc.translatedTranscripts[targetLanguage] = translated
            LocalStore.shared.updateMeeting(doc)
            selectedMeeting = LocalStore.shared.loadMeeting(id: meetingId)
        } catch {
            errorMessage = "Translation failed: \(error.localizedDescription)"
        }

        isTranslating = false
    }
```

- [ ] **Step 3: Build and commit**

```bash
cd VaakyaApp && make build 2>&1 | grep -E "BUILD FAILED|error:" | head -5
git add VaakyaApp/Sources/ViewModels/MeetingViewModel.swift
git commit -m "feat: add translate and language-aware enhance to MeetingViewModel

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: UI — Language toggle on transcript panel

**Files:**
- Modify: `VaakyaApp/Sources/Views/MeetingDetailView.swift`

- [ ] **Step 1: Add state for selected transcript language**

Add to MeetingDetailView's state properties:

```swift
    @State private var selectedTranscriptLang: String = "original"
    @State private var showTranscriptLangPicker: Bool = false
```

- [ ] **Step 2: Add transcript language toggle view**

Create a helper view inside MeetingDetailView:

```swift
    @ViewBuilder
    private func transcriptLanguageToggle(meeting: MeetingDocument) -> some View {
        HStack(spacing: 4) {
            // "Original" tab — always present
            langTab("Original", isSelected: selectedTranscriptLang == "original") {
                selectedTranscriptLang = "original"
            }

            // Translated language tabs
            ForEach(meeting.availableTranscriptLanguages, id: \.self) { langCode in
                let name = TranscriptionLanguage(rawValue: langCode)?.displayName ?? langCode
                langTab(name, isSelected: selectedTranscriptLang == langCode) {
                    selectedTranscriptLang = langCode
                }
            }

            // "+" button to add translation
            Button(action: { showTranscriptLangPicker = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.bgCard))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showTranscriptLangPicker) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(TranscriptionLanguage.allCases.filter { $0 != .auto }, id: \.self) { lang in
                        if !meeting.availableTranscriptLanguages.contains(lang.code) && lang.code != "original" {
                            Button(lang.displayName) {
                                showTranscriptLangPicker = false
                                Task {
                                    await meetingVM.translateTranscript(meetingId: meeting.id, targetLanguage: lang.code)
                                    selectedTranscriptLang = lang.code
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func langTab(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accent.opacity(0.12) : Color.clear))
        }
        .buttonStyle(.plain)
    }
```

- [ ] **Step 3: Insert toggle above the transcript panel**

In the transcript section (around line 323), add the toggle above `TranscriptView`:

```swift
                if showTranscript {
                    Divider().opacity(0.5)
                    VStack(spacing: 0) {
                        if !meetingVM.isStreamingTranscription {
                            transcriptLanguageToggle(meeting: meeting)
                            Divider().opacity(0.3)
                        }
                        if meetingVM.isStreamingTranscription {
                            LiveTranscriptView(transcriptionService: meetingVM.transcriptionService)
                        } else if meetingVM.isTranslating {
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Translating...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            let segments: [TranscriptSegmentData] = {
                                if selectedTranscriptLang == "original" {
                                    return meeting.transcript
                                }
                                return meeting.translatedTranscripts[selectedTranscriptLang] ?? meeting.transcript
                            }()
                            let transcriptText = segments.map { seg in
                                let speaker = seg.speaker.map { "[\($0)] " } ?? ""
                                return "[\(seg.startFormatted)] \(speaker)\(seg.text)"
                            }.joined(separator: "\n")
                            TranscriptView(
                                transcript: transcriptText,
                                meetingId: meeting.id,
                                blocks: meetingVM.blocks,
                                diarizationSpeakers: diarizationSpeakers
                            )
                        }
                    }
                    .transition(.move(edge: .trailing))
                }
```

- [ ] **Step 4: Build and commit**

```bash
cd VaakyaApp && make build 2>&1 | grep -E "BUILD FAILED|error:" | head -5
git add VaakyaApp/Sources/Views/MeetingDetailView.swift
git commit -m "feat: add transcript language toggle with on-demand translation

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: UI — Language toggle on notes panel + update enhance to use language

**Files:**
- Modify: `VaakyaApp/Sources/Views/MeetingDetailView.swift`

- [ ] **Step 1: Add state for notes language**

```swift
    @State private var selectedNotesLang: String = "en"
    @State private var showNotesLangPicker: Bool = false
```

- [ ] **Step 2: Add notes language toggle view**

```swift
    @ViewBuilder
    private func notesLanguageToggle(meeting: MeetingDocument) -> some View {
        if !meeting.availableNotesLanguages.isEmpty {
            HStack(spacing: 4) {
                ForEach(meeting.availableNotesLanguages, id: \.self) { langCode in
                    let name = TranscriptionLanguage(rawValue: langCode)?.displayName ?? langCode
                    langTab(name, isSelected: selectedNotesLang == langCode) {
                        selectedNotesLang = langCode
                    }
                }

                Button(action: { showNotesLangPicker = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.bgCard))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showNotesLangPicker) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(TranscriptionLanguage.allCases.filter { $0 != .auto }, id: \.self) { lang in
                            if !meeting.availableNotesLanguages.contains(lang.code) {
                                Button(lang.displayName) {
                                    showNotesLangPicker = false
                                    Task {
                                        await meetingVM.enhanceMeeting(meetingId: meeting.id, language: lang.code)
                                        selectedNotesLang = lang.code
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                        }
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Block.padding)
            .padding(.vertical, 6)
        }
    }
```

- [ ] **Step 3: Insert notes toggle above the blocks section**

Find where blocks are rendered (around line 254 in MeetingDetailView) and add the toggle above them. Also update the blocks source to use the selected language:

The existing code references `meetingVM.blocks` or iterates blocks directly. Find all references to `doc.blocks` or the blocks rendering and wrap them with the language toggle, using `meeting.activeBlocks(language: selectedNotesLang)` instead of `meeting.blocks` or `doc.blocks`.

- [ ] **Step 4: Update the Enhance button to pass language**

Update the enhance button action (around line 106):

```swift
headerButton(icon: "sparkles", label: "Enhance", ...) {
    let settings = LocalStore.shared.loadSettings()
    Task { await meetingVM.enhanceMeeting(meetingId: meeting.id, userNotes: floatingNotes, language: settings.notesLanguage) }
}
```

- [ ] **Step 5: Sync selectedNotesLang when meeting loads**

Add an `.onChange` or `.onAppear` to set `selectedNotesLang` from the meeting's `notesLanguage`:

```swift
.onAppear {
    if let lang = meetingVM.selectedMeeting?.notesLanguage {
        selectedNotesLang = lang
    }
}
```

- [ ] **Step 6: Build and commit**

```bash
cd VaakyaApp && make build 2>&1 | grep -E "BUILD FAILED|error:" | head -5
git add VaakyaApp/Sources/Views/MeetingDetailView.swift
git commit -m "feat: add notes language toggle with per-language enhancement

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Chat language + Settings default

**Files:**
- Modify: `VaakyaApp/Sources/Views/ContextualSidebar.swift`
- Modify: `VaakyaApp/Sources/Views/SettingsView.swift`

- [ ] **Step 1: Update ContextualSidebar chat to pass language**

In `ContextualSidebar.swift`, find the `sendChat` function and update it to pass the notes language:

```swift
    private func sendChat(_ message: String) async {
        // ... existing setup ...
        let settings = LocalStore.shared.loadSettings()
        chatResponse = try await AIService.shared.chat(
            transcript: doc.transcript,
            message: text,
            settings: settings,
            language: settings.notesLanguage
        )
    }
```

- [ ] **Step 2: Add "Notes Language" to Settings Intelligence tab**

In `SettingsView.swift`, find the Intelligence tab and add a notes language picker. Add to the SettingsKey enum:

```swift
static let notesLanguage = "vaakya_notes_language"
```

Add state:

```swift
@State private var notesLanguage: String
```

Initialize:

```swift
_notesLanguage = State(initialValue: defaults.string(forKey: SettingsKey.notesLanguage) ?? "en")
```

Add the picker in the Intelligence tab section (reuse the `TranscriptionLanguage` enum, excluding `.auto`):

```swift
sectionLabel("Notes Language")
settingsCard {
    ForEach(TranscriptionLanguage.allCases.filter { $0 != .auto }) { lang in
        radioRow(
            title: lang.displayName,
            subtitle: lang.subtitle,
            isSelected: notesLanguage == lang.code,
            isRecommended: lang == .english
        ) {
            notesLanguage = lang.code
            saveSetting(SettingsKey.notesLanguage, value: lang.code)
            // Also save to LocalSettings for AIService
            var settings = LocalStore.shared.loadSettings()
            settings.notesLanguage = lang.code
            LocalStore.shared.saveSettings(settings)
        }
        if lang != TranscriptionLanguage.allCases.filter({ $0 != .auto }).last {
            Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)
        }
    }
}
```

- [ ] **Step 3: Build and commit**

```bash
cd VaakyaApp && make build 2>&1 | grep -E "BUILD FAILED|error:" | head -5
git add VaakyaApp/Sources/Views/ContextualSidebar.swift VaakyaApp/Sources/Views/SettingsView.swift
git commit -m "feat: add notes language to Settings + language-aware chat

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Integration testing and final verification

- [ ] **Step 1: Full build**

```bash
cd VaakyaApp && rm -rf DerivedData/Build && make build 2>&1 | grep -E "BUILD FAILED|error:" | head -5
```

- [ ] **Step 2: Test transcript translation**

1. Open the app, select an existing meeting with a transcript
2. Click the transcript toggle to show transcript panel
3. Verify "Original" tab and "+" button are visible
4. Click "+" → select "Hindi" → verify loading state → verify Hindi translation appears
5. Switch back to "Original" → verify original text
6. Switch to "Hindi" again → should be instant (cached)

- [ ] **Step 3: Test notes language**

1. Go to Settings > Intelligence > Notes Language → select "Hindi"
2. Go back to a meeting, click "Enhance Notes"
3. Verify notes appear in Hindi
4. Click "+" on notes toggle → select "English"
5. Verify English notes are generated
6. Switch between Hindi/English notes → instant

- [ ] **Step 4: Test chat language**

1. With notes language set to Hindi
2. Click "Summarize" in the sidebar
3. Verify response comes in Hindi

- [ ] **Step 5: Test backward compatibility**

1. Open an old meeting that was enhanced before the multilingual update
2. Verify existing English notes still display correctly
3. Verify no JSON decoding errors in console

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "fix: integration adjustments from multilingual testing

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```
