import Foundation
import Security

/// Who is signed in. The login token is kept in the iPhone Keychain (encrypted), never in plain files.
struct AccountSession: Codable, Equatable {
    var token: String
    var email: String
    var userID: UUID
    var expiresAt: Date
}

enum SessionStore {
    private static let service = "com.pensereyotdom19.dailybudget.api"
    private static let account = "session"

    static func load() -> AccountSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AccountSession.self, from: data)
    }

    static func save(_ session: AccountSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        clear()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Readable after the first unlock, so background syncs work; never leaves this phone.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// What was last uploaded or downloaded, per record, so a sync only sends what changed.
/// Each value is a "fingerprint": the record's synced fields joined into one string.
struct SyncState: Codable, Equatable {
    var userID: UUID?
    /// The server's clock at the last download; sent back as `since`.
    var lastServerTime: String?
    var lastSyncedAt: Date?
    var settings: String?
    var bills: [UUID: String] = [:]
    var expenses: [UUID: String] = [:]
    var incomes: [UUID: String] = [:]
    var recurring: [UUID: String] = [:]
    var subscriptions: [UUID: String] = [:]

    init(userID: UUID? = nil) {
        self.userID = userID
    }

    /// Fields added later are optional when reading, so a sync-state file from an older version still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decodeIfPresent(UUID.self, forKey: .userID)
        lastServerTime = try c.decodeIfPresent(String.self, forKey: .lastServerTime)
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        settings = try c.decodeIfPresent(String.self, forKey: .settings)
        bills = try c.decodeIfPresent([UUID: String].self, forKey: .bills) ?? [:]
        expenses = try c.decodeIfPresent([UUID: String].self, forKey: .expenses) ?? [:]
        incomes = try c.decodeIfPresent([UUID: String].self, forKey: .incomes) ?? [:]
        recurring = try c.decodeIfPresent([UUID: String].self, forKey: .recurring) ?? [:]
        subscriptions = try c.decodeIfPresent([UUID: String].self, forKey: .subscriptions) ?? [:]
    }

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "sync-state.json")
    }

    static func load() -> SyncState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return state
    }

    func save() {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Self.fileURL, options: .atomic) }
    }
}
