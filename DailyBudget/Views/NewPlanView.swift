import SwiftUI
import SwiftData

/// Starts a new plan after the current one: dates, money and bills.
/// History, savings and old bill payments are kept.
struct NewPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [BudgetSettings]
    @Query(sort: \Bill.sortOrder) private var existingBills: [Bill]
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]

    struct DraftBill: Identifiable {
        var id = UUID()
        var existing: Bill?
        var name: String
        var amountText: String
        var frequency: BillFrequency
        var onceIndex = 0
        var cents: Int? { Money.parse(amountText) ?? (amountText == "0" ? 0 : nil) }
    }

    @State private var startMonth = ""
    @State private var monthCount = 6
    @State private var totalText = ""
    @State private var livingText = ""
    @State private var engagementText = ""
    @State private var bills: [DraftBill] = []
    @State private var confirming = false
    @State private var loaded = false

    private var settings: BudgetSettings? { settingsList.first }
    private var months: [String] { MonthKey.range(start: startMonth, count: monthCount) }
    private var startOptions: [String] { MonthKey.range(start: MonthKey.key(for: .now), count: 13) }

    private var planned: Int {
        PlanMath.plannedTotal(livingMonthlyCents: Money.parse(livingText) ?? 0, monthCount: monthCount,
                              engagementCents: Money.parse(engagementText) ?? 0,
                              bills: bills.map { (cents: $0.cents ?? 0,
                                                  dueCount: $0.frequency.dueMonths(in: months, onceIndex: $0.onceIndex).count) })
    }

    private var isValid: Bool {
        !startMonth.isEmpty && Money.parse(totalText) != nil && Money.parse(livingText) != nil
            && bills.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.cents != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Starts", selection: $startMonth) {
                        ForEach(startOptions, id: \.self) { m in Text(monthYear(m)).tag(m) }
                    }
                    Stepper("Lasts \(monthCount) months", value: $monthCount, in: 1...24)
                    if let last = months.last {
                        LabeledContent("Ends", value: monthYear(last))
                    }
                } header: { Text("Dates") }

                Section {
                    money("Total money", $totalText)
                    money("Living money per month", $livingText)
                    money("Engagement money (total)", $engagementText)
                } header: { Text("Money") } footer: {
                    Text("Living money is what the daily limit is made from. Engagement is the total for the engagement, including what earlier plans set aside.")
                }

                Section {
                    ForEach($bills) { $bill in billRow($bill) }
                        .onDelete { bills.remove(atOffsets: $0) }
                    Button {
                        bills.append(DraftBill(name: "", amountText: "", frequency: .monthly))
                    } label: { Label("Add a bill", systemImage: "plus.circle.fill") }
                } header: { Text("Bills") } footer: {
                    Text("Monthly bills carry over from your current plan. Swipe left to remove one.")
                }

                Section {
                    LabeledContent("Planned", value: Money.format(planned))
                    if let total = Money.parse(totalText) {
                        let left = total - planned
                        LabeledContent(left >= 0 ? "Not planned yet" : "Over your total",
                                       value: Money.format(abs(left)))
                            .foregroundStyle(left >= 0 ? Theme.mint : Theme.warn)
                    }
                } header: { Text("Check") }
            }
            .scrollContentBackground(.hidden)
            .background(GlowBackground())
            .navigationTitle("New plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { confirming = true }.disabled(!isValid)
                }
            }
            .confirmationDialog("Start the new plan?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Start \(monthYear(startMonth)) plan") { create() }
            } message: {
                Text("Your history, savings and paid bills stay. The daily limit uses the new living money from \(monthYear(startMonth)).")
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.light)
    }

    private func money(_ label: LocalizedStringKey, _ text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    private func billRow(_ bill: Binding<DraftBill>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Bill name", text: bill.name)
                    .onChange(of: bill.wrappedValue.name) { _, new in
                        if new.count > 60 { bill.wrappedValue.name = String(new.prefix(60)) }
                    }
                TextField("0", text: bill.amountText)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            }
            Picker("Due", selection: bill.frequency) {
                Text("Every month").tag(BillFrequency.monthly)
                Text("Every 3 months").tag(BillFrequency.every3Months)
                Text("Once").tag(BillFrequency.once)
            }
            .pickerStyle(.segmented)
            if bill.wrappedValue.frequency == .once {
                Picker("Month", selection: bill.onceIndex) {
                    ForEach(months.indices, id: \.self) { i in Text(monthYear(months[i])).tag(i) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func monthYear(_ key: String) -> String {
        MonthKey.firstDay(of: key)?.formatted(.dateTime.month(.wide).year().locale(AppLanguage.locale)) ?? key
    }

    private func load() {
        guard !loaded, let s = settings else { return }
        loaded = true
        startMonth = PlanMath.suggestedStart(currentPlanMonths: s.planMonths, today: .now)
        monthCount = s.monthCount
        totalText = String(format: "%.2f", Double(s.totalCents) / 100)
        livingText = String(format: "%.2f", Double(s.livingMonthlyCents) / 100)
        engagementText = String(format: "%.2f", Double(s.engagementCents) / 100)
        bills = existingBills.compactMap { b in
            guard let f = BillFrequency.guess(dueMonths: b.dueMonths, planMonths: s.planMonths) else { return nil }
            return DraftBill(existing: b, name: b.name, amountText: String(format: "%.2f", Double(b.amountCents) / 100), frequency: f)
        }
    }

    private func create() {
        guard let s = settings else { return }
        // Savings so far, counting every month of the old plan before the new one starts as finished.
        let calc = BudgetCalculator(expenses: expenses, settings: s, incomes: incomes)
        let startDate = MonthKey.firstDay(of: startMonth) ?? .now
        s.savedBeforeCents = s.savingsCents(calc, incomes: incomes, today: startDate)
        s.historyStartMonth = min(s.historyStartMonth ?? s.startMonth, s.startMonth)

        s.startMonth = startMonth
        s.monthCount = monthCount
        s.totalCents = Money.parse(totalText) ?? s.totalCents
        s.livingMonthlyCents = Money.parse(livingText) ?? s.livingMonthlyCents
        s.engagementCents = Money.parse(engagementText) ?? s.engagementCents

        let order = (existingBills.map(\.sortOrder).max() ?? 0) + 1
        for (i, draft) in bills.enumerated() {
            let due = draft.frequency.dueMonths(in: months, onceIndex: draft.onceIndex)
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            if let b = draft.existing {
                // Same bill continues: old months keep their history, new months are added.
                b.dueMonths = Array(Set(b.dueMonths).union(due)).sorted()
                b.name = name
                b.amountCents = draft.cents ?? b.amountCents
            } else {
                context.insert(Bill(name: name, amountCents: draft.cents ?? 0, dueMonths: due, sortOrder: order + i))
            }
        }
        try? context.save()
        AppRefresh.run(context: context)
        dismiss()
    }
}
