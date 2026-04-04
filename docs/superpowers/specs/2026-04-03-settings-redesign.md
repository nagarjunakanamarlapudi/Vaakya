# Settings Redesign + UX Fixes — Design Spec

**Date:** 2026-04-03
**Status:** Approved
**Scope:** Complete Settings UI rewrite + 4 targeted UX fixes across the app

---

## 1. Problem

The current Settings has 5 tabs (General, Record, Calendar, AI & Models, Account) with inconsistent patterns — segmented pickers, card lists with "Use this" buttons, dropdowns, and toggles all mixed. The AI + Models merge cramped three unrelated concerns (AI provider, Whisper models, Speaker Diarization) into one scrollable tab. Calendar had its own tab for just 2 toggles. General had 3 unrelated settings. Delete All Data has no confirmation. "Diarize" is jargon. Button sizes are inconsistent.

## 2. Design Decisions

### 2.1 Structure: 3 Tabs

Collapse from 5 tabs to 3, grouped by user intent:

| Tab | Sections | Contents |
|-----|----------|----------|
| **Recording** | Audio Capture | System audio toggle, auto-start for calendar events, calendar integration |
| | Transcription | Radio list of Whisper models (quality-focused, no file sizes) |
| | Speaker Identification | Radio list of diarization engines (same pattern as Transcription) |
| **Intelligence** | AI Enhancement | Provider dropdown (Platform/OpenAI/Anthropic/Ollama) + conditional fields |
| | Automation | Auto-enhance toggle, default template dropdown |
| **Account** | Account | Signed-in: avatar + email + sign out. Signed-out: value prop + Apple/Google buttons |
| | Sync | Sync Now + last sync time + Wi-Fi status. Greyed at 45% opacity when signed out |
| | Preferences | Theme (segmented: Light/System/Dark), Launch at login toggle |
| | Danger Zone | Delete all data with confirmation dialog |

**Eliminated:** Calendar tab (→ Recording), General tab (→ split across Recording + Account).

### 2.2 Component Pattern: Hybrid

- **Related toggles** grouped into shared cards with thin dividers between rows (Apple System Settings style)
- **Standalone settings** get their own single-row card
- **Uppercase section labels** above card groups (11px, semibold, tertiary color, 0.5pt tracking)
- All cards: white background, 10px corner radius, subtle shadow (0 1px 3px black 8%)

### 2.3 Control Patterns (Standardized)

| Control Type | Pattern | Used For |
|--------------|---------|----------|
| On/off | Toggle (switch) right-aligned | System audio, auto-start, calendar, auto-enhance, launch at login |
| Pick one from few | Segmented picker inline | Theme (Light/System/Dark) — only 3 options |
| Pick one from many | Dropdown (menu picker) | AI provider, default template |
| Pick one from list | Radio-button rows | Whisper model, diarization engine |
| Text input | Inline text field in subtly indented area | API keys, Ollama URL, Ollama model |

**No more "Use this" buttons.** All single-select uses radio buttons or dropdowns.

### 2.4 Model/Engine Selection (Radio List)

Both Transcription and Speaker Identification use an identical radio-list pattern:

- Each option is a row with: radio button (left) → name → one-line quality description
- **Show quality, not sizes**: "Best accuracy", "Good accuracy", "Fast, basic"
- Active row has green-tinted background
- "Recommended" badge on the best option
- Selecting an undownloaded model triggers download automatically — radio row shows inline progress bar temporarily, then settles to selected state
- "Manage Downloads" expandable disclosure at bottom of Transcription section — shows all models with sizes and delete buttons. Collapsed by default.
- If auto-download fails, revert radio selection to the previous model and show a brief inline error ("Download failed — check your connection") that auto-dismisses after 5 seconds

### 2.5 AI Provider (Conditional Fields)

Provider is a dropdown (not segmented picker — 4 options is too many for segmented). When the provider changes, the card expands/collapses to show relevant fields:

| Provider | Fields Shown |
|----------|-------------|
| Platform | None (no setup needed) |
| OpenAI | API key (secure field with show/hide toggle) |
| Anthropic | API key (secure field with show/hide toggle) |
| Local Ollama | URL text field + Model name text field |

Conditional fields appear in a subtly indented area (light background) below the provider row, within the same card.

### 2.6 Account — Signed Out State

- Centered card with avatar placeholder, "Sign in to sync across devices" heading, value prop text
- Full-width stacked buttons: "Sign in with Apple" (black) and "Sign in with Google" (white with border)
- Sync section visible but greyed (45% opacity) with "Sign in to enable sync" subtitle
- Preferences and Danger Zone remain fully accessible (local-only features)

### 2.7 Delete Confirmation Dialog

The "Delete..." button in Danger Zone opens a confirmation dialog:
- Title: "Delete all data?"
- Body: "This will permanently delete **N meetings**, their transcripts, notes, and audio from this device. This cannot be undone."
- Buttons: "Cancel" (secondary) and "Delete Everything" (red, primary)

Danger Zone card has a red section label and subtle red border (rgba(234,67,53,0.15)).

### 2.8 No Save/Cancel Footer

Remove the current Save/Cancel footer. All settings auto-save on change — this is standard macOS behavior (System Settings does this). API keys save to Keychain on field blur. Toggles save immediately. Dropdowns save on selection.

## 3. UX Fixes (Same Scope)

### 3.1 "Diarize" → "Identify Speakers"

- Button label: "Identify Speakers"
- Progress state: "Identifying speakers... 3/12" with inline progress bar
- Applies in MeetingDetailView toolbar

### 3.2 "New Note" → "Record Meeting"

- Sidebar footer button label changes from "New Note" to "Record Meeting"
- The action creates a meeting and starts recording — the label should reflect that

### 3.3 Consistent Button Sizes

Standardize on two sizes from DesignTokens:

| Size | Height | Font | Corner Radius | Use |
|------|--------|------|---------------|-----|
| **Primary** | 36pt | 14px medium | 10px | Main CTAs: Sign in, Delete Everything, Sync Now |
| **Compact** | 28pt | 12px medium | 6px | Inline actions: Sign Out, Select, Download, Manage |

### 3.4 Delete Confirmation on Meeting Delete

Apply the same confirmation pattern to individual meeting deletion (sidebar context menu). Dialog: "Delete [meeting title]? This will remove the transcript, notes, and audio. This cannot be undone." with Cancel + Delete buttons.

## 4. Mockups

Interactive mockups saved in `.superpowers/brainstorm/79716-1775254010/content/`:
- `component-patterns.html` — Hybrid component pattern (approved)
- `recording-tab.html` — Full Recording tab layout
- `model-selection-pattern.html` — Radio list pattern for models (approved)
- `intelligence-account-tabs.html` — Intelligence + Account tabs (approved)
- `account-signed-out.html` — Signed out state (approved)

## 5. Files to Modify

| File | Action | What Changes |
|------|--------|-------------|
| `Sources/Views/SettingsView.swift` | Rewrite | New 3-tab structure, all sections, auto-save |
| `Sources/Views/MeetingDetailView.swift` | Edit | "Identify Speakers" label + progress state |
| `Sources/Views/SidebarView.swift` | Edit | "Record Meeting" label |
| `Sources/Theme/DesignTokens.swift` | Edit | Add `Button.compactHeight`, `Button.compactFontSize`, `Button.compactCornerRadius` |
| `Sources/Services/ModelManager.swift` | Edit | Auto-download on selection |

## 6. Out of Scope

- iOS SettingsView (separate pass after macOS is validated)
- Onboarding flow changes
- New settings additions (only reorganizing existing ones)
- Backend changes (all settings are client-side)
