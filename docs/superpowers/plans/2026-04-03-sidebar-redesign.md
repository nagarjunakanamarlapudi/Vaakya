# Sidebar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat meeting list sidebar with grouped views (By Date / By Project), pinned meetings, collapsible sections, status indicators, and drag-and-drop.

**Architecture:** Add `isPinned`, `pinSortOrder`, and `project` fields to `MeetingMetadata`. Store project folders in UserDefaults. Refactor `SidebarView` into composable subviews: `SidebarViewModeToggle`, `SidebarSectionHeader`, `SidebarMeetingRow`, `SidebarDateView`, `SidebarProjectView`. All grouping/filtering is computed from the existing `LocalStore.shared.meetings` array.

**Tech Stack:** SwiftUI (macOS 14+), `@Observable`, `.draggable`/`.dropDestination`, `DisclosureGroup`-like custom sections, UserDefaults for persistence.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/Models/LocalModels.swift` | Modify | Add `isPinned`, `pinSortOrder`, `project` to `MeetingMetadata`; add `ProjectFolder` struct |
| `Sources/Services/LocalStore.swift` | Modify | Add `projects` list, `saveProjects()`, `updateMetadata()` methods |
| `Sources/Views/SidebarView.swift` | Rewrite | Compose from subviews, add view mode toggle, context menus, drag-and-drop |
| `Sources/Views/Sidebar/SidebarMeetingRow.swift` | Create | Single meeting row with status indicators and project pill |
| `Sources/Views/Sidebar/SidebarSectionHeader.swift` | Create | Collapsible section header (date sections + project folders) |
| `Sources/Views/Sidebar/SidebarDateView.swift` | Create | By Date grouped list (Today/Yesterday/This Week/Earlier) |
| `Sources/Views/Sidebar/SidebarProjectView.swift` | Create | By Project folder list with CRUD |
| `Sources/Views/Sidebar/ProjectEditorSheet.swift` | Create | Create/rename project sheet with color picker |

---

### Task 1: Data Model — Add fields to MeetingMetadata + ProjectFolder

**Files:**
- Modify: `Sources/Models/LocalModels.swift`

- [ ] **Step 1: Add new fields to MeetingMetadata**

In `Sources/Models/LocalModels.swift`, add three fields to `MeetingMetadata` after `hasAudio`:

```swift
struct MeetingMetadata: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var startedAt: Date
    var durationSeconds: Int?
    var speakerCount: Int
    var source: String?
    var participantNames: [String]
    var blockCounts: [String: Int]
    var pendingActionItems: Int
    var isEnhanced: Bool
    var lastModified: Date
    var hasAudio: Bool
    var isPinned: Bool
    var pinSortOrder: Int?
    var project: String?
    // ... rest unchanged
```

- [ ] **Step 2: Update MeetingMetadata.from() factory**

Update the `from(_ doc:)` factory to include the new fields with defaults. Since `isPinned`/`project` are metadata-only (not part of `MeetingDocument`), the factory should accept them as parameters:

```swift
static func from(_ doc: MeetingDocument, hasAudio: Bool = false,
                 isPinned: Bool = false, pinSortOrder: Int? = nil,
                 project: String? = nil) -> MeetingMetadata {
    let blockCounts = Dictionary(grouping: doc.blocks, by: \.type)
        .mapValues { $0.count }
    let pending = doc.blocks.filter { $0.type == "action" && !$0.isChecked }.count
    return MeetingMetadata(
        id: doc.id,
        title: doc.title,
        startedAt: doc.startedAt,
        durationSeconds: doc.durationSeconds,
        speakerCount: doc.speakerCount,
        source: doc.source,
        participantNames: doc.participants?.map(\.name) ?? [],
        blockCounts: blockCounts,
        pendingActionItems: pending,
        isEnhanced: doc.isEnhanced,
        lastModified: doc.lastModified,
        hasAudio: hasAudio,
        isPinned: isPinned,
        pinSortOrder: pinSortOrder,
        project: project
    )
}
```

- [ ] **Step 3: Add ProjectFolder struct**

Add after the `LocalSettings` struct at the bottom of the file:

```swift
// MARK: - Project Folder

