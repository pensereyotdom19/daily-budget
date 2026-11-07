import SwiftUI

/// Spending categories. Everyday categories count against the monthly living money;
/// Bills and Engagement are paid from their own planned amounts.
enum Category: String, CaseIterable, Codable, Identifiable {
    case food, coffee, transport, sport, skinCare, phone, shopping, health, fun, bills, engagement, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return String(localized: "Food", bundle: AppLanguage.bundle)
        case .coffee: return String(localized: "Coffee", bundle: AppLanguage.bundle)
        case .transport: return String(localized: "Transport", bundle: AppLanguage.bundle)
        case .sport: return String(localized: "Sport", bundle: AppLanguage.bundle)
        case .skinCare: return String(localized: "Skin care", bundle: AppLanguage.bundle)
        case .phone: return String(localized: "Phone", bundle: AppLanguage.bundle)
        case .shopping: return String(localized: "Shopping", bundle: AppLanguage.bundle)
        case .health: return String(localized: "Health", bundle: AppLanguage.bundle)
        case .fun: return String(localized: "Fun", bundle: AppLanguage.bundle)
        case .bills: return String(localized: "Bills", bundle: AppLanguage.bundle)
        case .engagement: return String(localized: "Engagement", bundle: AppLanguage.bundle)
        case .other: return String(localized: "Other", bundle: AppLanguage.bundle)
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

    /// The category's colour as 0xRRGGBB (also used by the widget).
    var hex: UInt32 {
        switch self {
        case .food: return 0xB5651D
        case .coffee: return 0x7B4B2A
        case .transport: return 0x2B6C8F
        case .sport: return 0x2F7A4F
        case .skinCare: return 0xA23B72
        case .phone: return 0x5A4FA0
        case .shopping: return 0x8C6D0F
        case .health: return 0xB03A3A
        case .fun: return 0xA0660C
        case .bills: return 0x4A5568
        case .engagement: return 0x9B3D5C
        case .other: return 0x6B6B6B
        }
    }

    var color: Color { Color(hex: hex) }

    /// True when spending in this category comes out of the daily living money.
    var countsAsLiving: Bool {
        switch self {
        case .bills, .engagement: return false
        default: return true
        }
    }
}
