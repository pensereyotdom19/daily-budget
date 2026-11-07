import SwiftUI
import SwiftData

struct RecurringRoute: Hashable {}

/// Expenses that repeat every month (not bills), added on their day automatically.
struct RecurringView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringExpense.dayOfMonth) private var items: [RecurringExpense]
    @State private var editing: RecurringExpense?
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(caption: "Every month", title: "Recurring")
                Text("Added for you on their day each month, like a phone top-up. They count like any other expense.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 4)
                if items.isEmpty {
                    Text("Nothing yet. Tap Add to create one.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16).glassCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { r in
                            Button { editing = r } label: { row(r) }
                                .buttonStyle(.pressable)
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = r }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        context.delete(r)
                                        try? context.save()
                                    }
                                }
                            if r.id != items.last?.id { Divider().overlay(Theme.ink.opacity(0.14)) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .glassCard()
                    Text("Tap to edit. Press and hold to delete. Expenses already added stay.")
                        .font(.caption).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                }
                Button { adding = true } label: {
                    Label("Add recurring expense", systemImage: "plus")
                        .font(.headline).foregroundStyle(Theme.base)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.accentGradient, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(GlowBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $editing) { r in RecurringEditor(item: r) }
        .sheet(isPresented: $adding) { RecurringEditor(item: nil) }
    }

    private func row(_ r: RecurringExpense) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(category: r.category, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.note.isEmpty ? r.category.title : r.note).font(.subheadline.weight(.semibold))
                Text(r.isActive ? "Every month on day \(r.dayOfMonth)" : "Paused")
                    .font(.caption).foregroundStyle(r.isActive ? Theme.secondary : Theme.warn)
            }
            Spacer()
            Text(Money.format(r.amountCents, alwaysShowCents: true)).font(Theme.rounded(16))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct RecurringEditor: View {
    let item: RecurringExpense?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var amountText = ""
    @State private var category: Category = .phone
    @State private var note = ""
    @State private var day = 1
    @State private var active = true
    @State private var addThisMonth = true

    private var today: Int { Calendar.current.component(.day, from: .now) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount") {
                        TextField("0.00", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Category", selection: $category) {
                        ForEach(Category.allCases.filter { $0 != .bills }) { c in
                            Label(c.title, systemImage: c.symbol).tag(c)
                        }
                    }
                    TextField("Note, e.g. Phone top-up", text: $note)
                }
                Section {
                    Stepper("Day \(day) of each month", value: $day, in: 1...31)
                    if item == nil && day <= today {
                        Toggle("Also add it for this month", isOn: $addThisMonth)
                    }
                    if item != nil { Toggle("Active", isOn: $active) }
                } footer: {
                    Text("In shorter months, days 29–31 use the last day.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlowBackground())
            .navigationTitle(item == nil ? "New recurring" : "Edit recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(Money.parse(amountText) == nil)
                }
            }
            .onAppear {
                guard let r = item else { return }
                amountText = String(format: "%.2f", Double(r.amountCents) / 100)
                category = r.category
                note = r.note
                day = r.dayOfMonth
                active = r.isActive
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard let cents = Money.parse(amountText) else { return }
        let trimmed = String(note.trimmingCharacters(in: .whitespaces).prefix(Expense.maxNoteLength))
        if let r = item {
            r.amountCents = cents
            r.category = category
            r.note = trimmed
            r.dayOfMonth = day
            r.isActive = active
        } else {
            let current = MonthKey.key(for: .now)
            let r = RecurringExpense(amountCents: cents, category: category, note: trimmed, dayOfMonth: day, startMonth: current)
            // Day already passed and you don't want it this month: start next month.
            if day <= today && !addThisMonth { r.lastAddedMonth = current }
            context.insert(r)
        }
        try? context.save()
        RecurringRunner.addDue(in: context)
        dismiss()
    }
}
