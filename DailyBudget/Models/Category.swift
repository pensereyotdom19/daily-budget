import SwiftUI

/// Spending categories. Everyday categories count against the monthly living money;
/// Bills and Engagement are paid from their own planned amounts.
enum Category: String, CaseIterable, Codable, Identifiable {
    case food, coffee, transport, sport, skinCare, phone, shopping, health, fun, bills, engagement, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return String(localized: "Food")
        case .coffee: return String(localized: "Coffee")
        case .transport: return String(localized: "Transport")
        case .sport: return String(localized: "Sport")
        case .skinCare: return String(localized: "Skin care")
        case .phone: return String(localized: "Phone")
        case .shopping: return String(localized: "Shopping")
        case .health: return String(localized: "Health")
        case .fun: return String(localized: "Fun")
        case .bills: return String(localized: "Bills")
        case .engagement: return String(localized: "Engagement")
        case .other: return String(localized: "Other")
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .coffee: return "cup.and.heat.waves.fill"
        case .transport: return "scooter"
        case .sport: return "figure.run"
        case .skinCare: return "sparkles"
        case .phone: return "iphone.gen3"
        case .shopping: return "bag.fill"
        case .health: return "cross.case.fill"
        case .fun: return "gamecontroller.fill"
        case .bills: return "doc.text.fill"
        case .engagement: return "heart.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    /// A more specific symbol for a bill, guessed from its name (e.g. "Electricity" → bolt).
    static func billSymbol(for name: String) -> String? {
        let n = name.lowercased()
        let table: [(keys: [String], symbol: String)] = [
            (["electric", "power"], "bolt.fill"),
            (["wifi", "wi-fi", "internet"], "wifi"),
            (["water"], "drop.fill"),
            (["bank", "loan"], "building.columns.fill"),
            (["waste", "trash", "garbage"], "trash.fill"),
            (["credit", "card"], "creditcard.fill"),
            (["phone", "mobile"], "phone.fill"),
            (["rent", "house", "home"], "house.fill"),
        ]
        return table.first { entry in entry.keys.contains { n.contains($0) } }?.symbol
    }

    var color: Color {
        switch self {
        case .food: return Color(hex: 0xFFC27A)
        case .coffee: return Color(hex: 0xE6B48A)
        case .transport: return Color(hex: 0x7FD8FF)
        case .sport: return Color(hex: 0x9DF7B8)
        case .skinCare: return Color(hex: 0xFF9BD2)
        case .phone: return Color(hex: 0xB6A4FF)
        case .shopping: return Color(hex: 0xFFE08F)
        case .health: return Color(hex: 0xFFA3A3)
        case .fun: return Color(hex: 0xFFE59A)
        case .bills: return Color(hex: 0xC9D2E3)
        case .engagement: return Color(hex: 0xFFB0C8)
        case .other: return Color(hex: 0xE6E6EE)
        }
    }

    /// True when spending in this category comes out of the daily living money.
    var countsAsLiving: Bool {
        switch self {
        case .bills, .engagement: return false
        default: return true
        }
    }
}
