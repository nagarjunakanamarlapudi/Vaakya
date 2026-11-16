# Notch Indicator — Recording Status in the Notch

**Status:** implemented (spec updated 2026-11-15 to match the code)
**Date:** 2026-05-17
**Platform:** macOS only (iOS scope: none)
**Mocks:** [`docs/notch-indicator-mocks.html`](../../notch-indicator-mocks.html) — the initial design. Sizes and timings changed during implementation; the values below are what shipped.

## Goal

A glanceable, low-chrome recording-status indicator anchored to the MacBook Pro notch (or a draggable floating pill on Macs without one). Complements the existing `MenuBarExtra` icon.

## Behavior

| Trigger | What happens |
|---|---|
| Recording starts | Pill grows out of the notch showing red dot + `00:00` + waveform, holds 2.0s, retracts |
| Heartbeat (every 30s) while recording | If retracted, re-expands for 2.0s with the current `mm:ss` |
| Hover over the expanded pill while recording | Stays expanded; retracts 0.4s after the pointer leaves (see Known issues) |
| Click expanded pill (drag < 4pt) | Stops recording via the normal stop flow |
| Recording stops | Pill expands once with final time + grey dot, holds 1.0s, hides |
| Idle (not recording) | Nothing visible (on notched Macs a notch-sized black shape sits behind the bezel) |

**Resting state during recording**: retracted to notch width (merged with the notch on notched Macs, invisible on non-notch Macs), plus a thin pulsing red bar just below the notch so "still recording" stays visible between heartbeats.

## Relationship to the floating notepad

The floating notepad (`FloatingNotepad` via `FloatingPanelManager`) still opens when recording starts. It is where Quick Notes are typed, and `stopRecordingFlow()` passes those notes to `enhanceMeeting`. Its minimize-to-pill button and Cmd+Shift+V still work. The notch shows status; the notepad is for notes.

## Non-notch Macs

The pill is a free-floating black panel at the top-center of the screen by default.

- **Screen choice**: the first screen with a notch, otherwise the main screen
- **Summon for positioning** (only when not recording): pointer within 10pt of the screen top for 0.3s → pill fades in at 55% opacity, hides ~3s later
- **Drag**: click-and-drag the pill to move it horizontally (x only)
- **Snap**: soft-snap to top-center if released within 20pt
- **Persistence**: x position saved in `UserDefaults` under `notchIndicator.position.x.id.<displayID>` (the `NSScreenNumber` display ID, which stays unique across identical monitors, unlike `localizedName`)

## Architecture

New folder: `VaakyaApp/Sources/macOS/NotchIndicator/`

| File | Responsibility |
|---|---|
| `NotchIndicatorController.swift` | `@MainActor @Observable` state machine. Owns the panel, drives transitions, manages heartbeat / retract / hide / summon timers, global mouse monitor, screen-change handling. |
| `NotchIndicatorWindow.swift` | `NSPanel` subclass: borderless, non-activating, transparent, `.statusBar` level, never key or main. Mouse passthrough toggled by state. |
| `NotchIndicatorView.swift` | `NotchPresentation` model + SwiftUI view — pill shape, expand/retract animation, under-notch recording bar, hover, click-vs-drag. |
| `NotchWaveformView.swift` | 6-bar mic-level visualizer driven by `AudioRecorder.currentAmplitude`. |
| `NotchGeometry.swift` | Sizes, notch detection (`safeAreaInsets.top > 0`), screen choice, default frame, summon hot zone. |
| `NotchPositionStore.swift` | UserDefaults wrapper for per-display saved x positions. |

All files wrapped in `#if os(macOS)`.

## State machine

Modes (`NotchPresentation.Mode`): `hidden`, `summonedIdle`, `expandedRecording`, `expandedStop`. There is no separate retracted mode — `hidden` is the resting state while recording.

