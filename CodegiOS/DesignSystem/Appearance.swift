import SwiftUI
import Observation

/// The app's theme mode. `.system` follows the device's light/dark setting.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// SF Symbol name, translated to Lucide at the call site — the web's own
    /// appearance picker uses Monitor / Sun / Moon for these three.
    var symbol: String {
        switch self {
        case .system: "iphone"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    /// The value to hand `.preferredColorScheme`. `.system` → `nil` (defer to the
    /// device).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// User-chosen appearance: light/dark/system mode and the shadcn theme preset.
/// Both persist to `UserDefaults` and survive relaunch. Owned at the app root
/// (`RootView`) and injected into the environment so the Settings screen can
/// read and mutate it; `mode` drives `.preferredColorScheme` and `themeColor`
/// drives the `\.webTheme` trait bridge, both applied once in `RootView`.
@MainActor
@Observable
final class AppearanceStore {
    private static let modeKey = "codeg.appearance.mode"
    /// Stores the preset's `rawValue` (a stable string like "violet"), not its
    /// index, so reordering the presets can't reinterpret a saved choice.
    private static let themeColorKey = "codeg.appearance.themeColor"
    /// The pre-port accent palette, kept only to migrate an existing install
    /// once. See ``migratedTheme(fromLegacyAccent:)``.
    private static let legacyAccentKey = "codeg.appearance.accent"

    var mode: AppearanceMode {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        }
    }

    /// The active shadcn preset — the web client's `data-theme`.
    var themeColor: WebThemeColor {
        didSet {
            guard oldValue != themeColor else { return }
            UserDefaults.standard.set(themeColor.rawValue, forKey: Self.themeColorKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.mode = defaults.string(forKey: Self.modeKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system

        if let stored = defaults.string(forKey: Self.themeColorKey),
           let preset = WebThemeColor(rawValue: stored) {
            self.themeColor = preset
        } else {
            // First launch after the port: carry the old accent choice over to
            // the nearest preset instead of silently resetting to neutral.
            let legacy = defaults.object(forKey: Self.legacyAccentKey) as? Int
            self.themeColor = Self.migratedTheme(fromLegacyAccent: legacy)
        }
    }

    /// Maps the pre-port `AccentPalette` raw index onto the closest shadcn
    /// preset. The old palette's raw values were pinned (neutral = 8, mint = 0,
    /// blue = 1, indigo = 2, purple = 3, pink = 4, orange = 5, teal = 6,
    /// red = 7, mocha = 9, butter = 10, dusk = 11); several old hues have no
    /// preset of their own and land on their nearest neighbor.
    static func migratedTheme(fromLegacyAccent index: Int?) -> WebThemeColor {
        switch index {
        case 0: .green   // mint
        case 1: .blue
        case 2: .violet  // indigo
        case 3: .violet  // purple
        case 4: .rose    // pink
        case 5: .orange
        case 6: .blue    // teal
        case 7: .red
        case 9: .stone   // mocha
        case 10: .yellow // butter
        case 11: .violet // dusk
        default: .neutral
        }
    }
}
