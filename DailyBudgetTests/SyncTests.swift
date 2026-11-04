import XCTest
import SwiftData
@testable import DailyBudget

/// Sync against a fake server that behaves like the real one (PUT = create or replace,
/// DELETE = soft delete, /api/sync?since= returns only newer changes, notes are trimmed).
@MainActor
final class SyncTests: XCTestCase {
    private var server: FakeServer!
    private var session: URLSession!
    /// A ModelContext only works while its container is alive, so tests keep theirs here.
    private var containers: [ModelContainer] = []

    override func setUp() {
        server = FakeServer()
        FakeServerProtocol.server = server
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeServerProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        FakeServerProtocol.server = nil
        containers.removeAll()
        server = nil
        session = nil
    }

    private func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(for: Expense.self, Bill.self, BudgetSettings.self, Income.self, RecurringExpense.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        containers.append(container)
        return container
    }

    private func engine(_ context: ModelContext, token: String = FakeServer.goodToken) -> SyncEngine {
        SyncEngine(api: APIClient(baseURL: URL(string: "https://fake.test")!, session: session, token: token),
                   context: context)
    }

    private func date(_ text: String) -> Date { APIDate.parse(text)! }

    func testFirstSyncUploadsEverythingAndASecondSyncSendsNothing() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        Seed.insertIfNeeded(into: context)
        context.insert(Expense(amountCents: 125, category: .coffee, note: "Iced latte  ", date: date("2026-11-04T01:00:00.123Z")))
        try context.save()
        var state = SyncState()

        let first = try await engine(context).run(state: &state)
        XCTAssertEqual(first.uploaded, 8)  // plan + 6 bills + 1 expense
        XCTAssertEqual(server.settings?.livingMonthlyCents, 9_200)
        XCTAssertEqual(server.liveBills.count, 6)
        XCTAssertEqual(server.liveExpenses.map(\.note), ["Iced latte"])  // the server trims notes…
        XCTAssertEqual(try context.fetch(FetchDescriptor<Expense>()).first?.note, "Iced latte")  // …and the phone takes that

