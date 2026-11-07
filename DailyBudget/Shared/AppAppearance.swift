import SwiftUI
import UIKit

/// Light or dark Ledger, chosen in Settings. "Same as iPhone" follows the phone's own setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    /// Stored in the app's own settings, so `-app.appearance dark` on launch also works for screenshots.
    static let key = "app.appearance"

    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    /// For SwiftUI's `.preferredColorScheme`; nil means follow the iPhone.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// For UIKit windows (the Face ID lock screen).
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    var title: String {
        switch self {
        case .system: return String(localized: "Same as iPhone", bundle: AppLanguage.bundle)
        case .light: return String(localized: "Light", bundle: AppLanguage.bundle)
        case .dark: return String(localized: "Dark", bundle: AppLanguage.bundle)
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
