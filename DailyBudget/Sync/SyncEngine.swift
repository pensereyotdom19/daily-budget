import Foundation
import SwiftData

/// One sync: upload what changed on this phone, then download what changed on the server.
///
/// How it knows what changed: `SyncState` remembers a fingerprint of every record as it was at the
/// last sync. A record whose fingerprint differs was edited here; a remembered id that is gone was
/// deleted here. Nothing else in the app has to tell the sync about changes.
///
/// If the same record changed on both sides, this phone wins (it is uploaded again next time).
@MainActor
struct SyncEngine {
    let api: APIClient
    let context: ModelContext

    struct Report: Equatable {
        var uploaded = 0
        var downloaded = 0
        var restoredFromServer = false
        /// Records the server refused (e.g. a note that is too long). Everything else still synced.
        var problems: [String] = []
    }

    func run(state: inout SyncState) async throws -> Report {
        var report = Report()
        if state.lastServerTime == nil {
            try await restoreIfServerHasData(state: &state, report: &report)
        }
        try await upload(state: &state, report: &report)
        try await download(state: &state, report: &report)
        return report
    }

    /// How many records on this phone are waiting to be uploaded.
    static func pendingCount(context: ModelContext, state: SyncState) -> Int {
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let bills = (try? context.fetch(FetchDescriptor<Bill>())) ?? []
        let settings = (try? context.fetch(FetchDescriptor<BudgetSettings>()))?.first
        var count = 0
        count += expenses.filter { state.expenses[$0.id] != Fingerprint.of($0) }.count
        count += bills.filter { state.bills[$0.id] != Fingerprint.of($0) }.count
        count += Set(state.expenses.keys).subtracting(expenses.map(\.id)).count
        count += Set(state.bills.keys).subtracting(bills.map(\.id)).count
        if let settings, state.settings != Fingerprint.of(settings) { count += 1 }
        return count
    }

    // MARK: First sync on a phone

    /// The first sync of an account on this phone. If the server already has a plan (for example after
    /// reinstalling the app), the server's plan and bills replace the default ones made at install,
    /// instead of creating duplicates. Expenses added on this phone are kept and uploaded.
    private func restoreIfServerHasData(state: inout SyncState, report: inout Report) async throws {
        let remote = try await api.changes(since: nil)
        let remoteBills = remote.bills.filter { $0.deleted != true }
        guard remote.settings != nil || !remoteBills.isEmpty else { return }

        let keep = Set(remoteBills.map(\.id))
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        for bill in try context.fetch(FetchDescriptor<Bill>()) where !keep.contains(bill.id) {
            for e in expenses where e.billID == bill.id { context.delete(e) }
            context.delete(bill)
        }
        apply(remote, force: true, state: &state, report: &report)
        state.lastServerTime = remote.serverTime
        report.restoredFromServer = true
        try context.save()
    }

    // MARK: Upload

    private func upload(state: inout SyncState, report: inout Report) async throws {
        let settings = try context.fetch(FetchDescriptor<BudgetSettings>()).first
        let bills = try context.fetch(FetchDescriptor<Bill>())
        let expenses = try context.fetch(FetchDescriptor<Expense>())

        if let settings {
            let fp = Fingerprint.of(settings)
            if state.settings != fp {
                try await attempt("Plan", report: &report) {
                    _ = try await api.putSettings(DTO.settings(settings))
                    state.settings = fp
                }
            }
        }

        for bill in bills {
            let fp = Fingerprint.of(bill)
            guard state.bills[bill.id] != fp else { continue }
            try await attempt("Bill \(bill.name)", report: &report) {
                _ = try await api.putBill(DTO.bill(bill))
                state.bills[bill.id] = fp
            }
        }
        for id in Set(state.bills.keys).subtracting(bills.map(\.id)) {
            try await attempt("Deleted bill", report: &report) {
                try await api.deleteBill(id)
                state.bills[id] = nil
            }
        }

        for expense in expenses {
            let fp = Fingerprint.of(expense)
            guard state.expenses[expense.id] != fp else { continue }
            try await attempt(expense.note.isEmpty ? expense.category.title : expense.note, report: &report) {
                _ = try await api.putExpense(DTO.expense(expense))
                state.expenses[expense.id] = fp
            }
        }
        for id in Set(state.expenses.keys).subtracting(expenses.map(\.id)) {
            try await attempt("Deleted expense", report: &report) {
                try await api.deleteExpense(id)
                state.expenses[id] = nil
            }
        }
    }

    /// Runs one upload. A record the server refuses is reported and skipped; being offline or
    /// signed out stops the whole sync.
    private func attempt(_ label: String, report: inout Report, _ work: () async throws -> Void) async throws {
        do {
            try await work()
            report.uploaded += 1
        } catch APIError.server(let status, let message) where (400..<500).contains(status) {
            report.problems.append("\(label): \(message)")
        }
    }

    // MARK: Download

    private func download(state: inout SyncState, report: inout Report) async throws {
        let changes = try await api.changes(since: state.lastServerTime)
        apply(changes, force: false, state: &state, report: &report)
        state.lastServerTime = changes.serverTime
        if context.hasChanges { try context.save() }
    }

