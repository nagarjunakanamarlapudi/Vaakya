# Multilingual Meeting Notes — Design Spec

**Date:** 2026-04-05
**Status:** Approved

## Goal

Support multilingual meeting workflows: transcription in the spoken language, on-demand transcript translation to any supported language, and enhanced notes generated in a chosen language. Original content always preserved — translations and notes are layers on top.

## Target Users

Indian professionals who speak in Hindi/Telugu/Tamil/Kannada but need meeting notes in English for documentation and sharing. Also supports the reverse (English meetings, notes in regional languages).

## Supported Languages

- English (en) — American, British, Indian English
- Hindi (hi) — हिन्दी
- Telugu (te) — తెలుగు
- Tamil (ta) — தமிழ்
- Kannada (kn) — ಕನ್ನಡ
- Auto-detect (transcription only)

## Architecture

Four independent layers, each preserving its output:

```
Layer 1: Transcription (Whisper)
    Speech → raw text segments in spoken language
    Stored in meeting.transcript
    Runs during recording (real-time streaming or chunk-based)

Layer 2: Diarization (SpeakerKit / ONNX pyannote)
    Raw segments → speaker-labeled segments ("Speaker 1", "Sarah", etc.)
    Writes speaker labels back to meeting.transcript
    Runs after recording stops (post-processing)
    Speaker names can be edited by user after identification

Layer 3: Transcript Translation (LLM)
    Speaker-labeled transcript → translated transcript in chosen language
    Speaker labels, timestamps, and segment structure preserved verbatim
    Stored in meeting.translatedTranscripts[langCode]
    On-demand, cached after first translation
    Multiple languages can coexist

Layer 4: Enhanced Notes (LLM)
    Speaker-labeled transcript → structured notes in chosen language
    Speaker names carried into decisions, actions, quotes
    Stored in meeting.enhancedBlocks[langCode]
    Multiple language versions can coexist
```

Layers 1-2 run automatically during/after recording. Layers 3-4 are user-initiated and on-demand. Translation (Layer 3) always uses the diarized transcript (Layer 2 output) so speaker attribution is preserved through translation.

## Data Model Changes

### MeetingDocument

```swift
struct MeetingDocument: Codable {
    // ... existing fields ...
    var transcript: [TranscriptSegmentData]           // original, immutable
    var translatedTranscripts: [String: [TranscriptSegmentData]]  // NEW: "en" → [...], "hi" → [...]
    var enhancedBlocks: [String: [BlockData]]          // NEW: replaces `blocks: [BlockData]`
    var notesLanguage: String?                          // NEW: language used for current enhancement
    // ... existing fields ...
}
```

- `translatedTranscripts` — dictionary keyed by language code. Each value is the same segment format as the original transcript. Populated on-demand when user requests a language.
- `enhancedBlocks` — dictionary keyed by language code. Replaces the current single `blocks` array. Each value is a full set of enhanced blocks (summary, decisions, actions, quotes).
- `notesLanguage` — tracks which language version is currently active/displayed.
- `transcript` — never modified after recording. Always the original spoken language.

### Migration

Existing meetings with `blocks: [BlockData]` migrate to `enhancedBlocks: { "en": blocks }` (assume English since all existing notes were generated in English).

## UI Changes

### Transcript Panel — Language Toggle

A segmented control above the transcript:

```
[ Original ] [ English ] [ Hindi ] [ + ]
```

- **Original** — always present, shows the raw Whisper transcript
- **Translated languages** — appear as they're created, instant switching from cache
- **"+" button** — shows a picker to translate to a new language
- **First tap on new language** — loading spinner while LLM translates, then cached and displayed
- **Subsequent taps** — instant from cache

### Enhanced Notes — Language Toggle

Same pattern above the notes section:

```
[ English ] [ Telugu ] [ + ]
```

- Shows languages that notes have been enhanced in
- "+" triggers enhancement in a new language (LLM call)
- Switching between existing versions is instant
- Each version is a full set of blocks (summary, decisions, actions, quotes)

### Settings > Intelligence — Global Default

```
Notes Language: [ English ▼ ]
```

- Dropdown: English, Hindi, Telugu, Tamil, Kannada
- Used as the default when clicking "Enhance Notes"
- Per-meeting "+" override takes precedence
- Stored in UserDefaults via SettingsKey

## LLM Prompts

### Transcript Translation

```
Translate this meeting transcript to {language}.
Preserve speaker labels, timestamps, and segment structure.
Do NOT summarize or modify content — translate verbatim.
Return a JSON array of segments with the same structure as the input.
```

Input: original `[TranscriptSegmentData]` formatted as `[timestamp] [speaker] text`
Output: same format, text translated, speaker names and timestamps preserved.

### Enhanced Notes (existing prompt, modified)

Add one line to the existing enhance prompt:

```
Produce all notes in {language}.
```

The LLM reads the original transcript (any language) and generates structured notes in the chosen language. No separate translation step — the LLM handles cross-language enhancement natively.

### Chat / Ask Vaakya

Add to the chat system prompt:

```
Respond in {language}.
```

Sidebar chat ("List action items", "Summarize", freeform questions) responds in the current notes language.

## Flow

### Recording
1. Whisper transcribes in the spoken language (auto-detect or user-selected)
2. Original transcript stored in `meeting.transcript`
3. No translation happens automatically

### Viewing Transcript
1. Default: shows original transcript
2. User taps "+" on language toggle → picks "English"
3. LLM translates full transcript → stored in `translatedTranscripts["en"]`
4. Toggle now shows `[ Original ] [ English ]`
5. User can add more languages — each cached independently

### Enhancing Notes
1. User clicks "Enhance Notes"
2. Notes generated in the global default language (e.g., English)
3. Stored in `enhancedBlocks["en"]`
4. User can later "+" to enhance in Telugu → `enhancedBlocks["te"]`
5. Both versions persist, switch via toggle

### Sharing
- Copy/Email/Slack use whichever language version is currently active in the UI
- No separate language selection for sharing

## Files Changed

### Data Model
- `Sources/Models/LocalModels.swift` — add `translatedTranscripts`, `enhancedBlocks` to MeetingDocument, migration from `blocks`

### AI Layer
- `Sources/Services/AIPrompts.swift` — add translate prompt, add language parameter to enhance/chat prompts
- `Sources/Services/AIService.swift` — add `translateTranscript()` method

### Views
- `Sources/Views/MeetingDetailView.swift` — language toggle above transcript panel and notes panel
- `Sources/Views/ContextualSidebar.swift` — chat respects notes language
- `Sources/Views/SettingsView.swift` — add "Notes Language" default in Intelligence tab

### ViewModel
- `Sources/ViewModels/MeetingViewModel.swift` — update enhance/translate methods to use language-keyed storage

## Not in Scope

- Real-time translation during recording (translate after recording completes)
- Whisper fine-tuned models for Indian languages (use stock large-v3-turbo)
- Language detection on existing transcript (user selects manually)
- Translation of user's floating notes (only transcript and enhanced notes)
