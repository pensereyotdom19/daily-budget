import SwiftUI
import SwiftData

struct SubscriptionsRoute: Hashable {}

/// On the Plan screen: what subscriptions cost per month and which renews next.
struct SubscriptionsCard: View {
    @Query(sort: \Subscription.nextRenewal) private var subscriptions: [Subscription]

    private var active: [Subscription] { subscriptions.filter(\.isActive) }

    var body: some View {
        NavigationLink(value: SubscriptionsRoute()) {
            HStack(spacing: 12) {
                if let next = active.first {
                    ServiceIcon(name: next.name, size: 38)
                } else {
                    Image(systemName: "repeat.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.sky)
                        .frame(width: 38, height: 38)
                        .background(Theme.sky.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Subscriptions").font(.subheadline.weight(.semibold))
                    if let next = active.first {
                        Text("Next: \(next.name) \(Money.format(next.amountCents, alwaysShowCents: true)) · \(next.nextRenewal.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.locale)))")
                            .font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                    } else {
                        Text("YouTube, ChatGPT, iCloud… add yours").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer(minLength: 4)
                if !active.isEmpty {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Money.format(active.reduce(0) { $0 + $1.monthlyCents }, alwaysShowCents: true)).font(Theme.rounded(16))
                        Text("per month").font(.caption2).foregroundStyle(Theme.secondary)
                    }
                }
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
            }
            .padding(14)
            .glassCard(radius: 22)
        }
        .buttonStyle(.pressable)
    }
}

/// All subscriptions, the monthly total, and add / edit / stop.
struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subscription.nextRenewal) private var subscriptions: [Subscription]
    @State private var editing: Subscription?
    /// For screenshots during development: launch with `-openSubscriptions YES -addSubscription YES`.
    @State private var adding = UserDefaults.standard.bool(forKey: "addSubscription")

    private var active: [Subscription] { subscriptions.filter(\.isActive) }
    private var stopped: [Subscription] { subscriptions.filter { !$0.isActive } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(caption: "Paid like bills", title: "Subscriptions")
                totalCard
                if !active.isEmpty { list(active) }
                if !stopped.isEmpty {
                    Text("Stopped").font(.title3.weight(.bold)).padding(.horizontal, 4).padding(.top, 4)
                    list(stopped)
                }
                Text("On each renewal date the payment is added as a Bills expense, so it doesn't lower your daily limit. Tap one to edit. Press and hold to delete.")
                    .font(.caption).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
                Button { adding = true } label: {
                    Label("Add subscription", systemImage: "plus")
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
        .sheet(item: $editing) { s in SubscriptionEditor(item: s) }
        .sheet(isPresented: $adding) { SubscriptionEditor(item: nil) }
    }

    private var totalCard: some View {
        let monthly = active.reduce(0) { $0 + $1.monthlyCents }
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EVERY MONTH").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                Text(Money.format(monthly, alwaysShowCents: true)).font(Theme.rounded(34))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("EVERY YEAR").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                Text(Money.format(active.reduce(0) { $0 + ($1.cycle == .monthly ? $1.amountCents * 12 : $1.amountCents) }, alwaysShowCents: true))
                    .font(Theme.rounded(20))
            }
        }
        .padding(18)
        .glassCard(radius: 26)
    }

    private func list(_ items: [Subscription]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { s in
                Button { editing = s } label: { row(s) }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = s }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            context.delete(s)
                            try? context.save()
                        }
                    }
                if s.id != items.last?.id { Divider().overlay(Color.white.opacity(0.14)) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .glassCard()
    }

    private func row(_ s: Subscription) -> some View {
        HStack(spacing: 12) {
            ServiceIcon(name: s.name, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.subheadline.weight(.semibold))
                Text(s.isActive
                     ? "\(s.cycle.title) · renews \(s.nextRenewal.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(AppLanguage.locale)))"
                     : "Stopped")
                    .font(.caption).foregroundStyle(s.isActive ? Theme.secondary : Theme.warn)
            }
            Spacer()
            Text(Money.format(s.amountCents, alwaysShowCents: true)).font(Theme.rounded(16))
                .foregroundStyle(s.isActive ? .white : Theme.secondary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

extension SubscriptionCycle {
    var title: String {
        switch self {
        case .monthly: return String(localized: "Monthly", bundle: AppLanguage.bundle)
        case .yearly: return String(localized: "Yearly", bundle: AppLanguage.bundle)
        }
    }
}

struct SubscriptionEditor: View {
    let item: Subscription?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var amountText = ""
    @State private var cycle: SubscriptionCycle = .monthly
    @State private var renewal = Date.now
    @State private var active = true

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Money.parse(amountText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if item == nil {
                    Section {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                            ForEach(ServiceBrand.all) { brand in
                                Button {
                                    withAnimation(.snappy) { name = brand.name }
                                } label: {
                                    VStack(spacing: 5) {
                                        BrandTile(brand: brand, size: 44)
                                        Text(verbatim: brand.shortName).font(.caption2).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.pressable)
                                .accessibilityLabel(Text(verbatim: brand.name))
                            }
                        }
                        .padding(.vertical, 6)
                    } header: { Text("Popular") }
                }
                Section {
                    HStack(spacing: 12) {
                        ServiceIcon(name: name, size: 34)
                            .animation(.snappy, value: ServiceBrand.match(name)?.id)
                        TextField("Name, e.g. YouTube", text: $name)
                            .onChange(of: name) { _, new in if new.count > 60 { name = String(new.prefix(60)) } }
                    }
                    LabeledContent("Price") {
                        TextField("0.00", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Every", selection: $cycle) {
                        Text("Month").tag(SubscriptionCycle.monthly)
                        Text("Year").tag(SubscriptionCycle.yearly)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    DatePicker("Next renewal", selection: $renewal, displayedComponents: .date)
                    if item != nil { Toggle("Active", isOn: $active) }
                } footer: {
                    Text("The payment is added as a Bills expense on this date, then the date moves to the next month or year. Turn Active off when you cancel.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlowBackground())
            .navigationTitle(item == nil ? "New subscription" : "Edit subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .onAppear {
                guard let s = item else { return }
                name = s.name
                amountText = String(format: "%.2f", Double(s.amountCents) / 100)
                cycle = s.cycle
                renewal = s.nextRenewal
                active = s.isActive
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard let cents = Money.parse(amountText) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Renew at 9 AM on the chosen day.
        let date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: renewal) ?? renewal
        if let s = item {
            s.name = trimmed
            s.amountCents = cents
            s.cycle = cycle
            if !Calendar.current.isDate(s.nextRenewal, inSameDayAs: date) {
                s.nextRenewal = date
                s.anchorDay = Calendar.current.component(.day, from: date)
            }
            s.isActive = active
        } else {
            context.insert(Subscription(name: trimmed, amountCents: cents, cycle: cycle, nextRenewal: date))
        }
        try? context.save()
        SubscriptionRunner.addDue(in: context)
        dismiss()
    }
}
