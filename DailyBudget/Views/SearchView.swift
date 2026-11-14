import SwiftUI
import SwiftData

struct SearchRoute: Hashable {}

/// Find expenses by note, category or amount, across every month.
struct SearchView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var query = ""
    @State private var editing: Expense?
    @FocusState private var focused: Bool

    private var results: [Expense] { ExpenseSearch.filter(expenses, query: query) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(caption: "All months", title: "Search")
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField("Coffee, Grab, 1.25…", text: $query)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 16).frame(height: 50)
                .glassCard(radius: 25)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Type a note, a category or an amount.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                } else if results.isEmpty {
                    Text("Nothing found for \"\(query)\".")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                } else {
                    let total = results.reduce(0) { $0 + $1.amountCents }
                    Text("\(results.count) found · \(Money.format(total, alwaysShowCents: true)) in total")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(results.prefix(200)) { e in
                            Button { editing = e } label: {
                                HStack(spacing: 12) {
                                    ExpenseIcon(expense: e, size: 40)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.note.isEmpty ? e.category.title : e.note).font(.subheadline.weight(.semibold))
                                        Text("\(e.category.title) · \(e.date.formatted(.dateTime.day().month(.abbreviated).year().locale(AppLanguage.locale)))")
                                            .font(.caption).foregroundStyle(Theme.secondary)
                                    }
                                    Spacer()
                                    Text(Money.format(e.amountCents, alwaysShowCents: true)).font(Theme.rounded(16))
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = e }
                                Button("Delete", systemImage: "trash", role: .destructive) { DeleteUndo.shared.delete(e, in: context) }
                            }
                            if e.id != results.prefix(200).last?.id { Divider().overlay(Theme.rule) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .glassCard()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(GlowBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { focused = true }
        .sheet(item: $editing) { e in AddExpenseView(editing: e).presentationBackground(Theme.base) }
    }
}
