import SwiftUI
import UIKit

extension Color {
    /// A colour with one value for light mode and one for dark mode.
    init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    /// The same colour mixed toward white, for dark backgrounds (0 = unchanged, 1 = white).
    static func lightened(_ hex: UInt32, by amount: Double) -> UInt32 {
        func mix(_ c: UInt32) -> UInt32 { UInt32(Double(c) + (255 - Double(c)) * amount) }
        return (mix((hex >> 16) & 0xFF) << 16) | (mix((hex >> 8) & 0xFF) << 8) | mix(hex & 0xFF)
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// "Ledger" look: serif figures and thin ruled lines.
/// In dark mode the cards are frosted light-blue glass on a navy-to-teal background (like the
/// web dashboard). What's inside a glass card is drawn in light mode, so it uses the light
/// colours (dark ink, forest green for good, tomato for over), which read well on light glass.
/// Light: oat milk paper, forest green for good, tomato red for over.
/// Dark: midnight navy, powder blue for good, soft tomato for over, sunflower for highlights.
/// Good and over keep the same meaning in both modes.
enum Theme {
    /// Paper: the screen background.
    static let base = Color(light: 0xF3EBDD, dark: 0x0F1A2E)
    /// Slightly lighter paper for cards and sheets.
    static let card = Color(light: 0xFBF6EE, dark: 0x16243D)
    /// Ink: text and rules.
    static let ink = Color(light: 0x23301F, dark: 0xE7EEF6)
    /// Thin lines between rows and around cards.
    static let rule = Color(light: 0xE2D6C1, dark: 0x263756)
    static let secondary = Color(light: 0x6F6A5C, dark: 0x8FA6C2)
    /// Positive (under budget, saved): forest green / powder blue.
    static let mint = Color(light: 0x2E5E3E, dark: 0xA9CBE8)
    /// Over budget, bills to watch: tomato (a deeper shade in light so small text stays readable).
    static let warn = Color(light: 0xBF3F2A, dark: 0xF07A62)
    /// Main buttons: forest green / powder blue, with `base` text on top.
    static let primary = Color(light: 0x2E5E3E, dark: 0xA9CBE8)
    /// The special touch: the + button, today in the calendar, the streak. Sunflower at night.
    static let highlight = Color(light: 0x2E5E3E, dark: 0xF5C542)
    static let sky = Color(light: 0x2B5A8A, dark: 0x9AD3C6)
    static let teal = Color(light: 0x2E5E3E, dark: 0xA9CBE8)
    static let pink = Color(light: 0x9B3D5C, dark: 0xE29AB3)
    static let violet = Color(light: 0x4B3F8F, dark: 0xB1A6EA)
    /// Main buttons are solid ink (kept as a gradient type so existing call sites work).
    /// Ledger shapes: square-ish buttons and small tags instead of round pills.
    static let buttonShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    static let chipShape = RoundedRectangle(cornerRadius: 5, style: .continuous)
    static let accentGradient = LinearGradient(colors: [ink, ink], startPoint: .top, endPoint: .bottom)

    /// Figures and titles: serif, like a printed ledger.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight == .bold ? .semibold : weight, design: .serif)
    }
}

/// Light mode: plain oat paper. Dark mode: midnight navy with soft teal and blue light,
/// the background the glass cards sit on.
struct GlowBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.base
            if scheme == .dark {
                RadialGradient(colors: [Color(hex: 0x2C7A8C, opacity: 0.85), .clear],
                               center: UnitPoint(x: 0.95, y: 0.0), startRadius: 0, endRadius: 520)
                RadialGradient(colors: [Color(hex: 0x1B4A7A, opacity: 0.9), .clear],
                               center: UnitPoint(x: 0.0, y: 1.0), startRadius: 0, endRadius: 560)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// True for views inside a dark-mode glass card (they're drawn in light mode there),
/// so a card inside a card knows to be glass too.
private struct OnGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var onGlass: Bool {
        get { self[OnGlassKey.self] }
        set { self[OnGlassKey.self] = newValue }
    }
}

/// Cards and buttons sink a little under your finger, so every tap feels answered.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// A card. Light mode: lighter paper with a thin ruled border.
/// Dark mode: frosted light-blue glass with a soft white edge; the content inside is drawn in
/// light mode so its text is dark. A card inside a card is a slightly clearer glass.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 24
    @Environment(\.colorScheme) private var scheme
    @Environment(\.onGlass) private var onGlass

    func body(content: Content) -> some View {
        if scheme == .dark || onGlass {
            let shape = RoundedRectangle(cornerRadius: min(radius, 18), style: .continuous)
            content
                .environment(\.colorScheme, .light)
                .environment(\.onGlass, true)
                // Kept cheap for smooth scrolling: no live blur (a see-through tint looks almost
                // the same here), and the shadow is drawn from the card's shape only, not from
                // everything inside it.
                .background {
                    shape.fill(Color(hex: onGlass ? 0xF4F8FC : 0xE2EEF8, opacity: onGlass ? 0.7 : 0.9))
                        .shadow(color: .black.opacity(onGlass ? 0 : 0.2), radius: 12, y: 6)
                }
                .overlay(shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 1))
        } else {
            let shape = RoundedRectangle(cornerRadius: min(radius, 14), style: .continuous)
            content
                .background(Theme.card, in: shape)
                .overlay(shape.strokeBorder(Theme.rule, lineWidth: 1))
        }
    }
}

extension View {
    func glassCard(radius: CGFloat = 24) -> some View { modifier(GlassCard(radius: radius)) }
}

/// A flat tile in the category's colour, like a coloured stamp on the page.
struct CategoryIcon: View {
    let category: Category
    var size: CGFloat = 38
    /// Overrides the category symbol, e.g. a bolt for an electricity bill.
    var symbol: String? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Image(systemName: symbol ?? category.symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(category.color)
            .frame(width: size, height: size)
            .background(shape.fill(category.color.opacity(0.13)))
            .overlay(shape.strokeBorder(category.color.opacity(0.3), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

extension Expense {
    /// Icon for this expense: a bill-specific symbol for bill payments, else the category's.
    var iconSymbol: String {
        if category == .bills, let s = Category.billSymbol(for: note) { return s }
        return category.symbol
    }
}

/// Screen title with a small caption above it.
struct ScreenHeader: View {
    let caption: Text
    let title: Text

    init(caption: LocalizedStringKey, title: LocalizedStringKey) {
        self.caption = Text(caption)
        self.title = Text(title)
    }

    /// For a caption that is already translated or isn't words (a date, a month range).
    @_disfavoredOverload
    init(caption: String, title: LocalizedStringKey) {
        self.caption = Text(verbatim: caption)
        self.title = Text(title)
    }

    /// For a title that isn't a fixed word, like a month name (already in the phone's language).
    init(caption: String, verbatimTitle: String) {
        self.caption = Text(verbatim: caption)
        self.title = Text(verbatim: verbatimTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            caption
                .textCase(.uppercase)
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.secondary)
            title
                .font(.system(size: 38, weight: .medium, design: .serif))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
