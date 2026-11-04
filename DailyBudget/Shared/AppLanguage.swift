import Foundation
import ObjectiveC

/// The app's language, chosen in Settings: the iPhone's language, English or Khmer.
/// Switching takes effect at once: the app reads its text from the chosen language's files,
/// and dates are formatted with `AppLanguage.locale`. The choice is shared with the widget.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, km

    var id: String { rawValue }
    static let key = "app.language"
    private static var shared: UserDefaults { UserDefaults(suiteName: WidgetSnapshot.appGroup) ?? .standard }

    /// For development screenshots, `-app.language km` on launch overrides the saved choice.
    static var current: AppLanguage {
        let raw = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[key] as? String
            ?? shared.string(forKey: key) ?? ""
        return AppLanguage(rawValue: raw) ?? .system
    }

    /// The name shown in the picker, in its own language.
    var nativeName: String {
        switch self {
        case .system: return String(localized: "Same as iPhone", bundle: AppLanguage.bundle)
        case .en: return "English"
        case .km: return "ខ្មែរ"
        }
    }

    static var locale: Locale {
        current == .system ? .current : Locale(identifier: current.rawValue)
    }

    static func set(_ language: AppLanguage) {
        shared.set(language.rawValue, forKey: key)
        // Also tell iOS, so the Face ID prompt and the next launch start in the same language.
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
        cachedBundle = nil
    }

    /// Where to look up text built in code: `String(localized: "...", bundle: AppLanguage.bundle)`.
    static var bundle: Bundle { overrideBundle ?? .main }

    /// Call once at launch: from then on, text is looked up in the chosen language.
    static func install() {
        guard !(Bundle.main is LanguageBundle) else { return }
        object_setClass(Bundle.main, LanguageBundle.self)
    }

    fileprivate static var cachedBundle: (AppLanguage, Bundle?)?

    /// The .lproj folder for the chosen language, or nil to use the iPhone's language.
    fileprivate static var overrideBundle: Bundle? {
        let lang = current
        if let cached = cachedBundle, cached.0 == lang { return cached.1 }
        var bundle: Bundle?
        if lang != .system, let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj") {
            bundle = Bundle(path: path)
        }
        cachedBundle = (lang, bundle)
        return bundle
    }
}

/// Bundle.main becomes this class so every text lookup goes to the chosen language.
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = AppLanguage.overrideBundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
