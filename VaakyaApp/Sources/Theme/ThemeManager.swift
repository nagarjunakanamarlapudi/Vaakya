import SwiftUI

// MARK: - Theme Manager

/// Manages app appearance (light/dark/system). Persists to UserDefaults.
@Observable
final class ThemeManager {
    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system = "System"
        case light  = "Light"
        case dark   = "Dark"

        var id: String { rawValue }
    }

    private static let storageKey = "vaakya_appearance_mode"

    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.storageKey)
        }
    }

    /// Returns the ColorScheme to apply, or nil for system default.
    var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppearanceMode.light.rawValue
        self.appearanceMode = AppearanceMode(rawValue: raw) ?? .system
    }
}
