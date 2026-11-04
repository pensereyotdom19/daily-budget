import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable {
    case today, history, plan

    var title: String {
        switch self {
        case .today: return "Today"
        case .history: return "History"
        case .plan: return "Plan"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "clock"
        case .history: return "list.bullet"
        case .plan: return "chart.bar"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    /// Opens on Today. For screenshots during development, launch with `-startTab history` (or plan).
    @State private var tab: AppTab = AppTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .today
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(tab: $tab, onSelect: switchTo, onAdd: { showingAdd = true })
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
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
                            Text(item.title).font(.caption2.weight(.semibold))
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