    /// Copies server records into the phone's database. Unless `force`, a record that was changed
    /// or deleted on this phone since the last sync is left alone: it will be uploaded next time.
    /// (A record can be deleted while a sync is running, after its upload step has passed.)
    private func apply(_ changes: ChangesDTO, force: Bool, state: inout SyncState, report: inout Report) {
        if let remote = changes.settings {
            let local = (try? context.fetch(FetchDescriptor<BudgetSettings>()))?.first
            let changedHere = local.map { state.settings != Fingerprint.of($0) } ?? false
            if force || !changedHere {
                let target = local ?? { let s = BudgetSettings(); context.insert(s); return s }()
                if Fingerprint.of(target) != Fingerprint.of(remote) { report.downloaded += 1 }
                target.startMonth = remote.startMonth
                target.monthCount = remote.monthCount
                target.totalCents = remote.totalCents
                target.livingMonthlyCents = remote.livingMonthlyCents
                target.engagementCents = remote.engagementCents
                target.firstOpenedAt = remote.firstOpenedAt
                state.settings = Fingerprint.of(remote)
            }
        }

        let localBills = Dictionary(((try? context.fetch(FetchDescriptor<Bill>())) ?? []).map { ($0.id, $0) },
                                    uniquingKeysWith: { a, _ in a })
        for remote in changes.bills {
            let local = localBills[remote.id]
            if let local, !force, state.bills[remote.id] != Fingerprint.of(local) { continue }
            // Deleted on this phone but the server hasn't heard yet: don't bring it back.
            if local == nil, !force, state.bills[remote.id] != nil, remote.deleted != true { continue }
            if remote.deleted == true {
                if let local { context.delete(local); report.downloaded += 1 }
                state.bills[remote.id] = nil
                continue
            }
            let target = local ?? {
                let b = Bill(name: remote.name, amountCents: remote.amountCents, dueMonths: [], sortOrder: remote.sortOrder)
                b.id = remote.id
                context.insert(b)
                return b
            }()
            if local == nil || Fingerprint.of(target) != Fingerprint.of(remote) { report.downloaded += 1 }
            target.name = remote.name
            target.amountCents = remote.amountCents
            target.sortOrder = remote.sortOrder
            target.dueMonths = remote.dueMonths.sorted()
            target.paidMonths = remote.paidMonths.sorted()
            state.bills[remote.id] = Fingerprint.of(remote)
        }

        let localExpenses = Dictionary(((try? context.fetch(FetchDescriptor<Expense>())) ?? []).map { ($0.id, $0) },
                                       uniquingKeysWith: { a, _ in a })
        for remote in changes.expenses {
            let local = localExpenses[remote.id]
            if let local, !force, state.expenses[remote.id] != Fingerprint.of(local) { continue }
            // Deleted on this phone but the server hasn't heard yet: don't bring it back.
            if local == nil, !force, state.expenses[remote.id] != nil, remote.deleted != true { continue }
            if remote.deleted == true {
                if let local { context.delete(local); report.downloaded += 1 }
                state.expenses[remote.id] = nil
                continue
            }
            let target = local ?? {
                let e = Expense(amountCents: remote.amountCents, category: .other)
                e.id = remote.id
                context.insert(e)
                return e
            }()
            if local == nil || Fingerprint.of(target) != Fingerprint.of(remote) { report.downloaded += 1 }
            target.amountCents = remote.amountCents
            target.categoryRaw = Category(rawValue: remote.category)?.rawValue ?? Category.other.rawValue
            target.note = remote.note
            target.date = remote.spentAt
            target.billID = remote.billId
            target.billMonth = remote.billMonth
            state.expenses[remote.id] = Fingerprint.of(remote)
        }
    }
}

/// Phone records → server JSON.
enum DTO {
    static func settings(_ s: BudgetSettings) -> SettingsDTO {
        SettingsDTO(startMonth: s.startMonth, monthCount: s.monthCount, totalCents: s.totalCents,
                    livingMonthlyCents: s.livingMonthlyCents, engagementCents: s.engagementCents,
                    firstOpenedAt: s.firstOpenedAt)
    }

    static func bill(_ b: Bill) -> BillDTO {
        BillDTO(id: b.id, name: b.name, amountCents: b.amountCents, sortOrder: b.sortOrder,
                dueMonths: b.dueMonths.sorted(), paidMonths: b.paidMonths.sorted())
    }

    static func expense(_ e: Expense) -> ExpenseDTO {
        ExpenseDTO(id: e.id, amountCents: e.amountCents, category: e.categoryRaw, note: e.note,
                   spentAt: e.date, billId: e.billID, billMonth: e.billMonth)
    }
}

/// The synced fields of a record joined into one string. Equal fingerprints = nothing to sync.
/// Phone records and server JSON produce the same fingerprint for the same content.
enum Fingerprint {
    private static func join(_ parts: [String]) -> String { parts.joined(separator: "\u{1F}") }
    private static func ms(_ d: Date?) -> String { d.map { String(APIDate.milliseconds($0)) } ?? "" }

    static func of(_ s: BudgetSettings) -> String { of(DTO.settings(s)) }
    static func of(_ s: SettingsDTO) -> String {
        join([s.startMonth, "\(s.monthCount)", "\(s.totalCents)", "\(s.livingMonthlyCents)",
              "\(s.engagementCents)", ms(s.firstOpenedAt)])
    }

    static func of(_ b: Bill) -> String { of(DTO.bill(b)) }
    static func of(_ b: BillDTO) -> String {
        join([b.name, "\(b.amountCents)", "\(b.sortOrder)",
              b.dueMonths.sorted().joined(separator: ","), b.paidMonths.sorted().joined(separator: ",")])
    }

    static func of(_ e: Expense) -> String { of(DTO.expense(e)) }
    static func of(_ e: ExpenseDTO) -> String {
        join(["\(e.amountCents)", e.category, e.note, ms(e.spentAt),
              e.billId?.uuidString ?? "", e.billMonth ?? ""])
    }
}