struct ProjectFolder: Codable, Identifiable {
    let id: String
    var name: String
    var color: String  // hex, e.g. "#4285F4"
    var sortOrder: Int

    init(id: String = UUID().uuidString, name: String, color: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
    }

    static let presetColors: [(name: String, hex: String)] = [
        ("Green", "#34A853"), ("Blue", "#4285F4"), ("Red", "#EA4335"),
        ("Yellow", "#FBBC04"), ("Purple", "#9334E6"), ("Teal", "#00897B"),
    ]
}
```

- [ ] **Step 4: Build and verify**

Run: `cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build 2>&1 | tail -5`
Expected: Build errors in `LocalStore.swift` where `MeetingMetadata` is constructed without the new fields. This is expected — we fix it in Task 2.

- [ ] **Step 5: Fix LocalStore compilation**

In `Sources/Services/LocalStore.swift`, find every call to `MeetingMetadata.from(...)` and add the new default parameters. There should be two call sites (in `createMeeting` and `updateMeeting`). Since the factory has defaults, the existing calls should compile. But also find the `initialize()` method where metadata is loaded from the index JSON — the decoder needs to handle missing fields.

Add `CodingKeys` with defaults to `MeetingMetadata` for backward-compatible decoding. In `LocalModels.swift`, add:

```swift
// Add to MeetingMetadata, after the existing properties
init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    title = try c.decode(String.self, forKey: .title)
    startedAt = try c.decode(Date.self, forKey: .startedAt)
    durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
    speakerCount = try c.decode(Int.self, forKey: .speakerCount)
    source = try c.decodeIfPresent(String.self, forKey: .source)
    participantNames = try c.decodeIfPresent([String].self, forKey: .participantNames) ?? []
    blockCounts = try c.decodeIfPresent([String: Int].self, forKey: .blockCounts) ?? [:]
    pendingActionItems = try c.decodeIfPresent(Int.self, forKey: .pendingActionItems) ?? 0
    isEnhanced = try c.decodeIfPresent(Bool.self, forKey: .isEnhanced) ?? false
    lastModified = try c.decode(Date.self, forKey: .lastModified)
    hasAudio = try c.decodeIfPresent(Bool.self, forKey: .hasAudio) ?? false
    isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    pinSortOrder = try c.decodeIfPresent(Int.self, forKey: .pinSortOrder)
    project = try c.decodeIfPresent(String.self, forKey: .project)
}
```

- [ ] **Step 6: Build and verify clean**

Run: `cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add VaakyaApp/Sources/Models/LocalModels.swift VaakyaApp/Sources/Services/LocalStore.swift
git commit -m "feat(sidebar): add isPinned, project fields to MeetingMetadata + ProjectFolder model"
```

---

### Task 2: LocalStore — Project folder CRUD + metadata updates

**Files:**
- Modify: `Sources/Services/LocalStore.swift`

- [ ] **Step 1: Add project storage to LocalStore**

In `LocalStore`, add after the existing private properties:

```swift
// MARK: - Projects

private let projectsKey = "vaakya_project_folders"

private(set) var projects: [ProjectFolder] = []

func loadProjects() {
    guard let data = UserDefaults.standard.data(forKey: projectsKey),
          let decoded = try? JSONDecoder().decode([ProjectFolder].self, from: data) else {
        return
    }
    projects = decoded.sorted(by: { $0.sortOrder < $1.sortOrder })
}

func saveProjects() {
    if let data = try? JSONEncoder().encode(projects) {
        UserDefaults.standard.set(data, forKey: projectsKey)
    }
}
```

- [ ] **Step 2: Add project CRUD methods**

```swift
func addProject(_ project: ProjectFolder) {
    var p = project
    p.sortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
    projects.append(p)
    saveProjects()
}

func deleteProject(id: String) {
    projects.removeAll { $0.id == id }
    // Unassign meetings from deleted project
    for i in meetings.indices where meetings[i].project == id {
        meetings[i].project = nil
    }
    saveProjects()
    flushIndex()
}

func renameProject(id: String, name: String) {
    if let idx = projects.firstIndex(where: { $0.id == id }) {
        projects[idx].name = name
        saveProjects()
    }
}

