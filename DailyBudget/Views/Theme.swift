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

/// One calm, Apple-style design for both modes (chosen 2026-11-14): one font (SF Pro),
/// grouped lists on plain surfaces, no shadows, quiet icons in the accent colour.
/// Light: soft grey background, white surfaces, forest green accent, tomato for over.
/// Dark: midnight navy, a lighter navy for surfaces, powder blue accent, soft tomato for over,
/// sunflower only for the + button. Good and over keep the same meaning in both modes.
enum Theme {
    /// The screen background.
    static let base = Color(light: 0xF2F2F7, dark: 0x0F1A2E)
    /// Surfaces: grouped lists, cards and sheets.
    static let card = Color(light: 0xFFFFFF, dark: 0x17253D)
    /// Ink: text and rules.
    static let ink = Color(light: 0x111A12, dark: 0xEEF2F7)
    /// Thin lines between rows and around cards.
    static let rule = Color(light: 0xE3E3E8, dark: 0x253651)
    static let secondary = Color(light: 0x6B6F68, dark: 0x8FA3BC)
    /// Positive (under budget, saved): forest green / powder blue.
    static let mint = Color(light: 0x2E5E3E, dark: 0xA9CBE8)
    /// Over budget, bills to watch: tomato (a deeper shade in light so small text stays readable).
    static let warn = Color(light: 0xC0392B, dark: 0xF07A62)
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

    /// Figures and titles: SF Pro (the name is kept from an earlier rounded font).
    /// Use with `.monospacedDigit()` so amounts line up.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight == .bold || weight == .regular ? .semibold : weight)
    }
}

/// The plain screen background (the name is kept from an earlier glowing look).
struct GlowBackground: View {
    var body: some View {
        Theme.base
            .ignoresSafeArea()
            .allowsHitTesting(false)
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

/// A plain surface: the card colour with soft corners, no border and no shadow
/// (the name is kept from an earlier glass look).
struct GlassCard: ViewModifier {
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content.background(Theme.card, in: RoundedRectangle(cornerRadius: min(radius, 12), style: .continuous))
    }
}

extension View {
    func glassCard(radius: CGFloat = 24) -> some View { modifier(GlassCard(radius: radius)) }
}

/// A quiet icon: the symbol in the accent colour on a soft tint of it. Every category uses
/// the same colour, so lists look calm; colour is kept for meaning (good / over).
struct CategoryIcon: View {
    let category: Category
    var size: CGFloat = 38
    /// Overrides the category symbol, e.g. a bolt for an electricity bill.
    var symbol: String? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: symbol ?? category.symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(Theme.mint)
            .frame(width: size, height: size)
            .background(shape.fill(Theme.mint.opacity(0.12)))
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
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondary)
            title
                .font(.system(size: 32, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
