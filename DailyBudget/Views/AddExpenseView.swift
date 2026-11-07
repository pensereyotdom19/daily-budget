import SwiftUI
import SwiftData

/// Add a new expense or extra income, or edit one when `editing` / `editingIncome` is set.
/// Amounts can be typed in dollars or riel; riel is converted to dollars at your rate.
struct AddExpenseView: View {
    var editing: Expense? = nil
    var editingIncome: Income? = nil

    enum Kind { case spent, income }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var settingsList: [BudgetSettings]

    @AppStorage("currency.lastRiel") private var lastUsedRiel = false
    @AppStorage("currency.rielPerDollar") private var rielPerDollar = Money.defaultRielPerDollar

    @State private var kind: Kind = .spent
    @State private var inRiel = false
    @State private var amountText = ""
    @State private var category: Category = .food
    @State private var target: IncomeTarget = .living
    @State private var note = ""
    @State private var date = Date.now
    @State private var editingRate = false
    @State private var rateText = ""
    @FocusState private var amountFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private var isEditing: Bool { editing != nil || editingIncome != nil }

    private var amountCents: Int? {
        if inRiel {
            guard let riel = Money.parseRiel(amountText) else { return nil }
            let cents = Money.rielToCents(riel, rate: rielPerDollar)
            return cents > 0 ? cents : nil
        }
        return Money.parse(amountText)
    }

    private var calc: BudgetCalculator {
        BudgetCalculator(expenses: expenses, settings: settingsList.first, incomes: incomes)
    }

    private var leftToday: Int { calc.summary(on: date).leftCents }

