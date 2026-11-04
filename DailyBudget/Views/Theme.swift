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
        ZStack {
            Theme.base
            Circle().fill(Theme.violet.opacity(0.30)).frame(width: 420).blur(radius: 90).offset(x: -150, y: -330)
            Circle().fill(Theme.pink.opacity(0.18)).frame(width: 360).blur(radius: 90).offset(x: 170, y: -60)
            Circle().fill(Theme.teal.opacity(0.22)).frame(width: 420).blur(radius: 100).offset(x: -110, y: 380)
        }
        .ignoresSafeArea()
    }
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

/// Small rounded square with a category's icon.
struct CategoryIcon: View {
    let category: Category
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(category.color)
            .frame(width: size, height: size)
            .background(category.color.opacity(0.22), in: RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .strokeBorder(category.color.opacity(0.5), lineWidth: 1))
    }
}

/// Screen title with a small caption above it.
struct ScreenHeader: View {
    let caption: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption.uppercased())
                .font(.footnote.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.secondary)
            Text(title)
                .font(.system(size: 34, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
