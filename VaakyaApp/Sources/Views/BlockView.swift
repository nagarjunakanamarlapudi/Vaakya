import SwiftUI

struct BlockView: View {
    let block: BlockData
    let meetingId: String
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    var onContentChange: ((String) -> Void)? = nil

    @State private var editedContent: String = ""
    @State private var isHovered: Bool = false
    @FocusState private var isFocused: Bool

    private var borderColor: Color {
        switch block.type.lowercased() {
        case "summary":  return DesignTokens.BlockColor.summary
        case "decision": return DesignTokens.BlockColor.decision
        case "action":   return DesignTokens.BlockColor.action
        case "quote":    return DesignTokens.BlockColor.quote
        default:         return Color.textTertiary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left colored border
            RoundedRectangle(cornerRadius: 2)
                .fill(borderColor)
                .frame(width: DesignTokens.Block.borderWidth)
                .padding(.vertical, DesignTokens.Spacing.space1)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                HStack {
                    Text(block.type.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(borderColor)
                        .tracking(0.5)
                    Spacer()
                    Menu {
                        Button("Delete", role: .destructive) { onDelete() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .menuStyle(.borderlessButton)
                    #endif
                }

                if block.type.lowercased() == "action" {
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.space2) {
                        Button { onToggle(!block.isChecked) } label: {
                            Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 14))
                                .foregroundStyle(block.isChecked ? DesignTokens.BlockColor.summary : Color.textTertiary)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            TextField("", text: $editedContent, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(block.isChecked ? Color.textTertiary : Color.textPrimary)
                                .strikethrough(block.isChecked)
                                .focused($isFocused)
                                .onSubmit { commitEdit() }
                            if let meta = block.metaText {
                                Text(meta)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            if let speaker = block.speaker, !speaker.isEmpty {
                                Text(speaker)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                } else if block.type.lowercased() == "quote" {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.space1) {
                        TextField("", text: $editedContent, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(DesignTokens.Typography.caption)
                            .italic()
                            .foregroundStyle(block.isAIGenerated ? Color.textSecondary : Color.textPrimary)
                            .focused($isFocused)
                            .onSubmit { commitEdit() }

                        HStack(spacing: DesignTokens.Spacing.space2) {
                            if let speaker = block.speaker {
                                Text(speaker)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            if let ts = block.timestampSeconds {
                                HStack(spacing: 3) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 8))
                                    Text(formatTimestamp(ts))
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(Color.accent)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("", text: $editedContent, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(block.isAIGenerated ? Color.textSecondary : Color.textPrimary)
                            .focused($isFocused)
                            .onSubmit { commitEdit() }
                        if let meta = block.metaText {
                            Text(meta)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textTertiary)
                        }
                        if let speaker = block.speaker, !speaker.isEmpty {
                            Text(speaker)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
            .padding(.leading, DesignTokens.Spacing.space3)
            .padding(.trailing, DesignTokens.Spacing.space2)
            .padding(.vertical, DesignTokens.Block.padding)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Block.cornerRadius)
                .fill(Color.bgCard)
                .shadow(color: DesignTokens.Shadow.cardColor, radius: DesignTokens.Shadow.cardRadius, y: DesignTokens.Shadow.cardY)
        )
        .padding(.bottom, DesignTokens.Spacing.space1)
        #if os(macOS)
        .onHover { hovering in isHovered = hovering }
        #endif
        .onAppear { editedContent = block.content }
        .onChange(of: block.content) { _, newValue in editedContent = newValue }
        .onChange(of: isFocused) { _, focused in
            if !focused { commitEdit() }
        }
    }

    private func commitEdit() {
        let trimmed = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != block.content else { return }
        onContentChange?(trimmed)
    }

    private func formatTimestamp(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
