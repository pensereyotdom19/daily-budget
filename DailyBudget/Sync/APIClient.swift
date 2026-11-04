import Foundation

/// Talks to the Daily Budget server (github.com/pensereyotdom19/daily-budget-api) with Apple's URLSession.
struct APIClient {
    static let productionURL = URL(string: "https://daily-budget-api.onrender.com")!

    /// The free server sleeps when unused and can take about a minute to wake up, so wait long enough.
    static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    var baseURL: URL = APIClient.productionURL
    var session: URLSession = APIClient.defaultSession
    var token: String?

    // MARK: Endpoints

    func login(email: String, password: String) async throws -> TokenDTO {
        try await send("POST", "api/auth/login", body: LoginDTO(email: email, password: password))
    }

    func changes(since: String?) async throws -> ChangesDTO {
        try await send("GET", "api/sync", query: since.map { [URLQueryItem(name: "since", value: $0)] } ?? [])
    }

    func putSettings(_ s: SettingsDTO) async throws -> SettingsDTO {
        try await send("PUT", "api/settings", body: s)
    }

    func putBill(_ b: BillDTO) async throws -> BillDTO {
        try await send("PUT", "api/bills/\(b.id.uuidString.lowercased())", body: b)
    }

    func putExpense(_ e: ExpenseDTO) async throws -> ExpenseDTO {
        try await send("PUT", "api/expenses/\(e.id.uuidString.lowercased())", body: e)
    }

    /// Deleting something the server never had is fine.
    func deleteBill(_ id: UUID) async throws { try await delete("api/bills/\(id.uuidString.lowercased())") }
    func deleteExpense(_ id: UUID) async throws { try await delete("api/expenses/\(id.uuidString.lowercased())") }

    // MARK: Plumbing

    private func delete(_ path: String) async throws {
        do {
            _ = try await raw("DELETE", path, body: nil, query: [])
        } catch APIError.server(status: 404, _) {
            // already gone
        }
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil,
                                    query: [URLQueryItem] = []) async throws -> T {
        let data = try await raw(method, path, body: try body.map { try APIDate.encoder.encode($0) }, query: query)
        do {
            return try APIDate.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.server(status: 0, message: String(localized: "Unexpected reply from the server"))
        }
    }

    private func raw(_ method: String, _ path: String, body: Data?, query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized(message: ProblemDTO.detail(in: data))
        default:
            throw APIError.server(status: status, message: ProblemDTO.detail(in: data) ?? String(localized: "Server error \(status)"))
        }
    }
}

enum APIError: Error, Equatable, LocalizedError {
    case offline
    case unauthorized(message: String?)
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .offline: return String(localized: "Can't reach the server. Check your internet and try again.")
        case .unauthorized(let message): return message ?? String(localized: "Please sign in again.")
        case .server(_, let message): return message
        }
    }
}

// MARK: - JSON shapes (same as the server's)

struct LoginDTO: Encodable { let email: String; let password: String }

struct TokenDTO: Decodable {
    let token: String
    let expiresAt: Date
    let userId: UUID
}

struct SettingsDTO: Codable, Equatable {
    var startMonth: String
    var monthCount: Int
    var totalCents: Int
    var livingMonthlyCents: Int
    var engagementCents: Int
    var firstOpenedAt: Date?
}

struct BillDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var amountCents: Int
    var sortOrder: Int
    var dueMonths: [String]
    var paidMonths: [String]
    var deleted: Bool? = nil
}

struct ExpenseDTO: Codable, Equatable {
    var id: UUID
    var amountCents: Int
    var category: String
    var note: String
    var spentAt: Date
    var billId: UUID?
    var billMonth: String?
    var deleted: Bool? = nil
}

struct ChangesDTO: Decodable {
    /// Kept exactly as the server sent it, and sent back as `since` next time.
    var serverTime: String
    var settings: SettingsDTO?
    var bills: [BillDTO]
    var expenses: [ExpenseDTO]
}

/// Spring's error body: {"title": "...", "detail": "Wrong email or password", "status": 401}
struct ProblemDTO: Decodable {
    var detail: String?
    static func detail(in data: Data) -> String? {
        (try? JSONDecoder().decode(ProblemDTO.self, from: data))?.detail
    }
}

/// Dates on the wire: ISO 8601 in UTC. We send milliseconds; the server may answer with more digits.
enum APIDate {
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Whole milliseconds since 1970: the precision both sides keep.
    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    static func fromMilliseconds(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    static func string(_ date: Date) -> String {
        let ms = milliseconds(date)
        let seconds = Date(timeIntervalSince1970: Double(ms / 1000))
        let base = plain.string(from: seconds).dropLast() // drop the "Z"
        return base + String(format: ".%03dZ", Int(ms % 1000))
    }

    /// Accepts "2026-11-04T01:00:00Z" and "2026-11-04T12:04:19.262272097Z". Extra digits are cut to milliseconds.
    static func parse(_ text: String) -> Date? {
        guard let dot = text.firstIndex(of: ".") else { return plain.date(from: text) }
        let afterDot = text[text.index(after: dot)...]
        let digits = afterDot.prefix { $0.isNumber }
        let zone = afterDot.dropFirst(digits.count)
        guard let whole = plain.date(from: String(text[..<dot]) + zone) else { return nil }
        let ms = Int64(String((digits + "000").prefix(3))) ?? 0
        return fromMilliseconds(milliseconds(whole) + ms)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(string(date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let text = try c.decode(String.self)
            guard let date = parse(text) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(text)")
            }
            return date
        }
        return d
    }()
}
