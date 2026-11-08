import SwiftUI
import SwiftData

/// Swipe an expense row: left to delete, right to add the same thing again (now).
/// A short swipe shows the button; a long swipe does it straight away. Tap the row to close it.
struct ExpenseSwipe: ViewModifier {
    let expense: Expense
    @Environment(\.modelContext) private var context
    @State private var offset: CGFloat = 0
    @State private var settled: CGFloat = 0
    @State private var done = 0

    private let button: CGFloat = 86
    private let full: CGFloat = 170
    /// Bill payments are tied to their bill, so they can't be repeated by swiping.
    private var canRepeat: Bool { expense.billID == nil }

    func body(content: Content) -> some View {
        ZStack {
            HStack(spacing: 0) {
                if canRepeat && offset > 0 {
                    Button(action: addAgain) {
                        Label("Add again", systemImage: "arrow.uturn.backward")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: offset)
                    .foregroundStyle(Theme.base)
                    .background(Theme.mint)
                    .accessibilityLabel("Add again")
                }
                Spacer(minLength: 0)
                if offset < 0 {
                    Button(role: .destructive, action: delete) {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: -offset)
                    .foregroundStyle(Theme.base)
                    .background(Theme.warn)
                    .accessibilityLabel("Delete")
                }
            }
            content
                .background(Theme.card)
                .offset(x: offset)
                .overlay {
                    // While a button is showing, a tap on the row just closes it.
                    if settled != 0 {
                        Color.clear.contentShape(Rectangle()).offset(x: offset).onTapGesture { close() }
                    }
                }
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 1.4 else { return }
                    var x = settled + v.translation.width
                    if !canRepeat { x = min(0, x) }
                    offset = max(-full - 30, min(full + 30, x))
                }
                .onEnded { v in
                    let x = offset
                    if x <= -full { delete() }
                    else if x >= full && canRepeat { addAgain() }
                    else if x < -button / 2 { settle(-button) }
                    else if x > button / 2 && canRepeat { settle(button) }
                    else { close() }
                }
        )
        .sensoryFeedback(.success, trigger: done)
        .accessibilityAction(named: Text("Delete")) { delete() }
        .accessibilityAction(named: Text("Add again")) { if canRepeat { addAgain() } }
    }

    private func settle(_ x: CGFloat) {
        withAnimation(.snappy) { offset = x; settled = x }
    }

    private func close() { settle(0) }

    private func delete() {
        withAnimation(.snappy) { offset = -500 }
        DeleteUndo.shared.delete(expense, in: context)
        done += 1
    }

    private func addAgain() {
        context.insert(Expense(amountCents: expense.amountCents, category: expense.category, note: expense.note, date: .now))
        try? context.save()
        done += 1
        close()
    }
}

extension View {
    /// Swipe left to delete, right to add it again.
    func expenseSwipe(_ expense: Expense) -> some View { modifier(ExpenseSwipe(expense: expense)) }
}
