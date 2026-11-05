import SwiftUI

/// Brand-coloured icons for well-known subscriptions (YouTube, Netflix, Claude, ChatGPT…), drawn with
/// SF Symbols and letters in each service's colours, so no logo images are needed.
struct ServiceBrand: Equatable, Identifiable {
    enum Mark: Equatable {
        case symbol(String)
        case letters(String)
    }

    /// The name filled in when you pick it from the list.
    var name: String
    /// Lowercased words that identify it in a subscription's name.
    var keywords: [String]
    var background: UInt32
    var foreground: UInt32 = 0xFFFFFF
    var mark: Mark
    var id: String { name }
    /// Shorter label for under the icon: "YouTube", "ChatGPT", "Claude".
    var shortName: String {
        [" Premium", " Plus", " Pro"].reduce(name) { $0.replacingOccurrences(of: $1, with: "") }
    }

    /// Order matters: "YouTube Music" must match YouTube before "music", "Apple TV" before "tv".
    static let all: [ServiceBrand] = [
        ServiceBrand(name: "YouTube Premium", keywords: ["youtube"], background: 0xFF0000, mark: .symbol("play.fill")),
        ServiceBrand(name: "Netflix", keywords: ["netflix"], background: 0x141414, foreground: 0xE50914, mark: .letters("N")),
        ServiceBrand(name: "Spotify", keywords: ["spotify"], background: 0x1DB954, foreground: 0x000000, mark: .symbol("waveform")),
        ServiceBrand(name: "ChatGPT Plus", keywords: ["chatgpt", "openai", "gpt"], background: 0x10A37F, mark: .symbol("bubble.left.and.text.bubble.right.fill")),
        ServiceBrand(name: "Claude Pro", keywords: ["claude", "anthropic"], background: 0xD97757, mark: .symbol("asterisk")),
        ServiceBrand(name: "Gemini", keywords: ["gemini"], background: 0x4285F4, mark: .symbol("sparkle")),
        ServiceBrand(name: "Perplexity", keywords: ["perplexity"], background: 0x20808D, mark: .symbol("magnifyingglass")),
        ServiceBrand(name: "iCloud+", keywords: ["icloud"], background: 0x3693F3, mark: .symbol("icloud.fill")),
        ServiceBrand(name: "Apple Music", keywords: ["apple music"], background: 0xFA2D48, mark: .symbol("music.note")),
        ServiceBrand(name: "Apple TV+", keywords: ["apple tv"], background: 0x000000, mark: .symbol("appletv.fill")),
        ServiceBrand(name: "Apple One", keywords: ["apple one"], background: 0x1C1C1E, mark: .symbol("apple.logo")),
        ServiceBrand(name: "Google One", keywords: ["google one", "google drive", "google"], background: 0xFFFFFF, foreground: 0x4285F4, mark: .letters("G")),
        ServiceBrand(name: "Disney+", keywords: ["disney"], background: 0x113CCF, mark: .letters("D+")),
        ServiceBrand(name: "Prime Video", keywords: ["prime", "amazon"], background: 0x00A8E1, mark: .symbol("play.tv.fill")),
        ServiceBrand(name: "Canva Pro", keywords: ["canva"], background: 0x00C4CC, mark: .letters("C")),
        ServiceBrand(name: "Adobe", keywords: ["adobe", "photoshop", "lightroom"], background: 0xFA0F00, mark: .letters("A")),
        ServiceBrand(name: "Microsoft 365", keywords: ["microsoft", "office", "365"], background: 0xD83B01, mark: .symbol("square.grid.2x2.fill")),
        ServiceBrand(name: "Notion", keywords: ["notion"], background: 0xFFFFFF, foreground: 0x000000, mark: .letters("N")),
        ServiceBrand(name: "Telegram Premium", keywords: ["telegram"], background: 0x2AABEE, mark: .symbol("paperplane.fill")),
        ServiceBrand(name: "Duolingo", keywords: ["duolingo"], background: 0x58CC02, mark: .symbol("bird.fill")),
        ServiceBrand(name: "GitHub", keywords: ["github", "copilot"], background: 0x24292E, mark: .symbol("chevron.left.forwardslash.chevron.right")),
        ServiceBrand(name: "CapCut", keywords: ["capcut"], background: 0x000000, mark: .symbol("scissors")),
    ]

    /// The brand whose keyword appears in `name`, if any.
    static func match(_ name: String) -> ServiceBrand? {
        let n = name.lowercased()
        guard !n.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return all.first { $0.keywords.contains { n.contains($0) } }
    }
}

/// A subscription's icon: the brand's colours when the name is a known service, otherwise a generic tile.
struct ServiceIcon: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        if let brand = ServiceBrand.match(name) {
            BrandTile(brand: brand, size: size)
        } else {
            CategoryIcon(category: .bills, size: size, symbol: SubscriptionSchedule.symbol(for: name))
        }
    }
}

struct BrandTile: View {
    let brand: ServiceBrand
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Group {
            switch brand.mark {
            case .symbol(let name):
                Image(systemName: name).font(.system(size: size * 0.42, weight: .bold))
            case .letters(let text):
                Text(verbatim: text)
                    .font(.system(size: size * (text.count > 1 ? 0.38 : 0.52), weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(Color(hex: brand.foreground))
        .frame(width: size, height: size)
        .background(shape.fill(Color(hex: brand.background)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: Color(hex: brand.background).opacity(0.35), radius: size * 0.18, y: size * 0.05)
        .accessibilityHidden(true)
    }
}

/// An expense's icon: a subscription payment gets its service's icon, everything else its category's.
struct ExpenseIcon: View {
    let expense: Expense
    var size: CGFloat = 40

    var body: some View {
        if expense.category == .bills, expense.billID == nil, let brand = ServiceBrand.match(expense.note) {
            BrandTile(brand: brand, size: size)
        } else {
            CategoryIcon(category: expense.category, size: size, symbol: expense.iconSymbol)
        }
    }
}
