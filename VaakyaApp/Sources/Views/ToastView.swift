import SwiftUI

/// Toast type determines the icon and accent color.
enum ToastType {
    case error
    case success
    case info

    var icon: String {
        switch self {
        case .error:   return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .error:   return Color.vaRed
        case .success: return Color.vaGreen
        case .info:    return Color.vaBlue
        }
    }
}

/// A single toast notification that appears at the top of the window.
struct ToastView: View {
    let message: String
    let type: ToastType
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.space2) {
            Image(systemName: type.icon)
                .font(.system(size: 12))
                .foregroundStyle(type.color)

            Text(message)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)

            Spacer()

            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.space4)
        .padding(.vertical, DesignTokens.Spacing.space3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .stroke(type.color.opacity(0.3), lineWidth: 1)
                )
                .shadow(
                    color: DesignTokens.Shadow.elevatedColor,
                    radius: DesignTokens.Shadow.elevatedRadius,
                    y: DesignTokens.Shadow.elevatedY
                )
        )
        .padding(.horizontal, DesignTokens.Spacing.space6)
        .padding(.top, DesignTokens.Spacing.space2)
    }
}