        server.requests.removeAll()
        let second = try await engine(context).run(state: &state)
        XCTAssertEqual(second.uploaded, 0)
        XCTAssertEqual(server.requests.filter { $0.hasPrefix("PUT") || $0.hasPrefix("DELETE") }, [])
        XCTAssertEqual(SyncEngine.pendingCount(context: context, state: state), 0)
    }

    func testEditsAndDeletesOnThePhoneAreUploaded() async throws {
        let context = try makeContainer().mainContext
        Seed.insertIfNeeded(into: context)
        let coffee = Expense(amountCents: 125, category: .coffee, note: "Coffee", date: date("2026-11-04T01:00:00Z"))
        context.insert(coffee)
        try context.save()
        var state = SyncState()
        _ = try await engine(context).run(state: &state)

        coffee.amountCents = 150
        let water = try context.fetch(FetchDescriptor<Bill>()).first { $0.name == "Water" }!
        context.delete(water)
        try context.save()
        XCTAssertEqual(SyncEngine.pendingCount(context: context, state: state), 2)

        server.requests.removeAll()
        _ = try await engine(context).run(state: &state)
        XCTAssertEqual(server.requests.filter { !$0.hasPrefix("GET") }.sorted(),
                       ["DELETE /api/bills/\(water.id.uuidString.lowercased())",
                        "PUT /api/expenses/\(coffee.id.uuidString.lowercased())"])
        XCTAssertEqual(server.liveExpenses.first?.amountCents, 150)
        XCTAssertEqual(server.liveBills.count, 5)
        XCTAssertEqual(SyncEngine.pendingCount(context: context, state: state), 0)
    }

    func testChangesFromAnotherDeviceAreDownloaded() async throws {
        let context = try makeContainer().mainContext
        Seed.insertIfNeeded(into: context)
        let coffee = Expense(amountCents: 125, category: .coffee, note: "Coffee", date: date("2026-11-04T01:00:00Z"))
        context.insert(coffee)
        try context.save()
        var state = SyncState()
        _ = try await engine(context).run(state: &state)

        let wifi = try context.fetch(FetchDescriptor<Bill>()).first { $0.name == "Wifi" }!
        server.change { s in
            s.bills[wifi.id]!.dto.amountCents = 2_000
            s.expenses[coffee.id]!.dto.deleted = true
            let lunch = UUID()
            s.expenses[lunch] = .init(dto: ExpenseDTO(id: lunch, amountCents: 300, category: "food", note: "Lunch",
                                                      spentAt: self.date("2026-11-04T05:00:00Z")))
        }

        let report = try await engine(context).run(state: &state)
        XCTAssertEqual(report.downloaded, 3)
        XCTAssertEqual(wifi.amountCents, 2_000)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Expense>()).map(\.note), ["Lunch"])
        XCTAssertEqual(SyncEngine.pendingCount(context: context, state: state), 0)
    }

    func testWhenBothSidesChangedTheSameExpenseThePhoneWins() async throws {
        let context = try makeContainer().mainContext
        let coffee = Expense(amountCents: 125, category: .coffee, note: "Coffee", date: date("2026-11-04T01:00:00Z"))
        context.insert(coffee)
        try context.save()
        var state = SyncState()
        _ = try await engine(context).run(state: &state)

        server.change { $0.expenses[coffee.id]!.dto.amountCents = 999 }
        coffee.amountCents = 500
        try context.save()

        _ = try await engine(context).run(state: &state)
        XCTAssertEqual(coffee.amountCents, 500)
        XCTAssertEqual(server.liveExpenses.first?.amountCents, 500)
    }

    func testReinstallingRestoresTheServerDataWithoutDuplicateBills() async throws {
        // First phone: plan, bills, one paid bill and a coffee, all uploaded.
        let oldPhone = try makeContainer().mainContext
        Seed.insertIfNeeded(into: oldPhone)
        let bank = try oldPhone.fetch(FetchDescriptor<Bill>()).first { $0.name == "Bank" }!
        BillPayments.setPaid(true, bill: bank, month: "2026-11", in: oldPhone)
        oldPhone.insert(Expense(amountCents: 125, category: .coffee, note: "Old coffee", date: date("2026-11-03T01:00:00Z")))
        let plan = try oldPhone.fetch(FetchDescriptor<BudgetSettings>()).first!
        plan.livingMonthlyCents = 10_000
        try oldPhone.save()
        var oldState = SyncState()
        _ = try await engine(oldPhone).run(state: &oldState)

        // Fresh install: the app seeds new default bills (new ids) and you add a coffee before signing in.
        let newPhone = try makeContainer().mainContext
        Seed.insertIfNeeded(into: newPhone)
        newPhone.insert(Expense(amountCents: 200, category: .coffee, note: "New coffee", date: date("2026-11-05T01:00:00Z")))
        try newPhone.save()
        var newState = SyncState()
        let report = try await engine(newPhone).run(state: &newState)

        XCTAssertTrue(report.restoredFromServer)
        let bills = try newPhone.fetch(FetchDescriptor<Bill>())
        XCTAssertEqual(bills.count, 6)
        XCTAssertEqual(Set(bills.map(\.id)), Set(server.liveBills.map(\.id)))
        XCTAssertEqual(bills.first { $0.name == "Bank" }?.paidMonths, ["2026-11"])
        XCTAssertEqual(try newPhone.fetch(FetchDescriptor<BudgetSettings>()).first?.livingMonthlyCents, 10_000)
        XCTAssertEqual(Set(try newPhone.fetch(FetchDescriptor<Expense>()).map(\.note)), ["Bank", "Old coffee", "New coffee"])
        XCTAssertEqual(server.liveBills.count, 6)
        XCTAssertEqual(Set(server.liveExpenses.map(\.note)), ["Bank", "Old coffee", "New coffee"])
    }

    func testAnExpenseDeletedOnThePhoneIsNotBroughtBackByTheDownload() async throws {
        let context = try makeContainer().mainContext
        let coffee = Expense(amountCents: 125, category: .coffee, note: "Coffee", date: date("2026-11-04T01:00:00Z"))
        context.insert(coffee)
        try context.save()
        var state = SyncState()
        _ = try await engine(context).run(state: &state)

        // The server has a newer copy (as if the upload landed during this sync) and the phone deleted it,
        // but the delete hasn't reached the server yet.
        let id = coffee.id
        server.change { $0.expenses[id]!.dto.amountCents = 150 }
        context.delete(coffee)
        try context.save()
        server.refuseDeletes = true
        _ = try await engine(context).run(state: &state)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
        XCTAssertEqual(SyncEngine.pendingCount(context: context, state: state), 1)  // delete still waiting

        server.refuseDeletes = false
        _ = try await engine(context).run(state: &state)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Expense>()).isEmpty)
        XCTAssertTrue(server.liveExpenses.isEmpty)
        XCTAssertEqual(SyncEngine.pendingCount(context: context, state: state), 0)
    }

    func testABillDeletedOnThePhoneIsNotBroughtBackByTheDownload() async throws {
        let context = try makeContainer().mainContext
        Seed.insertIfNeeded(into: context)
        var state = SyncState()
        _ = try await engine(context).run(state: &state)

        let water = try context.fetch(FetchDescriptor<Bill>()).first { $0.name == "Water" }!
        let id = water.id
        server.change { $0.bills[id]!.dto.amountCents = 600 }
        context.delete(water)
        try context.save()
        server.refuseDeletes = true
        _ = try await engine(context).run(state: &state)
        XCTAssertNil(try context.fetch(FetchDescriptor<Bill>()).first { $0.id == id })
    }

    func testIncomeRecurringAndPlanHistoryAreBackedUp() async throws {
        let context = try makeContainer().mainContext
        Seed.insertIfNeeded(into: context)
        let plan = try context.fetch(FetchDescriptor<BudgetSettings>()).first!
        plan.historyStartMonth = "2026-11"
        plan.savedBeforeCents = 4_200
        let gift = Income(amountCents: 2_000, target: .savings, note: "Gift", date: date("2026-11-04T03:00:00Z"))
        let topUp = RecurringExpense(amountCents: 500, category: .phone, note: "Top-up", dayOfMonth: 5, startMonth: "2026-11")
        topUp.lastAddedMonth = "2026-11"
        context.insert(gift)
        context.insert(topUp)
        try context.save()
        var state = SyncState()
        _ = try await engine(context).run(state: &state)

        XCTAssertEqual(server.liveIncomes.map(\.target), ["savings"])
        XCTAssertEqual(server.liveRecurring.first?.lastAddedMonth, "2026-11")
        XCTAssertEqual(server.settings?.savedBeforeCents, 4_200)
        XCTAssertEqual(server.settings?.historyStartMonth, "2026-11")
        XCTAssertEqual(SyncEngine.pendingCount(context: context, state: state), 0)

        context.delete(gift)
        topUp.amountCents = 600
        try context.save()
        XCTAssertEqual(SyncEngine.pendingCount(context: context, state: state), 2)
        _ = try await engine(context).run(state: &state)
        XCTAssertTrue(server.liveIncomes.isEmpty)
        XCTAssertEqual(server.liveRecurring.first?.amountCents, 600)
    }

    func testReinstallRestoresIncomeRecurringAndPlanHistoryWithoutAddingRecurringTwice() async throws {
        let oldPhone = try makeContainer().mainContext
        Seed.insertIfNeeded(into: oldPhone)
        let plan = try oldPhone.fetch(FetchDescriptor<BudgetSettings>()).first!
        plan.savedBeforeCents = 4_200
        oldPhone.insert(Income(amountCents: 2_000, target: .living, note: "Gift", date: date("2026-11-04T03:00:00Z")))
        let topUp = RecurringExpense(amountCents: 500, category: .phone, note: "Top-up", dayOfMonth: 1, startMonth: "2026-11")
        oldPhone.insert(topUp)
        try oldPhone.save()
        RecurringRunner.addDue(in: oldPhone, now: date("2026-11-04T05:00:00Z"))
        var oldState = SyncState()
        _ = try await engine(oldPhone).run(state: &oldState)

        let newPhone = try makeContainer().mainContext
        Seed.insertIfNeeded(into: newPhone)
        var newState = SyncState()
        _ = try await engine(newPhone).run(state: &newState)

        XCTAssertEqual(try newPhone.fetch(FetchDescriptor<Income>()).map(\.note), ["Gift"])
        XCTAssertEqual(try newPhone.fetch(FetchDescriptor<BudgetSettings>()).first?.savedBeforeCents, 4_200)
        let restored = try newPhone.fetch(FetchDescriptor<RecurringExpense>())
        XCTAssertEqual(restored.first?.lastAddedMonth, "2026-11")
        // Opening the restored app in the same month must not add the top-up again.
        XCTAssertEqual(RecurringRunner.addDue(in: newPhone, now: date("2026-11-04T06:00:00Z")), 0)
        XCTAssertEqual(try newPhone.fetch(FetchDescriptor<Expense>()).filter { $0.note == "Top-up" }.count, 1)
    }

    @MainActor
    func testCategoryLimitsTravelWithThePlan() async throws {
        let oldPhone = try makeContainer().mainContext
        Seed.insertIfNeeded(into: oldPhone)
        try oldPhone.fetch(FetchDescriptor<BudgetSettings>()).first!.categoryLimits = ["coffee": 1_500, "fun": 0]
        try oldPhone.save()
        var state = SyncState()
        _ = try await engine(oldPhone).run(state: &state)
        XCTAssertEqual(server.settings?.categoryLimits, ["coffee": 1_500])  // 0 means no limit

        let newPhone = try makeContainer().mainContext
        Seed.insertIfNeeded(into: newPhone)
        var newState = SyncState()
        _ = try await engine(newPhone).run(state: &newState)
        XCTAssertEqual(try newPhone.fetch(FetchDescriptor<BudgetSettings>()).first?.categoryLimits, ["coffee": 1_500])
    }

    func testDownloadsAskFromAFewSecondsBeforeLastTime() async throws {
        let context = try makeContainer().mainContext
        var state = SyncState()
        state.lastServerTime = "2026-11-04T10:00:10.000Z"
        state.userID = UUID()
        server.requests.removeAll()
        _ = try await engine(context).run(state: &state)
        let sync = server.requests.first { $0.hasPrefix("GET /api/sync") }
        XCTAssertNotNil(sync)
        XCTAssertEqual(server.lastSince, "2026-11-04T10:00:05.000Z")
    }

    func testAnExpiredSignInStopsTheSync() async throws {
        let context = try makeContainer().mainContext
        var state = SyncState()
        do {
            _ = try await engine(context, token: "expired").run(state: &state)
            XCTFail("expected unauthorized")
        } catch APIError.unauthorized {
            // expected
        }
    }

    func testARecordTheServerRefusesIsReportedAndTheRestStillSyncs() async throws {
        let context = try makeContainer().mainContext
        context.insert(Expense(amountCents: 100, category: .food, note: String(repeating: "x", count: 250)))
        context.insert(Expense(amountCents: 200, category: .food, note: "Rice"))
        try context.save()
        var state = SyncState()

        let report = try await engine(context).run(state: &state)
        XCTAssertEqual(report.problems.count, 1)
        XCTAssertEqual(server.liveExpenses.map(\.note), ["Rice"])
        XCTAssertEqual(SyncEngine.pendingCount(context: context, state: state), 1)  // tried again next time
    }

    func testServerDatesAreReadToTheMillisecond() {
        XCTAssertEqual(APIDate.milliseconds(APIDate.parse("2026-11-04T12:04:19.262272097Z")!), 1_793_793_859_262)
        XCTAssertEqual(APIDate.milliseconds(APIDate.parse("2026-11-04T12:04:19Z")!), 1_793_793_859_000)
        XCTAssertEqual(APIDate.string(APIDate.parse("2026-11-04T12:04:19.5Z")!), "2026-11-04T12:04:19.500Z")
    }
}

