import SwiftUI

// MARK: - Design Tokens

/// Centralized design tokens for the Vaakya design system.
/// Apple-native calm aesthetic — light mode default, dark mode optional.
/// All values derived from the spec (Section 10.2–10.7).
enum DesignTokens {

    // MARK: - Colors (Light Mode)

    enum Light {
        static let bgApp        = Color(hex: 0xFFFFFF)
        static let bgSidebar    = Color(hex: 0xF7F7F8)
        static let bgContent    = Color(hex: 0xFFFFFF)
        static let bgCard       = Color(hex: 0xF5F5F7)
        static let bgHover      = Color.black.opacity(0.04)
        static let bgActive     = Color.black.opacity(0.06)
        static let bgAccent     = Color(hex: 0x34A853).opacity(0.10)

        static let textPrimary   = Color(hex: 0x1A1A1A)
        static let textSecondary = Color(hex: 0x6B6B6B)
        static let textTertiary  = Color(hex: 0x9B9B9B)

        static let accent       = Color(hex: 0x34A853)
        static let accentHover  = Color(hex: 0x2D9249)
        static let green        = Color(hex: 0x34A853)
        static let red          = Color(hex: 0xEA4335)
        static let blue         = Color(hex: 0x4285F4)
        static let yellow       = Color(hex: 0xFBBC04)

        static let border       = Color.black.opacity(0.08)
        static let borderStrong = Color.black.opacity(0.15)
    }

    // MARK: - Colors (Dark Mode)

    enum Dark {
        static let bgApp        = Color(hex: 0x1A1A1A)
        static let bgSidebar    = Color(hex: 0x222222)
        static let bgContent    = Color(hex: 0x1A1A1A)
        static let bgCard       = Color(hex: 0x2A2A2A)
        static let bgHover      = Color.white.opacity(0.06)
        static let bgActive     = Color.white.opacity(0.08)
        static let bgAccent     = Color(hex: 0x4ECB71).opacity(0.12)

        static let textPrimary   = Color(hex: 0xEDEDEF)
        static let textSecondary = Color(hex: 0x9B9B9B)
        static let textTertiary  = Color(hex: 0x6B6B6B)

        static let accent       = Color(hex: 0x4ECB71)
        static let accentHover  = Color(hex: 0x3FBF60)
        static let green        = Color(hex: 0x4ECB71)
        static let red          = Color(hex: 0xEA4335)
        static let blue         = Color(hex: 0x4285F4)
        static let yellow       = Color(hex: 0xFBBC04)

        static let border       = Color.white.opacity(0.08)
        static let borderStrong = Color.white.opacity(0.15)
    }

    // MARK: - Spacing (8px base grid)

    enum Spacing {
        static let space1: CGFloat  = 4
        static let space2: CGFloat  = 8
        static let space3: CGFloat  = 12
        static let space4: CGFloat  = 16
        static let space6: CGFloat  = 24
        static let space8: CGFloat  = 32
        static let space12: CGFloat = 48
    }

