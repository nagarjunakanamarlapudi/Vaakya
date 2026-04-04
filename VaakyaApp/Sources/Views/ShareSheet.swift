import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ShareSheet: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.space6) {
            // Header
            HStack {
                Image(systemName: "link")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accent)

                Text("Share Meeting")
                    .font(DesignTokens.Typography.sectionHead)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(Color.bgCard)
                                .shadow(color: DesignTokens.Shadow.cardColor, radius: 1, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            // URL display
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                Text("Share link")
                    .font(DesignTokens.Typography.label)
                    .foregroundStyle(Color.textSecondary)

                HStack(spacing: DesignTokens.Spacing.space2) {
                    Text(url)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignTokens.Spacing.space3)
                        .padding(.vertical, DesignTokens.Spacing.space2)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(Color.bgCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                )
                        )

                    Button(action: {
                        copyToClipboard(url)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    }) {
                        HStack(spacing: DesignTokens.Spacing.space1) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            Text(copied ? "Copied!" : "Copy")
                                .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                        }
                        .foregroundStyle(copied ? DesignTokens.BlockColor.summary : Color.white)
                        .padding(.horizontal, DesignTokens.Spacing.space3)
                        .padding(.vertical, DesignTokens.Spacing.space2)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                                .fill(copied ? DesignTokens.BlockColor.summary.opacity(0.12) : Color.accent)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Anyone with this link can view the meeting contents.")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignTokens.Button.paddingH + 4)
                .padding(.vertical, DesignTokens.Spacing.space2)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Button.cornerRadius)
                        .fill(Color.bgCard)
                        .shadow(color: DesignTokens.Shadow.cardColor, radius: 1, y: 1)
                )
                .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(DesignTokens.Spacing.space6)
        #if os(macOS)
        .frame(width: 480)
        #endif
        .background(Color.bgApp)
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