    var body: some View {
        ZStack {
            GlowBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if !isEditing { kindPicker }
                    amountSection
                    if kind == .spent {
                        if editing == nil && !quickItems.isEmpty { quickFill }
                        categoryGrid
                    } else {
                        targetPicker
                    }
                    detailsCard
                    saveButton
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.ink)
        .onAppear(perform: load)
        .alert("Riel per dollar", isPresented: $editingRate) {
            TextField("4100", text: $rateText).keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let r = Money.parseRiel(rateText), r >= 1_000, r <= 10_000 { rielPerDollar = r }
            }
        } message: {
            Text("How many riel make one US dollar. Riel amounts are saved in dollars at this rate.")
        }
    }

    private func load() {
        if let e = editing {
            amountText = String(format: "%.2f", Double(e.amountCents) / 100)
            category = e.category
            note = e.note
            date = e.date
        } else if let i = editingIncome {
            kind = .income
            amountText = String(format: "%.2f", Double(i.amountCents) / 100)
            target = i.target
            note = i.note
            date = i.date
        } else {
            inRiel = lastUsedRiel
            amountFocused = true
        }
    }

    // MARK: - Header and kind

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .glassCard(radius: 22)
            }
            .accessibilityLabel("Close")
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var title: LocalizedStringKey {
        if editing != nil { return "Edit expense" }
        if editingIncome != nil { return "Edit income" }
        return kind == .spent ? "New expense" : "Extra money"
    }

    private var kindPicker: some View {
        HStack(spacing: 4) {
            kindButton(.spent, "I spent", "arrow.up.right")
            kindButton(.income, "I got money", "arrow.down.left")
        }
        .padding(4)
        .glassCard(radius: 24)
    }

    private func kindButton(_ k: Kind, _ label: LocalizedStringKey, _ symbol: String) -> some View {
        Button {
            withAnimation(.snappy) { kind = k }
        } label: {
            Label(label, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(kind == k ? Theme.ink.opacity(0.16) : .clear, in: Capsule())
                .foregroundStyle(kind == k ? Theme.ink : Theme.secondary)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(kind == k ? .isSelected : [])
    }

    // MARK: - Amount

    private var amountSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Button {
                    withAnimation(.snappy) { switchCurrency() }
                } label: {
                    Text(inRiel ? "៛" : "$")
                        .font(Theme.rounded(inRiel ? 34 : 40))
                        .foregroundStyle(Theme.secondary)
                        .frame(minWidth: 34)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(inRiel ? "Typing in riel. Switch to dollars" : "Typing in dollars. Switch to riel")
                TextField(inRiel ? "0" : "0.00", text: $amountText)
                    .keyboardType(inRiel ? .numberPad : .decimalPad)
                    .focused($amountFocused)
                    .font(Theme.rounded(64))
                    .multilineTextAlignment(.leading)
                    .fixedSize()
                    .accessibilityLabel(inRiel ? "Amount in riel" : "Amount in dollars")
            }
            if inRiel {
                Button { rateText = "\(rielPerDollar)"; editingRate = true } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: "= \(Money.format(amountCents ?? 0, alwaysShowCents: true))").font(Theme.rounded(16))
                        Text("at \(Money.formatRiel(rielPerDollar)) per $1").font(.caption).foregroundStyle(Theme.secondary)
                        Image(systemName: "pencil").font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Change the exchange rate")
            }
            effectPill
        }
        .padding(.vertical, 4)
    }

    /// Switching keeps the amount: $1.22 becomes ៛5,002 and back.
    private func switchCurrency() {
        let cents = amountCents
        inRiel.toggle()
        lastUsedRiel = inRiel
        guard let cents else { amountText = ""; return }
        amountText = inRiel ? "\(cents * rielPerDollar / 100)" : String(format: "%.2f", Double(cents) / 100)
    }

    @ViewBuilder private var effectPill: some View {
        if kind == .income {
            switch target {
            case .living:
                pill("Daily limit \(Money.format(calc.limitCents(on: date), alwaysShowCents: true)) → \(Money.format(limitAfterIncome, alwaysShowCents: true))", warn: false)
            case .savings:
                pill("Goes straight to emergency savings", warn: false)
            case .engagement:
                pill("Added to the Engagement money", warn: false)
            }
        } else if category.countsAsLiving, let limit = settingsList.first?.categoryLimits[category.rawValue] {
            let old = editing.map { $0.category == category ? $0.amountCents : 0 } ?? 0
            let spent = calc.spent(category: category.rawValue, inMonthOf: date) - old + (amountCents ?? 0)
            let after = leftToday - (amountCents ?? 0) + (editing.map { $0.category.countsAsLiving ? $0.amountCents : 0 } ?? 0)
            VStack(spacing: 6) {
                pill("\(Money.format(leftToday, alwaysShowCents: true)) left today → \(Money.format(after, alwaysShowCents: true)) after this", warn: after < 0)
                pill("\(category.title) this month: \(Money.format(spent, alwaysShowCents: true)) of \(Money.format(limit))", warn: spent > limit)
            }
        } else if category.countsAsLiving {
            let after = leftToday - (amountCents ?? 0) + (editing.map { $0.category.countsAsLiving ? $0.amountCents : 0 } ?? 0)
            pill("\(Money.format(leftToday, alwaysShowCents: true)) left today → \(Money.format(after, alwaysShowCents: true)) after this", warn: after < 0)
        } else {
            pill("Paid from the \(category.title.lowercased()) budget, not daily money", warn: false)
        }
    }

    /// Today's limit if this income goes to this month's living money.
    private var limitAfterIncome: Int {
        var after = calc
        let old = editingIncome.map { $0.target == .living ? $0.amountCents : 0 } ?? 0
        after.extraLivingByMonth[MonthKey.key(for: date), default: 0] += (amountCents ?? 0) - old
        return after.limitCents(on: date)
    }

    private func pill(_ text: LocalizedStringKey, warn: Bool) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(warn ? Theme.warn : Theme.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).frame(minHeight: 30)
            .glassCard(radius: 15)
    }

    // MARK: - Spent: quick fill and categories

    private var quickItems: [QuickAdd.Item] {
        QuickAdd.suggestions(from: expenses.filter { $0.billID == nil }
            .map { QuickAdd.Past(category: $0.category, note: $0.note, cents: $0.amountCents, date: $0.date) })
    }

    /// Tapping one fills in the form, so you can still change the amount before saving.
    private var quickFill: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OFTEN").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.leading, 4)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(quickItems) { item in
                        Button {
                            withAnimation(.snappy) {
                                inRiel = false
                                amountText = String(format: "%.2f", Double(item.cents) / 100)
                                category = item.category
                                note = item.note
                            }
                        } label: { QuickAddChip(item: item) }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Fill in \(item.title), \(Money.format(item.cents, alwaysShowCents: true))")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CATEGORY").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.leading, 4)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Category.allCases) { c in
                    let selected = c == category
                    Button {
                        withAnimation(.snappy) { category = c }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: c.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(c.color)
                            Text(c.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(Theme.ink.opacity(selected ? 0.16 : 0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(selected ? Theme.mint.opacity(0.8) : Theme.ink.opacity(0.1), lineWidth: selected ? 1.5 : 1))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .glassCard(radius: 28)
    }

    // MARK: - Income: where it goes

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE SHOULD IT GO?").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.leading, 4)
            VStack(spacing: 8) {
                ForEach(IncomeTarget.allCases) { t in
                    let selected = t == target
                    Button {
                        withAnimation(.snappy) { target = t }
                    } label: {
                        HStack(spacing: 12) {
                            IncomeIcon(target: t, size: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title).font(.subheadline.weight(.semibold))
                                Text(t.detail).font(.caption).foregroundStyle(Theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20)).foregroundStyle(selected ? Theme.mint : Theme.ink.opacity(0.4))
                        }
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .background(Theme.ink.opacity(selected ? 0.12 : 0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(selected ? Theme.mint.opacity(0.7) : Theme.ink.opacity(0.08)))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .glassCard(radius: 28)
    }

    // MARK: - Details and save

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Note").frame(width: 52, alignment: .leading)
                TextField(kind == .spent ? "e.g. Iced coffee" : "e.g. Gift from mom", text: $note)
                    .onChange(of: note) { _, new in
                        if new.count > Expense.maxNoteLength { note = String(new.prefix(Expense.maxNoteLength)) }
                    }
            }
            .frame(height: 50)
            Divider().overlay(Theme.ink.opacity(0.16))
            DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(86_400))
                .frame(height: 50)
        }
        .padding(.horizontal, 16)
        .glassCard(radius: 22)
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(saveTitle)
                .font(.headline)
                .foregroundStyle(Theme.base)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Theme.accentGradient, in: Capsule())
                .opacity(amountCents == nil ? 0.45 : 1)
        }
        .disabled(amountCents == nil)
        .padding(.top, 8)
    }

    private var saveTitle: LocalizedStringKey {
        if isEditing { return "Save changes" }
        return kind == .spent ? "Save expense" : "Save money"
    }

    private func save() {
        guard let cents = amountCents else { return }
        let trimmed = String(note.trimmingCharacters(in: .whitespaces).prefix(Expense.maxNoteLength))
        if let e = editing {
            e.amountCents = cents
            e.category = category
            e.note = trimmed
            e.date = date
        } else if let i = editingIncome {
            i.amountCents = cents
            i.target = target
            i.note = trimmed
            i.date = date
        } else if kind == .income {
            context.insert(Income(amountCents: cents, target: target, note: trimmed, date: date))
        } else {
            context.insert(Expense(amountCents: cents, category: category, note: trimmed, date: date))
        }
        try? context.save()
        dismiss()
    }
}

