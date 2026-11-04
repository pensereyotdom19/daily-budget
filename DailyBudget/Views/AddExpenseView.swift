import SwiftUI
import SwiftData

/// Add a new expense, or edit an existing one when `editing` is set.
struct AddExpenseView: View {
    var editing: Expense? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var expenses: [Expense]
    @Query private var settingsList: [BudgetSettings]

    @State private var amountText = ""
    @State private var category: Category = .food
    @State private var note = ""
    @State private var date = Date.now
    @FocusState private var amountFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var amountCents: Int? { Money.parse(amountText) }

    private var leftToday: Int {
        BudgetCalculator(expenses: expenses, settings: settingsList.first).summary(on: date).leftCents
    }

    var body: some View {
        ZStack {
            GlowBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    amountSection
                    categoryGrid
                    detailsCard
                    saveButton
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(.white)
        .onAppear {
            if let e = editing {
                amountText = String(format: "%.2f", Double(e.amountCents) / 100)
                category = e.category
                note = e.note
                date = e.date
            } else {
                amountFocused = true
            }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44)
                    .glassCard(radius: 22)
            }
            .accessibilityLabel("Close")
            Spacer()
            Text(editing == nil ? "New expense" : "Edit expense").font(.headline)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var amountSection: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("$").font(Theme.rounded(40)).foregroundStyle(Theme.secondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(Theme.rounded(64))
                    .multilineTextAlignment(.leading)
                    .fixedSize()
                    .accessibilityLabel("Amount in dollars")
            }
            if category.countsAsLiving {
                let after = leftToday - (amountCents ?? 0) + (editing.map { $0.category.countsAsLiving ? $0.amountCents : 0 } ?? 0)
                Text("\(Money.format(leftToday, alwaysShowCents: true)) left today → \(Money.format(after, alwaysShowCents: true)) after this")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(after < 0 ? Theme.warn : .white)
                    .padding(.horizontal, 12).frame(height: 30)
                    .glassCard(radius: 15)
            } else {
                Text("Paid from the \(category.title.lowercased()) budget, not daily money")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).frame(height: 30)
                    .glassCard(radius: 15)
            }
        }
        .padding(.vertical, 4)
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
                        .background(Color.white.opacity(selected ? 0.16 : 0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(selected ? Theme.mint.opacity(0.8) : Color.white.opacity(0.1), lineWidth: selected ? 1.5 : 1))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .glassCard(radius: 28)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Note").frame(width: 52, alignment: .leading)
                TextField("e.g. Iced coffee", text: $note)
            }
            .frame(height: 50)
            Divider().overlay(Color.white.opacity(0.16))
            DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(86_400))
                .frame(height: 50)
        }
        .padding(.horizontal, 16)
        .glassCard(radius: 22)
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(editing == nil ? "Save expense" : "Save changes")
                .font(.headline)
                .foregroundStyle(Theme.base)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Theme.accentGradient, in: Capsule())
                .opacity(amountCents == nil ? 0.45 : 1)
        }
        .disabled(amountCents == nil)
        .padding(.top, 8)
    }

    private func save() {
        guard let cents = amountCents else { return }
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        if let e = editing {
            e.amountCents = cents
            e.category = category
            e.note = trimmed
            e.date = date
        } else {
            context.insert(Expense(amountCents: cents, category: category, note: trimmed, date: date))
        }
        try? context.save()
        dismiss()
    }
}
