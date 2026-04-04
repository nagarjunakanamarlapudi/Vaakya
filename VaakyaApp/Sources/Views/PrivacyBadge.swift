import SwiftUI

/// "Processed on your Mac/iPhone" privacy badge with lock icon and green accent background.
struct PrivacyBadge: View {
    #if os(macOS)
    var text: String = "Processed on your Mac"
    #else
    var text: String = "Processed on your iPhone"
    #endif

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Color.vaGreen)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(Color.vaGreen.opacity(0.10))
        )
        .fixedSize()
    }
}
