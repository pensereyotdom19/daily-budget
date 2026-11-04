import SwiftUI
import SwiftData

struct CategoryLimitsRoute: Hashable {}

/// A monthly limit for any everyday category, e.g. Coffee $15. Today warns at 80% and when you go over.
struct CategoryLimitsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [BudgetSettings]
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @State private var editing: Category?
    @State private var text = ""

    private var settings: BudgetSettings? { settingsList.first }
    private var limits: [String: Int] { settings?.categoryLimits ?? [:] }
    private var calc: BudgetCalculator { BudgetCalculator(expenses: expenses, settings: settings, incomes: incomes) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(caption: "Every month", title: "Category limits")
                Text("Set a monthly limit for a category. Today warns you at 80% and when you go over. Leave it empty for no limit.")
                    .font(.footnote).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Category.allCases.filter(\.countsAsLiving)) { c in
                        Button { text = limits[c.rawValue].map { String(format: "%.2f", Double($0) / 100) } ?? ""; editing = c } label: {
                            row(c)
                        }
                        .buttonStyle(.pressable)
                        if c != Category.allCases.filter(\.countsAsLiving).last { Divider().overlay(Color.white.opacity(0.14)) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .glassCard()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(GlowBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert(editing?.title ?? "", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("No limit", text: $text).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { editing = nil }
            Button("Remove limit", role: .destructive) { save(nil) }
            Button("Save") { save(Money.parse(text)) }
        } message: {
            Text("Monthly limit in dollars")
        }
    }

    private func row(_ c: Category) -> some View {
        let limit = limits[c.rawValue]
        let spent = calc.spent(category: c.rawValue, inMonthOf: .now)
        return HStack(spacing: 12) {
            CategoryIcon(category: c, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title).font(.subheadline.weight(.semibold))
                Text("\(Money.format(spent, alwaysShowCents: true)) this month")
                    .font(.caption).foregroundStyle(limit.map { spent > $0 ? Theme.warn : Theme.secondary } ?? Theme.secondary)
            }
            Spacer()
            if let limit {
                Text(Money.format(limit, alwaysShowCents: true)).font(Theme.rounded(16))
            } else {
                Text("No limit").font(.footnote).foregroundStyle(Theme.secondary)
            }
            Image(systemName: "pencil").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func save(_ cents: Int?) {
        guard let c = editing, let s = settings else { return }
        var l = s.categoryLimits
        l[c.rawValue] = (cents ?? 0) > 0 ? cents : nil
        s.categoryLimits = l
        try? context.save()
        editing = nil
    }
}