```
hidden             ── recording starts ──→ expandedRecording ── 2.0s ──→ hidden
hidden             ── heartbeat (30s, recording) ──→ expandedRecording ── 2.0s ──→ hidden
expandedRecording  ── hover in ──→ stays expanded (retract cancelled)
expandedRecording  ── hover out ──→ hidden after 0.4s
expandedRecording  ── click (drag < 4pt) ──→ posts .stopRecording
any                ── recording stops ──→ expandedStop ── 1.0s ──→ hidden
hidden             ── pointer at top edge 0.3s (non-notch, idle) ──→ summonedIdle ── ~3s ──→ hidden
```

## Data wiring

- `AudioRecorder` gained `static let shared`. `MainView`, `iOSMainView`, the menu bar in `VaakyaApp`, and the notch all use it, so the notch observes the instance that is actually recording (and the menu bar icon now reflects real recording state too).
- The controller observes `isRecording`, `recordingDuration` and `currentAmplitude` with `withObservationTracking`, re-registering after every change. Edges on `isRecording` drive the start/stop transitions.
- `VaakyaApp` creates and installs the controller once the app is ready.
- Clicking the pill posts the new `Notification.Name.stopRecording`. `MeetingDetailView` handles it by running `stopRecordingFlow()` (stop audio and streaming transcription, save, diarize, enhance).

## Window mechanics

- Frame: fixed 360 × 44pt (the expanded pill width), so the pill grows inside the panel without resizing it
- Position: top edge at `screen.frame.maxY`, centered on the notch (or the saved x on non-notch screens)
- Level: `.statusBar` (above the menu bar)
- Collection behavior: `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, `.ignoresCycle`
- Mouse events: ignored in `hidden`; received in `summonedIdle`, `expandedRecording` and `expandedStop`
- Repositions on `NSApplication.didChangeScreenParametersNotification`; if no screen exists at launch, install is retried on the next screen change

## Visual spec

- Pill: black, 32pt tall, bottom corners 16pt continuous radius, square top
- Width: 180pt collapsed (the notch) → 360pt expanded. Content sits beside the notch: dot + duration in the 90pt to the left, waveform in the 90pt to the right
- Animation: `.spring(response: 0.36, dampingFraction: 0.82)` for mode changes; content fades with `.easeOut(duration: 0.18)`
- Red dot: `#FF3B30`, 9pt, soft glow, pulsing while recording
- Duration: system font 12pt medium, monospaced digits, white, `mm:ss`
- Waveform: 6 white capsule bars, 3pt wide, 3pt apart, 3–14pt tall
- Stop dot: grey (`Color(white: 0.4)`), no glow, no pulse
- Under-notch recording bar: 44 × 3pt red capsule with glow, pulsing, hidden while the pill is expanded
- Opacity: `hidden` is opaque on notched Macs (blends into the notch) and invisible on non-notch Macs; `summonedIdle` is 55%

## Known issues

- **Hover doesn't reveal the pill from rest.** The panel ignores mouse events in `hidden` (`NotchIndicatorController.refreshIgnoresMouse`), so hovering the notch while retracted does nothing. Hover only keeps an already-expanded pill open (after start or a heartbeat). Fixing it needs a hit-test approach that doesn't swallow clicks on menu bar items beside the notch, and testing on hardware.

## Testing

- Manual on a notched MacBook: start pop-out, retract + red bar, 30s heartbeat, hover keeps it open, click stops recording, stop state
- Manual: Quick Notes typed in the floating notepad reach the AI notes after stopping
- Manual on an external (non-notch) display: summon, drag, snap, per-display persistence
- Compile-time: macOS and iOS builds must succeed
- No new test infra

## Out of scope / follow-ups

- Right-click "Reset to top-center" on the floating pill (`NotchPositionStore.reset(for:)` exists; no UI yet)
- Hover-to-reveal from rest (see Known issues)
- iOS support (no notch on iOS — Dynamic Island is iPhone-only API, not in our scope)
- Custom audio reactive colors / themes
- Multi-recording stack (we only handle one active recording)
- Configurable heartbeat interval (30s hard-coded; revisit if asked)
