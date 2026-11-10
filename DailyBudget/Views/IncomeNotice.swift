import SwiftUI
import SwiftData

/// After you save new income, shows "+$100.00 · This month's everyday money" with Undo for a few seconds,
/// so you can see where the money went.
@MainActor @Observable
final class IncomeNotice {
    static let shared = IncomeNotice()
    init() {}

    struct Snapshot: Equatable {
        var incomeID: UUID
        var cents: Int
        var target: IncomeTarget
        var token = UUID()
    }

    private(set) var last: Snapshot?
    private var hideTask: Task<Void, Never>?

    func show(_ income: Income) {
        withAnimation(.snappy) { last = Snapshot(incomeID: income.id, cents: income.amountCents, target: income.target) }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.last = nil }
        }
    }

    /// Removes the income that was just added.
    func undo(in context: ModelContext) {
        guard let s = last else { return }
        hideTask?.cancel()
        withAnimation(.snappy) { last = nil }
        let id = s.incomeID
        if let income = try? context.fetch(FetchDescriptor<Income>(predicate: #Predicate { $0.id == id })).first {
            context.delete(income)
            try? context.save()
        }
    }
}

struct IncomeBar: View {
    let snapshot: IncomeNotice.Snapshot
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            IncomeIcon(target: snapshot.target, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("+\(Money.format(snapshot.cents, alwaysShowCents: true))")
                    .font(Theme.rounded(16)).foregroundStyle(Theme.mint)
                Text(snapshot.target.effect).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.mint)
        }
        .padding(.horizontal, 14).frame(height: 58)
        .glassCard()
        .padding(.horizontal, 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Undo"), onUndo)
    }
}