func changeProjectColor(id: String, color: String) {
    if let idx = projects.firstIndex(where: { $0.id == id }) {
        projects[idx].color = color
        saveProjects()
    }
}
```

- [ ] **Step 3: Add meeting metadata mutation methods**

```swift
// MARK: - Meeting Metadata Mutations (sidebar-only, no document change)

func togglePin(meetingId: String) {
    guard let idx = meetings.firstIndex(where: { $0.id == meetingId }) else { return }
    meetings[idx].isPinned.toggle()
    if !meetings[idx].isPinned { meetings[idx].pinSortOrder = nil }
    flushIndex()
}

func setPinOrder(meetingId: String, order: Int) {
    guard let idx = meetings.firstIndex(where: { $0.id == meetingId }) else { return }
    meetings[idx].pinSortOrder = order
    flushIndex()
}

func assignProject(meetingId: String, projectId: String?) {
    guard let idx = meetings.firstIndex(where: { $0.id == meetingId }) else { return }
    meetings[idx].project = projectId
    flushIndex()
}
```

- [ ] **Step 4: Call loadProjects in initialize()**

In `LocalStore.initialize()`, add `loadProjects()` after loading meetings from the index:

Find the line after `self.meetings = ...` in `initialize()` and add:
```swift
loadProjects()
```

- [ ] **Step 5: Build and verify**

Run: `cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add VaakyaApp/Sources/Services/LocalStore.swift
git commit -m "feat(sidebar): project folder CRUD + pin/assign methods in LocalStore"
```

---

### Task 3: SidebarMeetingRow — Shared meeting row with status indicators

**Files:**
- Create: `Sources/Views/Sidebar/SidebarMeetingRow.swift`

- [ ] **Step 1: Create the Sidebar directory**

```bash
mkdir -p /Users/nagarjuna/projects/meeting_genie/VaakyaApp/Sources/Views/Sidebar
```

- [ ] **Step 2: Create SidebarMeetingRow.swift**

```swift
#if os(macOS)
import SwiftUI

struct SidebarMeetingRow: View {
    let meeting: MeetingMetadata
    let isSelected: Bool
    var showProjectPill: Bool = false
    var projectColor: Color? = nil
    var projectName: String? = nil
    var isPinnedView: Bool = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.space3) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space1) {
                // Title + status indicators
                HStack(spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Status indicators
                    if meeting.isEnhanced {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.vaGreen)
                    }
                    if meeting.pendingActionItems > 0 {
                        HStack(spacing: 1) {
                            Text("\(meeting.pendingActionItems)")
                                .font(.system(size: 9, weight: .semibold))
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 7))
                        }
                        .foregroundStyle(Color.vaRed)
                    }
                    if meeting.hasAudio {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                // Subtitle row
                HStack(spacing: DesignTokens.Spacing.space2) {
                    Text(meeting.formattedDate)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)

                    if meeting.speakerCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "person.2")
                                .font(.system(size: 9))
                            Text("\(meeting.speakerCount)")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Color.textTertiary)
                    }

                    if let source = meeting.source, !source.isEmpty {
                        MeetingSourceTag(source: source)
                    }

                    // Project pill (in date view)
                    if showProjectPill, let name = projectName, let color = projectColor {
                        Text(name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color.opacity(0.12))
                            )
                    }
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.space4)
        .padding(.vertical, DesignTokens.Spacing.space2 + 2)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(isSelected ? Color.accent.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            if isPinnedView {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.vaGreen)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
    }
}
#endif
```

- [ ] **Step 3: Build and verify**

Run: `cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add VaakyaApp/Sources/Views/Sidebar/SidebarMeetingRow.swift
git commit -m "feat(sidebar): add SidebarMeetingRow with status indicators and project pill"
```

---

### Task 4: SidebarSectionHeader — Collapsible section header

**Files:**
- Create: `Sources/Views/Sidebar/SidebarSectionHeader.swift`

- [ ] **Step 1: Create SidebarSectionHeader.swift**

```swift
#if os(macOS)
import SwiftUI

