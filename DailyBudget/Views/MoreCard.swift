import SwiftUI

/// Recurring expenses, Face ID lock and riel rate (in Settings).
struct MoreCard: View {
    @Environment(AppLock.self) private var lock
    @AppStorage(AppLock.enabledKey) private var lockOn = false
    @AppStorage("currency.rielPerDollar") private var rielPerDollar = Money.defaultRielPerDollar
    @State private var editingRate = false
    @State private var rateText = ""
    @State private var lockFailed = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(value: RecurringRoute()) {
                row("repeat", Theme.violet, "Recurring expenses", "Added for you every month") {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                }
            }
            .buttonStyle(.pressable)
            divider
            row("faceid", Theme.mint, "Lock with \(AppLock.methodName)",
                lockFailed ? "Couldn't confirm it was you. Try again." : "Asks every time you open the app") {
                Toggle("", isOn: Binding(get: { lockOn }, set: setLock(_:)))
                    .labelsHidden().tint(Theme.teal)
            }
            divider
            Button { rateText = "\(rielPerDollar)"; editingRate = true } label: {
                row("dollarsign.arrow.circlepath", Theme.warn, "Riel rate", "\(Money.formatRiel(rielPerDollar)) = $1") {
                    Image(systemName: "pencil").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                }
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .glassCard(radius: 28)
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

    /// Turning the lock on or off asks for Face ID first, so nobody else can switch it.
    private func setLock(_ on: Bool) {
        Task {
            let ok = await AppLock.verify(reason: on ? String(localized: "Turn on the app lock", bundle: AppLanguage.bundle)
                                                      : String(localized: "Turn off the app lock", bundle: AppLanguage.bundle))
            lockFailed = !ok
            if ok { lockOn = on }
        }
    }

    private var divider: some View { Divider().overlay(Color.white.opacity(0.14)) }

    private func row<Trailing: View>(_ symbol: String, _ color: Color, _ title: LocalizedStringKey, _ detail: LocalizedStringKey,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
