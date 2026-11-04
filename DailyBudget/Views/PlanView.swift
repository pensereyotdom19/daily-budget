import SwiftUI
import SwiftData

struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bill.sortOrder) private var bills: [Bill]
    @Query private var incomes: [Income]
    @Query private var settingsList: [BudgetSettings]
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @State private var editingBill: Bill?
    @State private var editingSettings = false
    @State private var startingNewPlan = false
    /// For screenshots during development: launch with `-openAccount YES` to open Backup & sync.
    @State private var path: NavigationPath = {
        var p = NavigationPath()
        if UserDefaults.standard.bool(forKey: "openAccount") { p.append(AccountRoute()) }
        return p
    }()

    private var settings: BudgetSettings? { settingsList.first }
    private var months: [String] { settings?.planMonths ?? [] }
    private var currentMonth: String { MonthKey.key(for: .now) }

    private var billsTotal: Int {
        let planMonths = months
        return bills.reduce(0) { sum, bill in
            sum + bill.amountCents * bill.dueMonths.filter { planMonths.contains($0) }.count
        }
    }
    private var creditCardTotal: Int {
        bills.filter { $0.dueMonths.count == 1 }.reduce(0) { $0 + $1.amountCents }
    }
    private var regularBillsTotal: Int { billsTotal - creditCardTotal }
    private var livingTotal: Int { (settings?.livingMonthlyCents ?? 0) * months.count }
    private var engagement: Int { settings?.engagementCents ?? 0 }
    private var total: Int { settings?.totalCents ?? 0 }
    private var unplanned: Int { total - billsTotal - livingTotal - engagement }

    private var savings: Int {
        settings?.savingsCents(BudgetCalculator(expenses: expenses, settings: settings, incomes: incomes),
                               incomes: incomes) ?? 0
    }

    var body: some View {
        NavigationStack(path: $path) {
        ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .bottom) {
                    ScreenHeader(caption: rangeCaption, title: "6-month plan")
                    HStack(spacing: 4) {
                        Button { editingSettings = true } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 40, height: 40)
                        }
                        .accessibilityLabel("Edit plan amounts")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .padding(2)
                    .glassCard(radius: 22)
                }

                totalCard
                planCard
                thisMonthBills
                monthByMonth

                Text("Engagement \(Money.format(engagement)) is set aside on day 1 and kept out of daily spending.")
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0xFFE1EC))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(hex: 0xFF9BC0).opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(hex: 0xFF9BC0).opacity(0.4)))
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(GlowBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: MonthRoute.self) { route in
            MonthDetailView(route: route)
        }
        .navigationDestination(for: SavingsRoute.self) { _ in SavingsView() }
        .navigationDestination(for: PlanSummaryRoute.self) { _ in PlanSummaryView() }
        .sheet(isPresented: $startingNewPlan) { NewPlanView() }
        .sheet(item: $editingBill) { bill in
            AmountEditor(title: bill.name, cents: bill.amountCents) { bill.amountCents = $0 }
        }
        .sheet(isPresented: $editingSettings) {
            if let s = settings { SettingsEditor(settings: s) }
        }
        }
    }

    private var rangeCaption: String {
        guard let first = months.first, let last = months.last,
              let a = MonthKey.firstDay(of: first), let b = MonthKey.firstDay(of: last) else { return "" }
        return "\(a.formatted(.dateTime.month(.abbreviated).year().locale(AppLanguage.locale))) – \(b.formatted(.dateTime.month(.abbreviated).year().locale(AppLanguage.locale)))"
    }

    private var totalCard: some View {
        let parts: [PlanPart] = [
            PlanPart(name: String(localized: "Bills", bundle: AppLanguage.bundle), cents: regularBillsTotal, color: Color(hex: 0xB6A4FF)),
            PlanPart(name: String(localized: "Engagement", bundle: AppLanguage.bundle), cents: engagement, color: Color(hex: 0xFF9BC0)),
            PlanPart(name: String(localized: "Credit card", bundle: AppLanguage.bundle), cents: creditCardTotal, color: Color(hex: 0xFFC27A)),
            PlanPart(name: String(localized: "Living", bundle: AppLanguage.bundle), cents: livingTotal, color: Theme.mint),
        ]
        let denominator = Double(max(total, 1))
        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Total money").font(.subheadline.weight(.semibold))
                Spacer()
                Text(Money.format(total)).font(Theme.rounded(28))
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts) { part in
                        Rectangle().fill(part.color)
                            .frame(width: max(0, geo.size.width * CGFloat(Double(part.cents) / denominator) - 2))
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                ForEach(parts) { part in
                    HStack(spacing: 7) {
                        Circle().fill(part.color).frame(width: 10, height: 10)
                        Text("\(part.name) \(Money.format(part.cents))").font(.footnote)
                    }
                }
            }
            NavigationLink(value: SavingsRoute()) {
                HStack {
                    Text("Emergency savings").font(.footnote).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(Money.format(savings, alwaysShowCents: true)).font(Theme.rounded(15))
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Shows your savings")
            if unplanned != 0 {
                Text(unplanned > 0 ? "\(Money.format(unplanned)) not planned yet" : "Plan is \(Money.format(-unplanned)) over your total")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(unplanned > 0 ? Theme.mint : Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .glassCard(radius: 28)
    }

    /// Summary and new plan. Highlighted in the plan's last month and after it ends.
    private var planCard: some View {
        let ended = BudgetCalculator.planHasEnded(planMonths: months, today: .now)
        let lastMonth = months.last == currentMonth
        return VStack(alignment: .leading, spacing: 12) {
            if ended || lastMonth {
                HStack(spacing: 10) {
                    Image(systemName: ended ? "flag.checkered" : "hourglass")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.warn)
                    Text(ended ? "Your plan has ended. Start a new one to keep your daily limit going."
                               : "This is the last month of your plan. Set up the next one when you're ready.")
                        .font(.footnote.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                NavigationLink(value: PlanSummaryRoute()) {
                    Label("Summary", systemImage: "chart.pie.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.pressable)
                Button { startingNewPlan = true } label: {
                    Label("New plan", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ended || lastMonth ? Theme.base : .white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if ended || lastMonth { Capsule().fill(Theme.accentGradient) }
                            else { Capsule().fill(Color.white.opacity(0.1)) }
                        }
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(14)
        .glassCard(radius: 24)
    }

    private var thisMonthBills: some View {
        let due = bills.filter { $0.isDue(in: currentMonth) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Bills this month").font(.title3.weight(.bold)).padding(.horizontal, 4)
            VStack(spacing: 0) {
                if due.isEmpty {
                    Text("No bills due this month.").font(.subheadline).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                }
                ForEach(due) { bill in
                    let paid = bill.isPaid(in: currentMonth)
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.snappy) { BillPayments.toggle(bill: bill, month: currentMonth, in: context) }
                        } label: {
                            Image(systemName: paid ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(paid ? Theme.mint : .white.opacity(0.5))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(paid ? "Mark \(bill.name) unpaid" : "Mark \(bill.name) paid")
                        Button { editingBill = bill } label: {
                            HStack {
                                Text(bill.name).font(.subheadline.weight(.semibold))
                                    .strikethrough(paid, color: .white.opacity(0.6))
                                Spacer()
                                Text(Money.format(bill.amountCents)).font(Theme.rounded(16))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                    }
                    if bill.id != due.last?.id { Divider().overlay(Color.white.opacity(0.14)) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 2)
            .glassCard()
        }
    }

    private var monthByMonth: some View {
        let spent = Dictionary(uniqueKeysWithValues:
            BudgetCalculator(expenses: expenses, settings: settings, incomes: incomes)
                .monthlySpending(months: months).map { ($0.monthKey, $0.totalCents) })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Month by month").font(.title3.weight(.bold)).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(months, id: \.self) { month in
                    let due = bills.filter { $0.isDue(in: month) }
                    let living = settings?.livingMonthlyCents ?? 0
                    let sum = due.reduce(living) { $0 + $1.amountCents }
                    let isBig = due.contains { $0.dueMonths.count == 1 }
                    let spentHere = spent[month] ?? 0
                    NavigationLink(value: MonthRoute(monthKey: month)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(MonthKey.title(of: month)).font(.subheadline.weight(.semibold))
                                if month == currentMonth {
                                    Text("NOW").font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Theme.mint.opacity(0.25), in: Capsule())
                                }
                            }
                            Text(breakdown(due: due, living: living))
                                .font(.caption).foregroundStyle(Theme.secondary).lineLimit(2)
                            if month <= currentMonth {
                                Text("Spent \(Money.format(spentHere, alwaysShowCents: true))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(spentHere > sum ? Theme.warn : Theme.mint)
                            }
                        }
                        Spacer()
                        Text(Money.format(sum)).font(Theme.rounded(16))
                            .foregroundStyle(isBig ? Theme.warn : .white)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Opens \(MonthKey.title(of: month))")
                    if month != months.last { Divider().overlay(Color.white.opacity(0.14)) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
            .glassCard()
        }
    }

    /// e.g. "Bills $323 + water $5 + living $92"
    private func breakdown(due: [Bill], living: Int) -> String {
        let monthly = due.filter { $0.dueMonths.count == months.count }.reduce(0) { $0 + $1.amountCents }
        var parts: [String] = []
        if monthly > 0 { parts.append(String(localized: "Bills \(Money.format(monthly))", bundle: AppLanguage.bundle)) }
        for b in due where b.dueMonths.count != months.count {
            parts.append("\(b.name.lowercased()) \(Money.format(b.amountCents))")
        }
        parts.append(String(localized: "living \(Money.format(living))", bundle: AppLanguage.bundle))
        return parts.joined(separator: " + ")
    }
}

private struct PlanPart: Identifiable {
    let name: String
    let cents: Int
    let color: Color
    var id: String { name }
}

/// Simple sheet to change one dollar amount.
struct AmountEditor: View {
    let title: String
    let cents: Int
    var onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(title) {
                    TextField("Amount", text: $text).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Edit amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let c = Money.parse(text) { onSave(c) }
                        dismiss()
                    }
                    .disabled(Money.parse(text) == nil)
                }
            }
            .onAppear { text = String(format: "%.2f", Double(cents) / 100) }
        }
        .presentationDetents([.medium])
    }
}

/// Edit the plan's total, monthly living money and engagement amount.
struct SettingsEditor: View {
    @Bindable var settings: BudgetSettings
    @Environment(\.dismiss) private var dismiss
    @State private var total = ""
    @State private var living = ""
    @State private var engagement = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Total money for the plan") { TextField("Total", text: $total).keyboardType(.decimalPad) }
                Section("Living money per month") { TextField("Living", text: $living).keyboardType(.decimalPad) }
                Section("Engagement (set aside)") { TextField("Engagement", text: $engagement).keyboardType(.decimalPad) }
            }
            .navigationTitle("Plan amounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = Money.parse(total) { settings.totalCents = v }
                        if let v = Money.parse(living) { settings.livingMonthlyCents = v }
                        if let v = Money.parse(engagement) { settings.engagementCents = v }
                        dismiss()
                    }
                }
            }
            .onAppear {
                total = String(format: "%.2f", Double(settings.totalCents) / 100)
                living = String(format: "%.2f", Double(settings.livingMonthlyCents) / 100)
                engagement = String(format: "%.2f", Double(settings.engagementCents) / 100)
            }
        }
    }
}

enum CSVExport {
    /// A note starting with = + - @ (or a tab) would run as a formula in Excel or Sheets,
    /// e.g. =HYPERLINK(...). A leading apostrophe makes the spreadsheet show it as plain text.
    static func safeCell(_ text: String) -> String {
        guard let first = text.first, "=+-@\t\r".contains(first) else { return text }
        return "'" + text
    }

    static func make(expenses: [Expense]) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        var lines = ["date,category,amount,note"]
        for e in expenses {
            let note = safeCell(e.note).replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\(f.string(from: e.date)),\(e.category.title),\(String(format: "%.2f", Double(e.amountCents) / 100)),\"\(note)\"")
        }
        return lines.joined(separator: "\n")
    }
}