    // MARK: - Border Radius

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
    }

    // MARK: - Typography

    enum Typography {
        static let pageTitle    = Font.system(size: 24, weight: .bold)
        static let sectionHead  = Font.system(size: 16, weight: .semibold)
        static let body         = Font.system(size: 15)
        static let bodyMedium   = Font.system(size: 15, weight: .medium)
        static let caption      = Font.system(size: 13)
        static let label        = Font.system(size: 12, weight: .medium)
    }

    // MARK: - Block Colors (left borders + badges)

    enum BlockColor {
        static let summary  = Color(hex: 0x34A853) // green
        static let decision = Color(hex: 0x4285F4) // blue
        static let action   = Color(hex: 0xEA4335) // red
        static let quote    = Color(hex: 0xFBBC04) // yellow
    }

    // MARK: - Block Layout

    enum Block {
        static let padding: CGFloat = 16
        static let paddingH: CGFloat = 20
        static let marginBottom: CGFloat = 12
        static let cornerRadius: CGFloat = 12
        static let borderWidth: CGFloat = 3
        static let maxContentWidth: CGFloat = 720
    }

    // MARK: - Button

    enum Button {
        static let height: CGFloat = 36
        static let fontSize: CGFloat = 14
        static let fontWeight: Font.Weight = .medium
        static let cornerRadius: CGFloat = 10
        static let paddingH: CGFloat = 16

        // Compact variant for inline/secondary actions
        static let compactHeight: CGFloat = 28
        static let compactFontSize: CGFloat = 12
        static let compactCornerRadius: CGFloat = 6
    }

    // MARK: - Shadows

    enum Shadow {
        static let cardColor   = Color.black.opacity(0.08)
        static let cardRadius: CGFloat = 3
        static let cardY: CGFloat = 1

        static let elevatedColor   = Color.black.opacity(0.10)
        static let elevatedRadius: CGFloat = 12
        static let elevatedY: CGFloat = 4
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    init(hex string: String) {
        let hex = string.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Adaptive Color Helper

/// Returns the appropriate color for the current color scheme.
/// Usage: `AdaptiveColor.bgApp.color(for: colorScheme)`
enum AdaptiveColor {
    case bgApp, bgSidebar, bgContent, bgCard, bgHover, bgActive, bgAccent
    case textPrimary, textSecondary, textTertiary
    case accent, accentHover, green, red, blue, yellow
    case border, borderStrong

    func color(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            switch self {
            case .bgApp:        return DesignTokens.Dark.bgApp
            case .bgSidebar:    return DesignTokens.Dark.bgSidebar
            case .bgContent:    return DesignTokens.Dark.bgContent
            case .bgCard:       return DesignTokens.Dark.bgCard
            case .bgHover:      return DesignTokens.Dark.bgHover
            case .bgActive:     return DesignTokens.Dark.bgActive
            case .bgAccent:     return DesignTokens.Dark.bgAccent
            case .textPrimary:  return DesignTokens.Dark.textPrimary
            case .textSecondary: return DesignTokens.Dark.textSecondary
            case .textTertiary: return DesignTokens.Dark.textTertiary
            case .accent:       return DesignTokens.Dark.accent
            case .accentHover:  return DesignTokens.Dark.accentHover
            case .green:        return DesignTokens.Dark.green
            case .red:          return DesignTokens.Dark.red
            case .blue:         return DesignTokens.Dark.blue
            case .yellow:       return DesignTokens.Dark.yellow
            case .border:       return DesignTokens.Dark.border
            case .borderStrong: return DesignTokens.Dark.borderStrong
            }
        default:
            switch self {
            case .bgApp:        return DesignTokens.Light.bgApp
            case .bgSidebar:    return DesignTokens.Light.bgSidebar
            case .bgContent:    return DesignTokens.Light.bgContent
            case .bgCard:       return DesignTokens.Light.bgCard
            case .bgHover:      return DesignTokens.Light.bgHover
            case .bgActive:     return DesignTokens.Light.bgActive
            case .bgAccent:     return DesignTokens.Light.bgAccent
            case .textPrimary:  return DesignTokens.Light.textPrimary
            case .textSecondary: return DesignTokens.Light.textSecondary
            case .textTertiary: return DesignTokens.Light.textTertiary
            case .accent:       return DesignTokens.Light.accent
            case .accentHover:  return DesignTokens.Light.accentHover
            case .green:        return DesignTokens.Light.green
            case .red:          return DesignTokens.Light.red
            case .blue:         return DesignTokens.Light.blue
            case .yellow:       return DesignTokens.Light.yellow
            case .border:       return DesignTokens.Light.border
            case .borderStrong: return DesignTokens.Light.borderStrong
            }
        }
    }
}

// MARK: - Adaptive Color Helper

private func adaptiveColor(light: Color, dark: Color) -> Color {
    #if os(macOS)
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(dark)
            : NSColor(light)
    })
    #else
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
    })
    #endif
}

// MARK: - Adaptive Color Extensions

extension Color {
    // Backgrounds
    static let bgApp      = adaptiveColor(light: DesignTokens.Light.bgApp, dark: DesignTokens.Dark.bgApp)
    static let bgSidebar   = adaptiveColor(light: DesignTokens.Light.bgSidebar, dark: DesignTokens.Dark.bgSidebar)
    static let bgContent   = adaptiveColor(light: DesignTokens.Light.bgContent, dark: DesignTokens.Dark.bgContent)
    static let bgCard      = adaptiveColor(light: DesignTokens.Light.bgCard, dark: DesignTokens.Dark.bgCard)
    static let bgElevated  = bgCard

    // Text
    static let textPrimary   = adaptiveColor(light: DesignTokens.Light.textPrimary, dark: DesignTokens.Dark.textPrimary)
    static let textSecondary = adaptiveColor(light: DesignTokens.Light.textSecondary, dark: DesignTokens.Dark.textSecondary)
    static let textTertiary  = adaptiveColor(light: DesignTokens.Light.textTertiary, dark: DesignTokens.Dark.textTertiary)

    // Accent
    static let accent = adaptiveColor(light: DesignTokens.Light.accent, dark: DesignTokens.Dark.accent)

    // Semantic colors (adapt for dark mode contrast)
    static let vaGreen  = adaptiveColor(light: DesignTokens.Light.green, dark: DesignTokens.Dark.green)
    static let vaRed    = DesignTokens.Light.red   // same in both modes
    static let vaBlue   = DesignTokens.Light.blue   // same in both modes
    static let vaYellow = DesignTokens.Light.yellow // same in both modes

    // Borders
    static let vaBorder       = adaptiveColor(light: DesignTokens.Light.border, dark: DesignTokens.Dark.border)
    static let vaBorderStrong = adaptiveColor(light: DesignTokens.Light.borderStrong, dark: DesignTokens.Dark.borderStrong)

    // Block accent colors (used for left borders and badges)
    static let blockRed    = DesignTokens.BlockColor.action
    static let blockGreen  = adaptiveColor(light: DesignTokens.BlockColor.summary, dark: DesignTokens.Dark.green)
    static let blockBlue   = DesignTokens.BlockColor.decision
    static let blockYellow = DesignTokens.BlockColor.quote
}
