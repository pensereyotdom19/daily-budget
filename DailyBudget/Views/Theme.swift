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

enum Theme {
    static let base = Color(hex: 0x040509)
    static let violet = Color(hex: 0x7B5CFF)
    static let pink = Color(hex: 0xFF5E8A)
    static let teal = Color(hex: 0x12B5A2)
    static let mint = Color(hex: 0x7CF2A0)
    static let sky = Color(hex: 0x5FD0FF)
    static let warn = Color(hex: 0xFFC9AE)
    static let secondary = Color.white.opacity(0.72)
    static let accentGradient = LinearGradient(colors: [mint, sky], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Near-black background with faint colored glows behind the glass.
struct GlowBackground: View {
    var body: some View {
        // The glows sit in an overlay so they never make the screen wider than the phone.
        // Radial gradients look like the old blurred circles but are far cheaper to draw,
        // which keeps tab switches and screen pushes smooth.
        Theme.base
            .overlay {
                ZStack {
                    glow(Theme.violet, 0.30, size: 600).offset(x: -150, y: -330)
                    glow(Theme.pink, 0.18, size: 540).offset(x: 170, y: -60)
                    glow(Theme.teal, 0.22, size: 620).offset(x: -110, y: 380)
                }
            }
            .clipped()
            .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func glow(_ color: Color, _ opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.55), color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
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

/// Frosted glass card. Uses Liquid Glass on iOS 26+, a thin material before that.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = 24) -> some View { modifier(GlassCard(radius: radius)) }
}

/// Glossy rounded square in the category's color with a dark symbol (same style as the + button).
struct CategoryIcon: View {
    let category: Category
    var size: CGFloat = 38
    /// Overrides the category symbol, e.g. a bolt for an electricity bill.
    var symbol: String? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: symbol ?? category.symbol)
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(Theme.base.opacity(0.85))
            .frame(width: size, height: size)
            .background(
                shape.fill(LinearGradient(colors: [category.color, category.color.opacity(0.62)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.05)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: category.color.opacity(0.35), radius: size * 0.2, y: size * 0.06)
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
                .font(.footnote.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.secondary)
            title
                .font(.system(size: 34, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