extension IncomeTarget {
    var title: String {
        switch self {
        case .living: return String(localized: "This month's everyday money", bundle: AppLanguage.bundle)
        case .savings: return String(localized: "Emergency savings", bundle: AppLanguage.bundle)
        case .engagement: return String(localized: "Engagement", bundle: AppLanguage.bundle)
        }
    }

    var detail: String {
        switch self {
        case .living: return String(localized: "Your daily limit goes up for the rest of the month.", bundle: AppLanguage.bundle)
        case .savings: return String(localized: "Kept safe. The daily limit doesn't change.", bundle: AppLanguage.bundle)
        case .engagement: return String(localized: "Adds to the money set aside for the engagement.", bundle: AppLanguage.bundle)
        }
    }

    var symbol: String {
        switch self {
        case .living: return "fork.knife"
        case .savings: return "banknote.fill"
        case .engagement: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .living: return Theme.mint
        case .savings: return Theme.sky
        case .engagement: return Category.engagement.color
        }
    }
}

/// Same glossy tile as CategoryIcon, for income.
struct IncomeIcon: View {
    let target: IncomeTarget
    var size: CGFloat = 38

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: target.symbol)
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(Theme.base.opacity(0.85))
            .frame(width: size, height: size)
            .background(shape.fill(LinearGradient(colors: [target.color, target.color.opacity(0.62)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(shape.strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
    }
}
