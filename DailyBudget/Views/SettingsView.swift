import SwiftUI
import SwiftData
import WidgetKit

/// Everything you set once and change rarely: language, reminders, lock, riel rate,
/// recurring expenses, backup and export.
struct SettingsView: View {
    @Query(sort: \Expense.date) private var expenses: [Expense]
    @AppStorage(AppLanguage.key, store: UserDefaults(suiteName: WidgetSnapshot.appGroup)) private var language = AppLanguage.system.rawValue
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(caption: "Daily Budget", title: "Settings")

                    section("General")
                    VStack(spacing: 0) {
                        languageCard
                        Divider().overlay(Theme.rule).padding(.leading, 60)
                        appearanceCard
                    }
                    .glassCard(radius: 22)

                    section("Reminders")
                    RemindersCard()

                    section("Money and security")
                    MoreCard()

                    if let expiry = AppExpiry.date {
                        section("This install")
                        expiryCard(expiry)
                    }

                    section("Your data")
                    SyncCard()
                    ShareLink(item: CSVExport.make(expenses: expenses),
                              preview: SharePreview("Daily Budget expenses")) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.sky)
                                .frame(width: 38, height: 38)
                                .background(Theme.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Export expenses").font(.subheadline.weight(.semibold))
                                Text("A CSV file for Numbers, Excel or Google Sheets").font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .glassCard(radius: 22)
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .background(GlowBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RecurringRoute.self) { _ in RecurringView() }
            .navigationDestination(for: AccountRoute.self) { _ in AccountView() }
            .navigationDestination(for: CategoryLimitsRoute.self) { _ in CategoryLimitsView() }
        }
    }

    /// Free Apple ID installs stop opening after 7 days; this shows when.
    private func expiryCard(_ expiry: Date) -> some View {
        let days = AppExpiry.daysLeft(until: expiry)
        let date = expiry.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute().locale(AppLanguage.locale))
        return HStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(days <= 1 ? Theme.warn : Theme.mint)
                .frame(width: 38, height: 38)
                .background(Theme.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Works until \(date)").font(.subheadline.weight(.semibold))
                Text(days <= 0 ? "Last day. Run it from Xcode on your Mac today." :
                     "\(days) days left. Run it from Xcode again before then to reset to 7 days.")
                    .font(.caption).foregroundStyle(days <= 1 ? Theme.warn : Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(radius: 22)
    }

    private func section(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.title3.weight(.bold)).padding(.horizontal, 4).padding(.top, 6)
    }

    /// One row with the current language; tapping it opens a short menu.
    private var languageCard: some View {
        let current = AppLanguage(rawValue: language) ?? .system
        return Menu {
            Picker("Language", selection: Binding(get: { current }, set: choose)) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(verbatim: lang.nativeName).tag(lang)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.sky)
                    .frame(width: 32, height: 32)
                    .background(Theme.sky.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Language").font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(verbatim: current.nativeName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Language"))
        .accessibilityValue(Text(verbatim: current.nativeName))
    }

    /// Light or dark, or follow the iPhone. Changes straight away.
    private var appearanceCard: some View {
        let current = AppAppearance(rawValue: appearance) ?? .system
        return Menu {
            Picker("Appearance", selection: Binding(get: { current }, set: { appearance = $0.rawValue })) {
                ForEach(AppAppearance.allCases) { a in
                    Label(a.title, systemImage: a.symbol).tag(a)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: current.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.violet)
                    .frame(width: 32, height: 32)
                    .background(Theme.violet.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Appearance").font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(verbatim: current.title).font(.subheadline).foregroundStyle(Theme.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Appearance"))
        .accessibilityValue(Text(verbatim: current.title))
    }

    private func choose(_ lang: AppLanguage) {
        guard lang.rawValue != language else { return }
        AppLanguage.set(lang)
        WidgetCenter.shared.reloadAllTimelines()
        language = lang.rawValue  // redraws the app in the new language
    }
}