struct SidebarSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool
    var count: Int = 0
    var icon: String? = nil
    var iconColor: Color? = nil
    var isFolderStyle: Bool = false
    var accentColor: Color = Color.textTertiary
    var dimmed: Bool = false

    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack(spacing: 8) {
                // Chevron
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 10)

                // Icon (folder or custom)
                if let icon = icon {
                    if isFolderStyle {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundStyle(iconColor ?? Color.textTertiary)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 11))
                            .foregroundStyle(iconColor ?? Color.textTertiary)
                    }
                }

                // Title
                if isFolderStyle {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(dimmed ? Color.textTertiary : Color.textPrimary)
                } else {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()

                // Count
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            if isFolderStyle && isExpanded {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
    }
}
#endif
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add VaakyaApp/Sources/Views/Sidebar/SidebarSectionHeader.swift
git commit -m "feat(sidebar): add SidebarSectionHeader — collapsible with icon, count, folder style"
```

---

### Task 5: SidebarDateView — By Date grouped list

**Files:**
- Create: `Sources/Views/Sidebar/SidebarDateView.swift`

- [ ] **Step 1: Create SidebarDateView.swift**

```swift
#if os(macOS)
import SwiftUI

struct SidebarDateView: View {
    let meetings: [MeetingMetadata]
    let projects: [ProjectFolder]
    let selectedId: String?
    let onSelect: (MeetingMetadata) -> Void

    @State private var pinnedExpanded = true
    @State private var todayExpanded = true
    @State private var yesterdayExpanded = true
    @State private var thisWeekExpanded = true
    @State private var earlierExpanded = true

    private var pinned: [MeetingMetadata] {
        meetings.filter(\.isPinned).sorted {
            ($0.pinSortOrder ?? 0) < ($1.pinSortOrder ?? 0)
        }
    }

    private var unpinned: [MeetingMetadata] {
        meetings.filter { !$0.isPinned }
    }

    private var today: [MeetingMetadata] {
        unpinned.filter { Calendar.current.isDateInToday($0.startedAt) }
    }

    private var yesterday: [MeetingMetadata] {
        unpinned.filter { Calendar.current.isDateInYesterday($0.startedAt) }
    }

    private var thisWeek: [MeetingMetadata] {
        let cal = Calendar.current
        return unpinned.filter {
            cal.isDate($0.startedAt, equalTo: Date(), toGranularity: .weekOfYear)
                && !cal.isDateInToday($0.startedAt)
                && !cal.isDateInYesterday($0.startedAt)
        }
    }

    private var earlier: [MeetingMetadata] {
        let cal = Calendar.current
        return unpinned.filter {
            !cal.isDate($0.startedAt, equalTo: Date(), toGranularity: .weekOfYear)
        }
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            // Pinned
            if !pinned.isEmpty {
                dateSection(
                    title: "Pinned", icon: "star.fill", iconColor: Color.vaYellow,
                    meetings: pinned, isExpanded: $pinnedExpanded, isPinnedSection: true
                )
                Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)
            }

            // Today
            if !today.isEmpty {
                dateSection(title: "Today", meetings: today, isExpanded: $todayExpanded)
            }

            // Yesterday
            if !yesterday.isEmpty {
                dateSection(title: "Yesterday", meetings: yesterday, isExpanded: $yesterdayExpanded)
            }

            // This Week
            if !thisWeek.isEmpty {
                dateSection(title: "This Week", meetings: thisWeek, isExpanded: $thisWeekExpanded)
            }

            // Earlier
            if !earlier.isEmpty {
                dateSection(title: "Earlier", meetings: earlier, isExpanded: $earlierExpanded)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.space2)
    }

    @ViewBuilder
    private func dateSection(
        title: String, icon: String? = nil, iconColor: Color? = nil,
        meetings: [MeetingMetadata], isExpanded: Binding<Bool>,
        isPinnedSection: Bool = false
    ) -> some View {
        SidebarSectionHeader(
            title: title, isExpanded: isExpanded,
            count: meetings.count, icon: icon, iconColor: iconColor
        )

        if isExpanded.wrappedValue {
            ForEach(meetings) { meeting in
                let project = projects.first(where: { $0.id == meeting.project })
                Button(action: { onSelect(meeting) }) {
                    SidebarMeetingRow(
                        meeting: meeting,
                        isSelected: selectedId == meeting.id,
                        showProjectPill: !isPinnedSection && meeting.project != nil,
                        projectColor: project.map { Color(hex: $0.color) },
                        projectName: project?.name,
                        isPinnedView: isPinnedSection
                    )
                }
                .buttonStyle(.plain)
                .draggable(meeting.id)
            }
        }
    }
}

