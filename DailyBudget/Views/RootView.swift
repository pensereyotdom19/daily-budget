import SwiftUI
import SwiftData

enum AppTab: CaseIterable {
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
    @State private var tab: AppTab = .today
    @State private var showingAdd = false

    var body: some View {
        ZStack(alignment: .bottom) {
            GlowBackground()

            Group {
                switch tab {
                case .today: TodayView(onSeeAll: { tab = .history })
                case .history: HistoryView()
                case .plan: PlanView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(tab: $tab, onAdd: { showingAdd = true })
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
}

/// Glass capsule tab bar with a separate round + button.
struct FloatingTabBar: View {
    @Binding var tab: AppTab
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.snappy) { tab = item }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.symbol).font(.system(size: 19, weight: .semibold))
                            Text(item.title).font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(tab == item ? Color.white : Color.white.opacity(0.7))
                        .background {
                            if tab == item {
                                Capsule().fill(Color.white.opacity(0.14))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
            .padding(6)
            .glassCard(radius: 32)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.base)
                    .frame(width: 64, height: 64)
                    .background(Theme.accentGradient, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
            }
            .accessibilityLabel("Add expense")
        }
    }
}
