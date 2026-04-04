#if os(macOS)
import SwiftUI

struct SidebarSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool
    var count: Int = 0
    var icon: String? = nil
    var iconColor: Color? = nil
    var isFolderStyle: Bool = false
    var dimmed: Bool = false

    var body: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 10)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: isFolderStyle ? 14 : 11))
                        .foregroundStyle(iconColor ?? Color.textTertiary)
                }
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
    }
}
#endif