// MARK: - Color from hex string helper

extension Color {
    init(hex string: String) {
        let hex = string.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        self.init(hex: UInt32(rgbValue))
    }
}
#endif
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add VaakyaApp/Sources/Views/Sidebar/SidebarDateView.swift
git commit -m "feat(sidebar): add SidebarDateView — By Date grouped list with pinned section"
```

---

### Task 6: ProjectEditorSheet — Create/rename project with color picker

**Files:**
- Create: `Sources/Views/Sidebar/ProjectEditorSheet.swift`

- [ ] **Step 1: Create ProjectEditorSheet.swift**

```swift
#if os(macOS)
import SwiftUI

struct ProjectEditorSheet: View {
    var existing: ProjectFolder?
    var onSave: (String, String) -> Void  // (name, colorHex)
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var selectedColor: String = "#4285F4"

    init(existing: ProjectFolder? = nil, onSave: @escaping (String, String) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _selectedColor = State(initialValue: existing?.color ?? "#4285F4")
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.space6) {
            Text(existing == nil ? "New Project" : "Rename Project")
                .font(DesignTokens.Typography.sectionHead)
                .foregroundStyle(Color.textPrimary)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                Text("Name")
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(Color.textSecondary)
                TextField("Project name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.space3)
                    .padding(.vertical, DesignTokens.Spacing.space3)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .fill(Color.bgContent)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .stroke(Color.vaBorder, lineWidth: 1)
                            )
                    )
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                Text("Color")
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(Color.textSecondary)
                HStack(spacing: 10) {
                    ForEach(ProjectFolder.presetColors, id: \.hex) { preset in
                        Button(action: { selectedColor = preset.hex }) {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: selectedColor == preset.hex ? 2 : 0)
                                        .shadow(color: .black.opacity(0.2), radius: 2)
                                )
                                .overlay(
                                    selectedColor == preset.hex
                                        ? Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                        : nil
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: DesignTokens.Spacing.space3) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondary)

                Button(existing == nil ? "Create" : "Save") {
                    onSave(name, selectedColor)
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignTokens.Button.paddingH)
                .padding(.vertical, DesignTokens.Spacing.space2)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Button.cornerRadius)
                        .fill(Color.accent)
                )
                .foregroundStyle(Color.white)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignTokens.Spacing.space6)
        .frame(width: 340)
        .background(Color.bgApp)
    }
}
#endif
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add VaakyaApp/Sources/Views/Sidebar/ProjectEditorSheet.swift
git commit -m "feat(sidebar): add ProjectEditorSheet — create/rename project with color picker"
```

---

### Task 7: SidebarProjectView — By Project folder list with drag-and-drop

**Files:**
- Create: `Sources/Views/Sidebar/SidebarProjectView.swift`

- [ ] **Step 1: Create SidebarProjectView.swift**

```swift
#if os(macOS)
import SwiftUI

struct SidebarProjectView: View {
    let meetings: [MeetingMetadata]
    let projects: [ProjectFolder]
    let selectedId: String?
    let onSelect: (MeetingMetadata) -> Void
    let onAssignProject: (String, String?) -> Void  // (meetingId, projectId?)

    @State private var pinnedExpanded = true
    @State private var expandedProjects: Set<String> = []
    @State private var unlabeledExpanded = false
    @State private var showCreateProject = false
    @State private var editingProject: ProjectFolder? = nil

    private var pinned: [MeetingMetadata] {
        meetings.filter(\.isPinned).sorted {
            ($0.pinSortOrder ?? 0) < ($1.pinSortOrder ?? 0)
        }
    }

