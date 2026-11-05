import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case today, history, plan, settings

    var title: String {
        switch self {
        case .today: return String(localized: "Today", bundle: AppLanguage.bundle)
        case .history: return String(localized: "History", bundle: AppLanguage.bundle)
        case .plan: return String(localized: "Plan", bundle: AppLanguage.bundle)
        case .settings: return String(localized: "Settings", bundle: AppLanguage.bundle)
        }
    }

    var symbol: String {
        switch self {
        case .today: return "clock"
        case .history: return "list.bullet"
        case .plan: return "chart.bar"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncManager.self) private var sync
    @Environment(AppLock.self) private var lock
    /// Kept by the app, so switching language (which redraws everything) stays on the same tab.
    @Binding var tab: AppTab
    @State private var showingAdd = false

    var body: some View {
        ZStack(alignment: .bottom) {
            GlowBackground()

            // All three tabs stay alive (no reload, scroll position kept); switching only cross-fades.
            ZStack {
                TodayView(onSeeAll: { switchTo(.history) })
                    .tabLayer(isActive: tab == .today)
                HistoryView()
                    .tabLayer(isActive: tab == .history)
                PlanView()
                    .tabLayer(isActive: tab == .plan)
                SettingsView()
                    .tabLayer(isActive: tab == .settings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(tab: $tab, onSelect: switchTo, onAdd: { showingAdd = true })
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
                // Stay at the bottom behind the keyboard instead of riding up over the form.
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showingAdd) {
            AddExpenseView()
                .presentationDetents([.large])
                .presentationBackground(Theme.base)
        }
        .onAppear {
            Seed.insertIfNeeded(into: context)
            BillPayments.sync(in: context)
            BillAutoPay.run(in: context)
            RecurringRunner.addDue(in: context)
            SubscriptionRunner.addDue(in: context)
            QuickAddImporter.run(in: context)
            if QuickAddImporter.takeOpenAddRequest() { showingAdd = true }
            lock.sceneChanged(to: .active)
            // Re-registers the Siri phrases (and their category words) every launch.
            DailyBudgetShortcuts.updateAppShortcutParameters()
            AppRefresh.run(context: context)
            sync.attach(context)
            sync.appBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickAddQueued)) { _ in
            // Siri ran while the app was open: save now, and open + if a Shortcut asked for it.
            QuickAddImporter.run(in: context)
            if QuickAddImporter.takeOpenAddRequest() { showingAdd = true }
            AppRefresh.run(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            // Opening or leaving the app updates the widget and reschedules reminders, and backs up changes.
            lock.sceneChanged(to: phase)
            if phase == .active {
                RecurringRunner.addDue(in: context)
                SubscriptionRunner.addDue(in: context)
                BillAutoPay.run(in: context)
                QuickAddImporter.run(in: context)
                if QuickAddImporter.takeOpenAddRequest() { showingAdd = true }
            }
            if phase != .inactive { AppRefresh.run(context: context) }
            if phase == .active { sync.appBecameActive() }
            if phase == .background { sync.appWentToBackground() }
        }
    }

    private func switchTo(_ newTab: AppTab) {
        guard newTab != tab else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { tab = newTab }
    }
}

private extension View {
    /// A tab screen that stays in memory: visible and tappable only when active, with a soft fade and lift.
    func tabLayer(isActive: Bool) -> some View {
        self
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 10)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}

/// Glass capsule tab bar with a separate round + button.
struct FloatingTabBar: View {
    @Binding var tab: AppTab
    var onSelect: (AppTab) -> Void
    var onAdd: () -> Void
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.symbol).font(.system(size: 19, weight: .semibold))
                            Text(item.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(tab == item ? Color.white : Color.white.opacity(0.7))
                        .background {
                            if tab == item {
                                // Slides from the old tab to the new one.
                                Capsule().fill(Color.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "highlight", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
            .padding(6)
            .glassCard(radius: 32)
            .sensoryFeedback(.selection, trigger: tab)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.base)
                    .frame(width: 64, height: 64)
                    .background(Theme.accentGradient, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Add expense")
        }
    }
}
