import SwiftUI
import SwiftData

/// "Can I afford it?": type a price and see what it does to today, tomorrow and the month.
struct AffordView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var settingsList: [BudgetSettings]
    @AppStorage("currency.rielPerDollar") private var rielPerDollar = Money.defaultRielPerDollar
    @State private var amountText = ""
    @State private var inRiel = false
    @FocusState private var focused: Bool

    private var cents: Int? {
        if inRiel { return Money.parseRiel(amountText).map { Money.rielToCents($0, rate: rielPerDollar) } }
        return Money.parse(amountText)
    }
    private var calc: BudgetCalculator { BudgetCalculator(expenses: expenses, settings: settingsList.first, incomes: incomes) }

    var body: some View {
        ZStack {
            GlowBackground()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                                .frame(width: 44, height: 44).glassCard(radius: 22)
                        }
                        .accessibilityLabel("Close")
                        Spacer()
                        Text("Can I afford it?").font(.headline)
                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Button {
                            inRiel.toggle(); amountText = ""
                        } label: {
                            Text(inRiel ? "៛" : "$").font(Theme.rounded(inRiel ? 34 : 40)).foregroundStyle(Theme.secondary)
                                .frame(minWidth: 34)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(inRiel ? "Typing in riel. Switch to dollars" : "Typing in dollars. Switch to riel")
                        TextField(inRiel ? "0" : "0.00", text: $amountText)
                            .keyboardType(inRiel ? .numberPad : .decimalPad)
                            .focused($focused)
                            .font(Theme.rounded(64))
                            .fixedSize()
                            .accessibilityLabel("Price")
                    }
                    if inRiel, let c = cents {
                        Text(verbatim: "= \(Money.format(c, alwaysShowCents: true))").font(Theme.rounded(16)).foregroundStyle(Theme.secondary)
                    }
                    if let c = cents, c > 0 {
                        result(calc.whatIf(spending: c, on: .now), cents: c)
                    } else {
                        Text("Type a price to see how it changes your budget. Nothing is saved.")
                            .font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(.white)
        .onAppear { focused = true }
    }

    private func result(_ w: BudgetCalculator.WhatIf, cents: Int) -> some View {
        let leftNow = calc.summary(on: .now).leftCents
        let verdict: (LocalizedStringKey, String, Color) =
            w.fitsToday ? ("Yes, it fits in today's money.", "checkmark.circle.fill", Theme.mint)
            : w.monthLeftAfter >= 0 ? ("More than today's money. Your month can take it, but the next days get less.", "exclamationmark.circle.fill", Theme.warn)
            : ("That's more than all the everyday money left this month.", "xmark.octagon.fill", Theme.pink)
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: verdict.1).font(.system(size: 22)).foregroundStyle(verdict.2)
                Text(verdict.0).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .glassCard(radius: 22)

            VStack(spacing: 0) {
                change("Left today", from: leftNow, to: w.leftTodayAfter)
                Divider().overlay(Color.white.opacity(0.14))
                if w.tomorrowInSameMonth {
                    change("Tomorrow's limit", from: w.tomorrowLimitNow, to: w.tomorrowLimitAfter)
                } else {
                    HStack {
                        Text("Tomorrow's limit").font(.subheadline)
                        Spacer()
                        Text("New month, no change").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    .padding(.vertical, 12)
                }
                Divider().overlay(Color.white.opacity(0.14))
                change("Left this month", from: w.monthLeftAfter + cents, to: w.monthLeftAfter)
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
            .glassCard()
        }
    }

    private func change(_ title: LocalizedStringKey, from: Int, to: Int) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(Money.format(from, alwaysShowCents: true)).font(Theme.rounded(15)).foregroundStyle(Theme.secondary)
            Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
            Text(Money.format(to, alwaysShowCents: true)).font(Theme.rounded(16))
                .foregroundStyle(to < 0 ? Theme.warn : .white)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