// MARK: - Fake server

final class FakeServer {
    static let goodToken = "good-token"

    struct Stored<T> { var dto: T; var updated = 0 }

    var tick = 0
    var settings: SettingsDTO?
    var settingsUpdated = 0
    var bills: [UUID: Stored<BillDTO>] = [:]
    var expenses: [UUID: Stored<ExpenseDTO>] = [:]
    var incomes: [UUID: Stored<IncomeDTO>] = [:]
    var recurring: [UUID: Stored<RecurringDTO>] = [:]
    var requests: [String] = []
    var lastSince: String?
    /// Makes DELETE fail with 409, to leave a delete waiting on the phone.
    var refuseDeletes = false

    var liveBills: [BillDTO] { bills.values.map(\.dto).filter { $0.deleted != true } }
    var liveExpenses: [ExpenseDTO] { expenses.values.map(\.dto).filter { $0.deleted != true } }
    var liveIncomes: [IncomeDTO] { incomes.values.map(\.dto).filter { $0.deleted != true } }
    var liveRecurring: [RecurringDTO] { recurring.values.map(\.dto).filter { $0.deleted != true } }

    /// Simulates edits made from another device: everything touched gets a newer time.
    func change(_ edit: (FakeServer) -> Void) {
        let beforeBills = bills.mapValues { $0.dto }
        let beforeExpenses = expenses.mapValues { $0.dto }
        edit(self)
        for (id, b) in bills where beforeBills[id] != b.dto { tick += 1; bills[id]!.updated = tick }
        for (id, e) in expenses where beforeExpenses[id] != e.dto { tick += 1; expenses[id]!.updated = tick }
    }

