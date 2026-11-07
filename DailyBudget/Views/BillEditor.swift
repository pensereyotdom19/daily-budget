import SwiftUI
import SwiftData

/// Edit a bill's amount and the day it is paid automatically.
struct BillEditor: View {
    let bill: Bill
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var amountText = ""
    @State private var dueDay = 0  // 0 = tick it by hand

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount") {
                        TextField("0.00", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } header: { Text(verbatim: bill.name) }

                Section {
                    Picker("Paid automatically", selection: $dueDay) {
                        Text("Off, I tick it").tag(0)
                        ForEach(1...31, id: \.self) { d in
                            Text("On the \(BillSchedule.ordinal(d))").tag(d)
                        }
                    }
                } footer: {
                    Text(dueDay == 0
                         ? "You mark it paid yourself on the Plan screen."
                         : "On this day of each month it's due, the bill is marked paid and added as a Bills expense. Days 29–31 use the last day in shorter months. You can still untick it.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlowBackground())
            .navigationTitle("Edit bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let cents = Money.parse(amountText) { bill.amountCents = cents }
                        BillAutoPay.setDueDay(dueDay == 0 ? nil : dueDay, for: bill, in: context)
                        dismiss()
                    }
                    .disabled(Money.parse(amountText) == nil)
                }
            }
            .onAppear {
                amountText = String(format: "%.2f", Double(bill.amountCents) / 100)
                dueDay = bill.dueDay ?? 0
            }
        }
        .presentationDetents([.medium, .large])
    }
}
