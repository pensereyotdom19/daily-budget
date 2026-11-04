import Foundation

/// With a free Apple ID, the app's signing profile runs out 7 days after it was installed and then the
/// app won't open until it is installed again. The profile is inside the app, so we can read the date.
enum AppExpiry {
    /// The expiry date from this install's profile, or nil (simulator, App Store, unreadable).
    static var date: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expirationDate(fromProvision: data)
    }

    /// The profile is a signed file with a plain plist inside; this finds the plist and reads ExpirationDate.
    static func expirationDate(fromProvision data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plistData = data[start.lowerBound..<end.upperBound]
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    /// Whole days left, rounded down (0 on the last day). Negative once expired.
    static func daysLeft(until expiry: Date, now: Date = .now) -> Int {
        Int((expiry.timeIntervalSince(now) / 86_400).rounded(.down))
    }
}
