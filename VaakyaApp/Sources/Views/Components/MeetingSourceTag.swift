import SwiftUI

// MARK: - Meeting Source Tag

struct MeetingSourceTag: View {
    let source: String

    private var tagColor: Color {
        switch source.lowercased() {
        case "zoom":      return Color.vaBlue
        case "meet":      return Color.accent
        case "teams":     return Color(hex: 0x6264A7)
        case "facetime":  return Color.vaBlue
        case "webex":     return Color.vaBlue
        case "in person": return Color(hex: 0xFF6D00)
        case "manual":    return Color.textTertiary
        default:          return Color.textTertiary
        }
    }

    var body: some View {
        Text(source)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tagColor)
            .padding(.horizontal, DesignTokens.Spacing.space2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(tagColor.opacity(0.12))
            )
    }
}
