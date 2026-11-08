import SwiftUI
import SwiftData

/// Deleting an expense shows "Deleted · Undo" for a few seconds, in case it was a slip of the thumb.
/// Undo puts back a copy with a new id, so sync treats it as a fresh expense whether or not
/// the delete was already sent to the server.
@MainActor @Observable
final class DeleteUndo {
    static let shared = DeleteUndo()
    init() {}

    struct Snapshot: Equatable {
        var amountCents: Int
        var categoryRaw: String
        var note: String
        var date: Date
        var billID: UUID?
        var billMonth: String?
        /// Changes on every delete, so a newer delete restarts the timer.
        var token = UUID()

        var title: String { note.isEmpty ? (Category(rawValue: categoryRaw) ?? .other).title : note }
    }

    private(set) var last: Snapshot?
    private var hideTask: Task<Void, Never>?
    static let visibleSeconds: Double = 5

    func delete(_ expense: Expense, in context: ModelContext) {
        let snap = Snapshot(amountCents: expense.amountCents, categoryRaw: expense.categoryRaw, note: expense.note,
                            date: expense.date, billID: expense.billID, billMonth: expense.billMonth)
        BillPayments.delete(expense, in: context)
        withAnimation(.snappy) { last = snap }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.visibleSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.last = nil }
        }
    }

    func undo(in context: ModelContext) {
        guard let s = last else { return }
        hideTask?.cancel()
        withAnimation(.snappy) { last = nil }
        Self.restore(s, in: context)
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.snappy) { last = nil }
    }

    /// Puts the expense back (and ticks its bill paid again if it was a bill payment).
    static func restore(_ s: Snapshot, in context: ModelContext) {
        let e = Expense(amountCents: s.amountCents, category: Category(rawValue: s.categoryRaw) ?? .other,
                        note: s.note, date: s.date)
        e.categoryRaw = s.categoryRaw
        e.billID = s.billID
        e.billMonth = s.billMonth
        context.insert(e)
        if let id = s.billID, let month = s.billMonth,
           let bill = ((try? context.fetch(FetchDescriptor<Bill>())) ?? []).first(where: { $0.id == id }),
           !bill.paidMonths.contains(month) {
            bill.paidMonths.append(month)
        }
        try? context.save()
    }
}

/// The bar above the tab bar.
struct UndoBar: View {
    let snapshot: DeleteUndo.Snapshot
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash").foregroundStyle(Theme.secondary)
            Text("Deleted \(snapshot.title) \(Money.format(snapshot.amountCents, alwaysShowCents: true))")
                .lineLimit(1)
            Spacer(minLength: 6)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.mint)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16).frame(height: 50)
        .glassCard()
        .padding(.horizontal, 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Undo"), onUndo)
    }
}
