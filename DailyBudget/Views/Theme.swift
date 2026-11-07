import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// "Ledger" look: cream paper, navy ink, serif figures, thin ruled lines.
enum Theme {
    /// Paper: the screen background.
    static let base = Color(hex: 0xF7F3EA)
    /// Slightly lighter paper for cards and sheets.
    static let card = Color(hex: 0xFBF8F1)
    /// Navy ink: text, rules and the main buttons.
    static let ink = Color(hex: 0x1E2A3A)
    /// Thin lines between rows and around cards.
    static let rule = Color(hex: 0xD9CFBA)
    static let secondary = Color(hex: 0x5B6472)
    /// Positive (under budget, saved): ledger green.
    static let mint = Color(hex: 0x2F5D4A)
    /// Over budget, bills to watch: oxblood.
    static let warn = Color(hex: 0x8A2E2E)
    static let sky = Color(hex: 0x2B5A8A)
    static let teal = Color(hex: 0x2F5D4A)
    static let pink = Color(hex: 0x9B3D5C)
    static let violet = Color(hex: 0x4B3F8F)
    /// Main buttons are solid ink (kept as a gradient type so existing call sites work).
    static let accentGradient = LinearGradient(colors: [ink, ink], startPoint: .top, endPoint: .bottom)

    /// Figures and titles: serif, like a printed ledger.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight == .bold ? .semibold : weight, design: .serif)
    }
}

/// Plain paper background (the name is kept from the earlier glowing look).
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

/// A ledger card: lighter paper with a thin ruled border (the name is kept from the glass look).
struct GlassCard: ViewModifier {
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(radius, 14), style: .continuous)
        content
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.rule, lineWidth: 1))
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
