import SwiftUI
import SwiftData

/// Switches for the three reminders, shown on the Plan screen.
struct RemindersCard: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage(ReminderPrefs.eveningOn) private var eveningOn = false
    @AppStorage(ReminderPrefs.eveningMinutes) private var eveningMinutes = 20 * 60
    @AppStorage(ReminderPrefs.morningOn) private var morningOn = false
    @AppStorage(ReminderPrefs.morningMinutes) private var morningMinutes = 8 * 60
    @AppStorage(ReminderPrefs.billsOn) private var billsOn = false
    @AppStorage(ReminderPrefs.weeklyOn) private var weeklyOn = false
    @AppStorage(ReminderPrefs.expiryOn) private var expiryOn = false
    @AppStorage(ReminderPrefs.subscriptionsOn) private var subscriptionsOn = false
    @AppStorage(ReminderPrefs.recapOn) private var recapOn = false
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(symbol: "moon.stars.fill", color: Color(hex: 0x4B3F8F), title: "Log my spending",
                detail: "Every evening. Skipped if you already added something.",
                isOn: $eveningOn, minutes: $eveningMinutes)
            divider
            row(symbol: "sun.max.fill", color: Color(hex: 0xA0660C), title: "Today's limit",
                detail: "Every morning: how much you can spend today.",
                isOn: $morningOn, minutes: $morningMinutes)
            divider
            row(symbol: "doc.text.fill", color: Category.bills.color, title: "Bills",
                detail: "9 AM on the 1st, and on the 25th if still not paid.",
                isOn: $billsOn, minutes: nil)
            divider
            row(symbol: "repeat.circle.fill", color: Theme.mint, title: "Subscriptions",
                detail: "Two days before each renewal, so you can cancel in time.",
                isOn: $subscriptionsOn, minutes: nil)
            divider
            row(symbol: "book.closed.fill", color: Theme.violet, title: "Month-end recap",
                detail: "On the 1st: what you spent, what you saved, days on budget.",
                isOn: $recapOn, minutes: nil)
            divider
            row(symbol: "calendar.badge.checkmark", color: Theme.sky, title: "Weekly summary",
                detail: "Sunday 7 PM: what you spent and how many days were on budget.",
                isOn: $weeklyOn, minutes: nil)
            if AppExpiry.date != nil {
                divider
                row(symbol: "hourglass", color: Theme.warn, title: "App expiry",
                    detail: "The day before the free install stops opening, and that morning.",
                    isOn: $expiryOn, minutes: nil)
            }

            if denied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are turned off for Daily Budget.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.warn)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.bold)).foregroundStyle(Theme.mint)
                }
                .padding(.top, 10)
            }
        }
        .padding(16)
        .glassCard(radius: 28)
        .onChange(of: eveningOn) { _, on in switched(on) { eveningOn = false } }
        .onChange(of: morningOn) { _, on in switched(on) { morningOn = false } }
        .onChange(of: billsOn) { _, on in switched(on) { billsOn = false } }
        .onChange(of: weeklyOn) { _, on in switched(on) { weeklyOn = false } }
        .onChange(of: expiryOn) { _, on in switched(on) { expiryOn = false } }
        .onChange(of: subscriptionsOn) { _, on in switched(on) { subscriptionsOn = false } }
        .onChange(of: recapOn) { _, on in switched(on) { recapOn = false } }
        .onChange(of: eveningMinutes) { AppRefresh.run(context: context) }
        .onChange(of: morningMinutes) { AppRefresh.run(context: context) }
        .animation(.snappy, value: eveningOn)
        .animation(.snappy, value: morningOn)
        .animation(.snappy, value: denied)
    }

    private var divider: some View {
        Divider().overlay(Theme.ink.opacity(0.14)).padding(.vertical, 4)
    }

    private func row(symbol: String, color: Color, title: LocalizedStringKey, detail: LocalizedStringKey,
                     isOn: Binding<Bool>, minutes: Binding<Int>?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 32, height: 32)
                        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text(detail).font(.caption).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(Theme.teal)
            if let minutes, isOn.wrappedValue {
                HStack {
                    Text("Time").font(.footnote).foregroundStyle(Theme.secondary)
                    Spacer()
                    DatePicker("Time", selection: timeBinding(minutes), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .padding(.leading, 44)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 6)
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                                  second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }

    /// Turning a reminder on asks iOS for permission first; if it's refused, the switch goes back off.
    private func switched(_ on: Bool, revert: @escaping () -> Void) {
        guard on else { AppRefresh.run(context: context); return }
        Task {
            if await ReminderScheduler.requestPermission() {
                denied = false
            } else {
                revert()
                denied = true
            }
            AppRefresh.run(context: context)
        }
    }
}
