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
    private var undo = DeleteUndo.shared
    /// For screenshots during development: launch with `-openAdd YES` to start on the + screen.
    @State private var showingAdd = UserDefaults.standard.bool(forKey: "openAdd")

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

            if let snap = undo.last {
                UndoBar(snapshot: snap) { undo.undo(in: context) }
                    .padding(.bottom, 96)
                    .id(snap.token)
                    .zIndex(2)
            }

            FloatingTabBar(tab: $tab, onSelect: switchTo, onAdd: { showingAdd = true })
                // Stay at the bottom behind the keyboard instead of riding up over the form.
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $showingAdd) {
            AddExpenseView()
                .presentationDetents([.large])
                .presentationBackground(Theme.base)
        }
        .onAppear {
            Seed.insertIfNeeded(into: context)
            #if DEBUG
            SampleData.insertIfRequested(into: context)
            #endif
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

/// Ledger tab bar: a ruled bar along the bottom with the + in the middle.
struct FloatingTabBar: View {
    @Binding var tab: AppTab
    var onSelect: (AppTab) -> Void
    var onAdd: () -> Void
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            item(.today)
            item(.history)
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.base)
                    .frame(width: 54, height: 54)
                    .background(Theme.highlight, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Add expense")
            .padding(.horizontal, 6)
            item(.plan)
            item(.settings)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background {
            Theme.card
                .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
        .sensoryFeedback(.selection, trigger: tab)
    }

    private func item(_ item: AppTab) -> some View {
        Button { onSelect(item) } label: {
            VStack(spacing: 3) {
                Image(systemName: item.symbol).font(.system(size: 19, weight: tab == item ? .semibold : .regular))
                Text(item.title).font(.caption2.weight(tab == item ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.7)
                Capsule().fill(tab == item ? Theme.ink : .clear).frame(width: 18, height: 2)
                    .matchedGeometryEffect(id: tab == item ? "underline" : "\(item.rawValue)", in: highlight)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(tab == item ? Theme.ink : Theme.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(tab == item ? .isSelected : [])
    }
}
