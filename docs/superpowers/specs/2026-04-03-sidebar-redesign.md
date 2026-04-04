# Sidebar Redesign — Grouped Meetings with Projects

**Date:** 2026-04-03
**Status:** Approved

## Problem

The meeting sidebar is a flat chronological list. With 10+ meetings it becomes a long undifferentiated scroll. Users have no way to organize, group, or prioritize meetings.

## Solution

Two switchable view modes (By Date / Projects), a Pinned section, collapsible groups, status indicators, and project labels.

---

## 1. View Modes

A segmented toggle below the search bar switches between two views:

| Mode | Grouping | Default |
|------|----------|---------|
| **By Date** | Today / Yesterday / This Week / Earlier | Yes |
| **Projects** | User-created project folders | No |

The selected mode persists in UserDefaults (`vaakya_sidebar_view_mode`).

## 2. Pinned Section

Appears at the top in **both** view modes. Meetings are pinned/unpinned via right-click context menu.

- Header: star icon + "Pinned" label + count badge + collapse chevron
- Pinned meetings show a left accent bar (green, 3px)
- Pin state stored in `MeetingMetadata.isPinned`

## 3. By Date View

Groups meetings into relative date sections:

| Section | Rule |
|---------|------|
| Today | `startedAt` is today |
| Yesterday | `startedAt` is yesterday |
| This Week | `startedAt` is within current calendar week, excluding today/yesterday |
| Earlier | Everything else |

Each section header:
- Collapse/expand chevron (▶/▼)
- Section label (uppercase, secondary color)
- Count badge (right-aligned)

Meetings in date view show a **project label pill** if assigned — small colored tag (e.g., blue "Engineering") next to the title. This provides project context without switching views.

## 4. Projects View

Groups meetings by user-created project folders.

### Folder visual treatment (Option B — SF Symbol + accent bar)
- `folder.fill` SF Symbol tinted to project color
- Project name in semibold
- Count (right-aligned, secondary)
- Collapse chevron
- Left accent bar (3px, project color) on expanded folders — hidden when collapsed

### Unlabeled section
- Appears at bottom, dimmed (opacity 0.6)
- Gray folder icon
- Contains all meetings with no assigned project

### Project CRUD
- **Create**: Right-click a meeting → "Move to Project" → "New Project..." → name + pick color
- **Assign**: Right-click → "Move to Project" → pick from list
- **Remove from project**: Right-click → "Remove from Project"
- **Rename/Delete project**: Right-click the project folder header

### Available project colors
6 preset colors matching the design system:
- Green (#34A853), Blue (#4285F4), Red (#EA4335), Yellow (#FBBC04), Purple (#9334E6), Teal (#00897B)

## 5. Status Indicators

Small icons on each meeting row, right-aligned after the title:

| Icon | Meaning | Source |
|------|---------|--------|
| ✦ (green) | AI-enhanced | `isEnhanced == true` |
| N⚡ (red) | Pending action items | `pendingActionItems > 0` |
| 🎤 (gray) | Has audio recording | `hasAudio == true` |

Use SF Symbols in implementation: `sparkle` for enhanced, `bolt.fill` for action items, `mic.fill` for audio.

## 6. Collapse State

- Each section's expand/collapse state persisted in UserDefaults
- Key format: `vaakya_section_collapsed_{sectionId}` (e.g., `vaakya_section_collapsed_today`, `vaakya_section_collapsed_project_engineering`)
- Default: Pinned and Today expanded, everything else expanded
- Collapse state remembered across app restarts

## 7. Data Model Changes

### MeetingMetadata additions
```swift
struct MeetingMetadata {
    // ... existing fields ...
    var isPinned: Bool       // new — default false
    var project: String?     // new — project name, nil = unlabeled
}
```

### Project storage
```swift
struct ProjectFolder: Codable, Identifiable {
    let id: String           // UUID
    var name: String
    var color: String         // hex string, e.g. "#4285F4"
    var sortOrder: Int
}
```

Stored in UserDefaults as JSON array under key `vaakya_project_folders`.

## 8. Context Menu

Right-click on a meeting row shows:

```
📌 Pin / Unpin
📁 Move to Project  ▶  [Engineering, Product, 1:1s, ...] / New Project...
🗑 Delete
```

Right-click on a project folder header:

```
✏️ Rename
🎨 Change Color     ▶  [6 color options]
🗑 Delete Project   (moves meetings to Unlabeled)
```

## 9. Drag-and-Drop

### Reorder pinned meetings
- Drag a pinned meeting up/down within the Pinned section to change sort order
- Sort order stored in `MeetingMetadata.pinSortOrder: Int?`
- Visual feedback: insertion line between items during drag

### Move meetings between projects
- Drag a meeting onto a project folder header to assign it to that project
- Drag onto "Unlabeled" to remove project assignment
- Visual feedback: folder highlights (background tint) when a valid drop target
- Works in both By Date and Projects views
- In By Date view, project folders appear as drop targets in a thin strip below the view toggle when dragging begins

### SwiftUI implementation
- Use `.draggable(meeting.id)` on meeting rows
- Use `.dropDestination(for: String.self)` on project folder headers and pinned section
- Use `onMove` modifier within pinned section for reordering

## 10. Search Behavior

Search works the same in both views — filters across all meetings regardless of grouping. Results displayed as a flat list (no section headers) when search text is non-empty.

## 10. Scope Boundaries

**In scope:**
- Segmented view toggle (By Date / Projects)
- Pinned section
- Collapsible date sections with count badges
- Project folders with CRUD
- Status indicators (enhanced, action items, audio)
- Project label pills in date view
- Context menus
- Drag-and-drop (reorder pinned meetings, move meetings between projects)
- Collapse state persistence

**Out of scope (post-beta):**
- Smart folders (auto-grouping by participants, source, etc.)
- Nested project sub-folders
- Keyboard shortcuts for pin/project assignment
