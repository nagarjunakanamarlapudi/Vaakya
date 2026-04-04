#if os(macOS)
import SwiftUI

struct ProjectEditorSheet: View {
    var existing: ProjectFolder?
    var onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedColor: String

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
                Text("Name").font(DesignTokens.Typography.label).foregroundStyle(Color.textSecondary)
                TextField("Project name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.space3)
                    .padding(.vertical, DesignTokens.Spacing.space3)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .fill(Color.bgContent)
                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                .stroke(Color.vaBorder, lineWidth: 1))
                    )
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                Text("Color").font(DesignTokens.Typography.label).foregroundStyle(Color.textSecondary)
                HStack(spacing: 10) {
                    ForEach(ProjectFolder.presetColors, id: \.hex) { preset in
                        Button(action: { selectedColor = preset.hex }) {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    selectedColor == preset.hex
                                        ? Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                        : nil
                                )
                                .overlay(Circle().stroke(selectedColor == preset.hex ? Color.white : Color.clear, lineWidth: 2).shadow(color: .black.opacity(0.2), radius: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: DesignTokens.Spacing.space3) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain).foregroundStyle(Color.textSecondary)
                Button(existing == nil ? "Create" : "Save") {
                    onSave(name, selectedColor)
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignTokens.Button.paddingH)
                .padding(.vertical, DesignTokens.Spacing.space2)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Button.cornerRadius).fill(Color.accent))
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