    private static let epochMS: Int64 = 1_793_750_400_000  // 2026-11-04T00:00:00Z
    private func time(_ t: Int) -> String { APIDate.string(APIDate.fromMilliseconds(Self.epochMS + Int64(t))) }
    private func ticks(_ text: String) -> Int { Int(APIDate.milliseconds(APIDate.parse(text)!) - Self.epochMS) }

    struct Changes: Encodable {
        var serverTime: String
        var settings: SettingsDTO?
        var bills: [BillDTO]
        var expenses: [ExpenseDTO]
        var incomes: [IncomeDTO]
        var recurring: [RecurringDTO]
    }

    func handle(_ request: URLRequest, body: Data?) -> (Int, Data) {
        let method = request.httpMethod ?? "GET"
        let path = request.url!.path
        requests.append("\(method) \(path)")
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.goodToken)" else {
            return (401, Data(#"{"detail":"Unauthorized"}"#.utf8))
        }
        let parts = path.split(separator: "/").map(String.init)  // ["api", "bills", "<id>"]
        let id = parts.count == 3 ? UUID(uuidString: parts[2]) : nil

        switch (method, parts.count > 1 ? parts[1] : "") {
        case ("GET", "sync"):
            lastSince = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "since" }?.value
            let since = lastSince.map(ticks)
            let newer: (Int) -> Bool = { since == nil || $0 > since! }
            let reply = Changes(serverTime: time(tick),
                                settings: newer(settingsUpdated) ? settings : nil,
                                bills: bills.values.filter { newer($0.updated) }.map(\.dto),
                                expenses: expenses.values.filter { newer($0.updated) }.map(\.dto),
                                incomes: incomes.values.filter { newer($0.updated) }.map(\.dto),
                                recurring: recurring.values.filter { newer($0.updated) }.map(\.dto))
            return (200, try! APIDate.encoder.encode(reply))

        case ("PUT", "settings"):
            settings = try! APIDate.decoder.decode(SettingsDTO.self, from: body!)
            tick += 1; settingsUpdated = tick
            return (200, try! APIDate.encoder.encode(settings))

        case ("PUT", "bills"):
            var b = try! APIDate.decoder.decode(BillDTO.self, from: body!)
            b.id = id!; b.name = b.name.trimmingCharacters(in: .whitespaces); b.deleted = false
            tick += 1; bills[id!] = Stored(dto: b, updated: tick)
            return (200, try! APIDate.encoder.encode(b))

        case ("PUT", "expenses"):
            var e = try! APIDate.decoder.decode(ExpenseDTO.self, from: body!)
            if e.note.count > 200 { return (400, Data(#"{"detail":"note: size must be between 0 and 200"}"#.utf8)) }
            e.id = id!; e.note = e.note.trimmingCharacters(in: .whitespaces); e.deleted = false
            tick += 1; expenses[id!] = Stored(dto: e, updated: tick)
            return (200, try! APIDate.encoder.encode(e))

        case ("DELETE", _) where refuseDeletes:
            return (409, Data(#"{"detail":"Try again later"}"#.utf8))

        case ("PUT", "incomes"):
            var i = try! APIDate.decoder.decode(IncomeDTO.self, from: body!)
            i.id = id!; i.note = i.note.trimmingCharacters(in: .whitespaces); i.deleted = false
            tick += 1; incomes[id!] = Stored(dto: i, updated: tick)
            return (200, try! APIDate.encoder.encode(i))

        case ("PUT", "recurring"):
            var r = try! APIDate.decoder.decode(RecurringDTO.self, from: body!)
            r.id = id!; r.deleted = false
            tick += 1; recurring[id!] = Stored(dto: r, updated: tick)
            return (200, try! APIDate.encoder.encode(r))

        case ("DELETE", "incomes"):
            guard incomes[id!] != nil else { return (404, Data()) }
            tick += 1; incomes[id!]!.dto.deleted = true; incomes[id!]!.updated = tick
            return (204, Data())

        case ("DELETE", "recurring"):
            guard recurring[id!] != nil else { return (404, Data()) }
            tick += 1; recurring[id!]!.dto.deleted = true; recurring[id!]!.updated = tick
            return (204, Data())

        case ("DELETE", "bills"):
            guard bills[id!] != nil else { return (404, Data()) }
            tick += 1; bills[id!]!.dto.deleted = true; bills[id!]!.updated = tick
            return (204, Data())

        case ("DELETE", "expenses"):
            guard expenses[id!] != nil else { return (404, Data()) }
            tick += 1; expenses[id!]!.dto.deleted = true; expenses[id!]!.updated = tick
            return (204, Data())

        default:
            return (404, Data())
        }
    }
}

final class FakeServerProtocol: URLProtocol {
    static var server: FakeServer?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let server = Self.server else { return }
        let (status, data) = server.handle(request, body: Self.body(of: request))
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands the body to URLProtocol as a stream.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