    private func meetingsFor(projectId: String) -> [MeetingMetadata] {
        meetings.filter { !$0.isPinned && $0.project == projectId }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var unlabeled: [MeetingMetadata] {
        meetings.filter { !$0.isPinned && $0.project == nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            // Pinned
            if !pinned.isEmpty {
                SidebarSectionHeader(
                    title: "Pinned", isExpanded: $pinnedExpanded,
                    count: pinned.count, icon: "star.fill", iconColor: Color.vaYellow
                )
                if pinnedExpanded {
                    ForEach(pinned) { meeting in
                        Button(action: { onSelect(meeting) }) {
                            SidebarMeetingRow(
                                meeting: meeting, isSelected: selectedId == meeting.id,
                                isPinnedView: true
                            )
                        }
                        .buttonStyle(.plain)
                        .draggable(meeting.id)
                    }
                }
                Divider().opacity(0.3).padding(.horizontal, DesignTokens.Spacing.space4)
            }

            // Project folders
            ForEach(projects.sorted(by: { $0.sortOrder < $1.sortOrder })) { project in
                let folderMeetings = meetingsFor(projectId: project.id)
                let isExpanded = Binding(
                    get: { expandedProjects.contains(project.id) },
                    set: { newVal in
                        if newVal { expandedProjects.insert(project.id) }
                        else { expandedProjects.remove(project.id) }
                    }
                )

                SidebarSectionHeader(
                    title: project.name, isExpanded: isExpanded,
                    count: folderMeetings.count,
                    icon: "folder.fill", iconColor: Color(hex: project.color),
                    isFolderStyle: true, accentColor: Color(hex: project.color)
                )
                .dropDestination(for: String.self) { meetingIds, _ in
                    for id in meetingIds { onAssignProject(id, project.id) }
                    return true
                } isTargeted: { targeted in
                    if targeted { expandedProjects.insert(project.id) }
                }
                .contextMenu {
                    Button("Rename") { editingProject = project }
                    Menu("Change Color") {
                        ForEach(ProjectFolder.presetColors, id: \.hex) { preset in
                            Button(action: {
                                LocalStore.shared.changeProjectColor(id: project.id, color: preset.hex)
                            }) {
                                Label(preset.name, systemImage: "circle.fill")
                            }
                        }
                    }
                    Divider()
                    Button("Delete Project", role: .destructive) {
                        LocalStore.shared.deleteProject(id: project.id)
                    }
                }

                if isExpanded.wrappedValue {
                    ForEach(folderMeetings) { meeting in
                        Button(action: { onSelect(meeting) }) {
                            SidebarMeetingRow(
                                meeting: meeting, isSelected: selectedId == meeting.id
                            )
                        }
                        .buttonStyle(.plain)
                        .draggable(meeting.id)
                    }
                }

                Divider().opacity(0.15).padding(.horizontal, DesignTokens.Spacing.space4)
            }

            // Unlabeled
            if !unlabeled.isEmpty {
                SidebarSectionHeader(
                    title: "Unlabeled", isExpanded: $unlabeledExpanded,
                    count: unlabeled.count,
                    icon: "folder.fill", iconColor: Color.textTertiary,
                    isFolderStyle: true, dimmed: true
                )
                .dropDestination(for: String.self) { meetingIds, _ in
                    for id in meetingIds { onAssignProject(id, nil) }
                    return true
                }

                if unlabeledExpanded {
                    ForEach(unlabeled) { meeting in
                        Button(action: { onSelect(meeting) }) {
                            SidebarMeetingRow(
                                meeting: meeting, isSelected: selectedId == meeting.id
                            )
                        }
                        .buttonStyle(.plain)
                        .draggable(meeting.id)
                    }
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.space2)
        .onAppear {
            // Expand first project by default
            if let first = projects.first { expandedProjects.insert(first.id) }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorSheet(existing: project) { name, color in
                LocalStore.shared.renameProject(id: project.id, name: name)
                LocalStore.shared.changeProjectColor(id: project.id, color: color)
            }
        }
    }
}
#endif
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add VaakyaApp/Sources/Views/Sidebar/SidebarProjectView.swift
git commit -m "feat(sidebar): add SidebarProjectView — folder list with drag-and-drop + context menus"
```

---

### Task 8: Rewrite SidebarView — Compose everything together

**Files:**
- Modify: `Sources/Views/SidebarView.swift`

- [ ] **Step 1: Rewrite SidebarView.swift**

Replace the entire content of `SidebarView.swift` with the new composed version. Keep the `#if os(macOS)` guard. The key changes:
- Add segmented view mode toggle (By Date / Projects) below search
- Route to `SidebarDateView` or `SidebarProjectView` based on mode
- Add context menus (pin/unpin, move to project, delete) on each meeting row
- Keep existing header, search, recording indicator, footer

Read the full current file first, then replace the meeting list section (between the recording indicator and the footer divider) with the new grouped views. Add the view mode toggle between the search bar and the recording indicator.

Key additions to the view's `@State`:
```swift
@State private var viewMode: String = UserDefaults.standard.string(forKey: "vaakya_sidebar_view_mode") ?? "date"
@State private var showCreateProject = false
```

The segmented toggle:
```swift
// View mode toggle
Picker("View", selection: $viewMode) {
    Text("By Date").tag("date")
    Text("Projects").tag("projects")
}
.pickerStyle(.segmented)
.padding(.horizontal, DesignTokens.Spacing.space4)
.padding(.bottom, DesignTokens.Spacing.space2)
.onChange(of: viewMode) { _, newVal in
    UserDefaults.standard.set(newVal, forKey: "vaakya_sidebar_view_mode")
}
```

The meeting list section becomes:
```swift
ScrollView {
    if !searchText.isEmpty {
        // Flat search results
        LazyVStack(spacing: DesignTokens.Spacing.space1) {
            ForEach(filteredMeetings) { meeting in
                meetingButton(meeting)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.space2)
    } else if viewMode == "projects" {
        SidebarProjectView(
            meetings: meetingVM.meetings,
            projects: LocalStore.shared.projects,
            selectedId: meetingVM.selectedMeeting?.id,
            onSelect: { meetingVM.selectMeeting($0) },
            onAssignProject: { meetingId, projectId in
                LocalStore.shared.assignProject(meetingId: meetingId, projectId: projectId)
            }
        )
    } else {
        SidebarDateView(
            meetings: meetingVM.meetings,
            projects: LocalStore.shared.projects,
            selectedId: meetingVM.selectedMeeting?.id,
            onSelect: { meetingVM.selectMeeting($0) }
        )
    }
}
```

Each meeting row gets a context menu:
```swift
private func meetingButton(_ meeting: MeetingMetadata) -> some View {
    Button(action: { meetingVM.selectMeeting(meeting) }) {
        SidebarMeetingRow(
            meeting: meeting,
            isSelected: meetingVM.selectedMeeting?.id == meeting.id
        )
    }
    .buttonStyle(.plain)
    .draggable(meeting.id)
    .contextMenu { meetingContextMenu(meeting) }
}

@ViewBuilder
private func meetingContextMenu(_ meeting: MeetingMetadata) -> some View {
    Button(action: { LocalStore.shared.togglePin(meetingId: meeting.id) }) {
        Label(meeting.isPinned ? "Unpin" : "Pin", systemImage: meeting.isPinned ? "pin.slash" : "pin")
    }

    Menu("Move to Project") {
        ForEach(LocalStore.shared.projects) { project in
            Button(action: {
                LocalStore.shared.assignProject(meetingId: meeting.id, projectId: project.id)
            }) {
                Label(project.name, systemImage: "folder.fill")
            }
        }
        Divider()
        if meeting.project != nil {
            Button("Remove from Project") {
                LocalStore.shared.assignProject(meetingId: meeting.id, projectId: nil)
            }
        }
        Button("New Project...") { showCreateProject = true }
    }

    Divider()
    Button("Delete", role: .destructive) { meetingVM.deleteMeeting(meeting) }
}
```

Add the `.sheet` for creating a project at the bottom of the VStack:
```swift
.sheet(isPresented: $showCreateProject) {
    ProjectEditorSheet { name, color in
        let project = ProjectFolder(name: name, color: color)
        LocalStore.shared.addProject(project)
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Verify the old meetingRow function is removed**

The old `meetingRow(_ meeting:)` private function should be removed and replaced by the new `meetingButton(_ meeting:)` that uses `SidebarMeetingRow`.

- [ ] **Step 4: Commit**

```bash
git add VaakyaApp/Sources/Views/SidebarView.swift
git commit -m "feat(sidebar): rewrite SidebarView — view mode toggle, grouped lists, context menus, drag-and-drop"
```

---

### Task 9: Drag-and-drop reorder for pinned meetings

**Files:**
- Modify: `Sources/Views/Sidebar/SidebarDateView.swift`
- Modify: `Sources/Views/Sidebar/SidebarProjectView.swift`

- [ ] **Step 1: Add onMove to pinned section in SidebarDateView**

In `SidebarDateView`, replace the pinned `ForEach` with one that supports reordering:

```swift
// In the pinned section of dateSection(), when isPinnedSection is true:
if isPinnedSection && isExpanded.wrappedValue {
    ForEach(meetings) { meeting in
        Button(action: { onSelect(meeting) }) {
            SidebarMeetingRow(
                meeting: meeting, isSelected: selectedId == meeting.id,
                isPinnedView: true
            )
        }
        .buttonStyle(.plain)
        .draggable(meeting.id)
    }
    .onMove { source, destination in
        var reordered = meetings
        reordered.move(fromOffsets: source, toOffset: destination)
        for (i, m) in reordered.enumerated() {
            LocalStore.shared.setPinOrder(meetingId: m.id, order: i)
        }
    }
}
```

Add the same `onMove` to the pinned section in `SidebarProjectView`.

- [ ] **Step 2: Add drop target to pinned section headers for pin-via-drag**

In both `SidebarDateView` and `SidebarProjectView`, add `.dropDestination` to the pinned `SidebarSectionHeader`:

```swift
SidebarSectionHeader(
    title: "Pinned", isExpanded: $pinnedExpanded,
    count: pinned.count, icon: "star.fill", iconColor: Color.vaYellow
)
.dropDestination(for: String.self) { meetingIds, _ in
    for id in meetingIds {
        if !LocalStore.shared.meetings.contains(where: { $0.id == id && $0.isPinned }) {
            LocalStore.shared.togglePin(meetingId: id)
        }
    }
    return true
}
```

This requires adding a callback parameter `onPin: (String) -> Void` to `SidebarDateView` and wiring it from `SidebarView`.

- [ ] **Step 3: Build and verify**

Run: `cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add VaakyaApp/Sources/Views/Sidebar/SidebarDateView.swift VaakyaApp/Sources/Views/Sidebar/SidebarProjectView.swift
git commit -m "feat(sidebar): drag-and-drop reorder pinned meetings + drag-to-pin"
```

---

### Task 10: Final integration + build verification

**Files:**
- All sidebar files

- [ ] **Step 1: Full clean build**

```bash
cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && swift package clean && swift build 2>&1 | tail -10
```

Expected: `Build complete!`

- [ ] **Step 2: Run backend tests to verify nothing broke**

```bash
cd /Users/nagarjuna/projects/meeting_genie && .venv/bin/pytest tests/ -v 2>&1 | tail -5
```

Expected: `22 passed`

- [ ] **Step 3: Verify the app launches**

```bash
cd /Users/nagarjuna/projects/meeting_genie/VaakyaApp && make dev 2>&1 | head -5
```

Check that the app window opens and the sidebar shows the new segmented toggle.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat(sidebar): complete sidebar redesign — grouped views, projects, pinning, drag-and-drop"
```

- [ ] **Step 5: Update ROADMAP.md**

Add to the Completed section in `docs/superpowers/plans/ROADMAP.md`:

```markdown
### Sidebar Redesign ✅
- Two view modes: By Date (Today/Yesterday/This Week/Earlier) and By Project folders
- Pinned section with drag-to-reorder
- Status indicators (enhanced, action items, audio)
- Project folders with CRUD, color picker, drag-and-drop assignment
- Collapsible sections with persistent state
- Context menus for pin/unpin, move to project, delete
```
