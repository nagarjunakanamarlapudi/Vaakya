import SwiftUI

/// Reusable empty state component with centered icon, heading, subtitle, and optional action button.
/// Uses DesignTokens for all styling.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.space3) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Color.textTertiary)

            Text(title)
                .font(DesignTokens.Typography.sectionHead)
                .foregroundStyle(Color.textSecondary)

            Text(subtitle)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)

            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: DesignTokens.Button.fontSize, weight: DesignTokens.Button.fontWeight))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DesignTokens.Button.paddingH)
                        .frame(height: DesignTokens.Button.height)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Button.cornerRadius)
                                .fill(Color.accent)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, DesignTokens.Spacing.space2)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.space8)
    }
}
