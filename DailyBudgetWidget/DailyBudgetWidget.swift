import WidgetKit
import SwiftUI
import UIKit
import AppIntents

@main
struct DailyBudgetWidgets: WidgetBundle {
    init() {
        AppLanguage.install()
    }

    var body: some Widget {
        TodayLeftWidget()
        if #available(iOS 18.0, *) {
            QuickAddControl()
            NewExpenseControl()
        }
    }
}

struct TodayLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayLeft", provider: Provider()) { entry in
            TodayLeftView(entry: entry)
        }
        .configurationDisplayName("Left today")
        .description("How much you can still spend today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Timeline

struct DayEntry: TimelineEntry {
    var date: Date
    var limitCents: Int
    var spentCents: Int
    var monthLeftCents: Int
    var hasData: Bool
    var quickItems: [WidgetQuickItem] = []
    var leftCents: Int { limitCents - spentCents }
    var isOver: Bool { spentCents > limitCents }
    var fraction: Double { limitCents > 0 ? min(1, max(0, Double(leftCents) / Double(limitCents))) : 0 }

    static let placeholder = DayEntry(date: .now, limitCents: 340, spentCents: 125, monthLeftCents: 9_075, hasData: true)
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(on: .now))
    }

    /// One entry now, then one at each of the next midnights, so the limit resets
    /// on a new day even if the app isn't opened. The app reloads this when you log something.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let cal = Calendar.current
        var dates = [Date.now]
        var day = cal.startOfDay(for: .now)
        for _ in 0..<3 {
            day = cal.date(byAdding: .day, value: 1, to: day)!
            dates.append(day)
        }
        completion(Timeline(entries: dates.map(entry(on:)), policy: .atEnd))
    }

    private func entry(on date: Date) -> DayEntry {
        guard let snap = WidgetSnapshot.load() else {
            return DayEntry(date: date, limitCents: 0, spentCents: 0, monthLeftCents: 0, hasData: false)
        }
        let calc = snap.calculator()
        let today = calc.summary(on: date)
        return DayEntry(date: date, limitCents: today.limitCents, spentCents: today.spentCents,
                        monthLeftCents: calc.monthLeftCents(inMonthOf: date), hasData: true,
                        quickItems: Array((snap.quickItems ?? []).prefix(3)))
    }
}

// MARK: - Views

private enum W {
    // Ledger look, same as the app: paper and navy ink by day, dark navy and cream ink at night.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        func ui(_ h: UInt32) -> UIColor {
            UIColor(red: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1)
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    static let base = dyn(0xF3EBDD, 0x0F1A2E)
    static let ink = dyn(0x23301F, 0xE7EEF6)
    static let mint = dyn(0x2E5E3E, 0xA9CBE8)
    static let warn = dyn(0xBF3F2A, 0xF07A62)
    static let secondary = dyn(0x6F6A5C, 0x8FA6C2)
    static let rule = dyn(0xE2D6C1, 0x263756)
    static let accent = LinearGradient(colors: [mint, mint], startPoint: .top, endPoint: .bottom)
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight == .bold ? .semibold : weight, design: .serif)
    }
}

struct TodayLeftView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    private var left: String { Money.format(entry.leftCents, alwaysShowCents: true) }
    private var limit: String { Money.format(entry.limitCents, alwaysShowCents: true) }

    var body: some View {
        content
            .environment(\.locale, AppLanguage.locale)
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var content: some View {
        if !entry.hasData {
            Text("Open Daily Budget once to set up this widget.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(W.ink)
                .multilineTextAlignment(.center)
        } else {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: Text(entry.isOver ? "\(Money.format(-entry.leftCents, alwaysShowCents: true)) over today" : "\(left) left today")
            case .systemMedium: medium
            default: small
            }
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .systemSmall, .systemMedium: W.base
        default: Color.clear
        }
    }

    private func ring(size: CGFloat, line: CGFloat) -> some View {
        ZStack {
            Circle().stroke(W.rule, lineWidth: line)
            Circle()
                .trim(from: 0, to: entry.fraction)
                .stroke(W.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private var ringLabel: some View {
        VStack(spacing: 0) {
            Text(left)
                .font(W.rounded(20))
                .foregroundStyle(entry.isOver ? W.warn : W.ink)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(entry.isOver ? "OVER TODAY" : "LEFT TODAY")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(W.secondary)
        }
        .padding(14)
    }

    private var small: some View {
        VStack(spacing: 6) {
            ZStack { ring(size: 104, line: 10); ringLabel }
            Text("Limit \(limit)").font(.caption2.weight(.semibold)).foregroundStyle(W.secondary)
        }
        .foregroundStyle(W.ink)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                ZStack { ring(size: entry.quickItems.isEmpty ? 118 : 100, line: 10); ringLabel }
                if !entry.quickItems.isEmpty {
                    Text("Limit \(limit)").font(.system(size: 10, weight: .semibold)).foregroundStyle(W.secondary)
                }
            }
            if entry.quickItems.isEmpty { stats } else { buttons }
        }
        .foregroundStyle(W.ink)
    }

    /// Tap to log it right away. The app saves it next time it opens.
    private var buttons: some View {
        VStack(spacing: 6) {
            ForEach(entry.quickItems, id: \.self) { item in
                Button(intent: QuickAddIntent(item: item)) {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(W.base.opacity(0.85))
                            .frame(width: 24, height: 24)
                            .background(Color(widgetHex: item.colorHex), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(Money.format(item.cents, alwaysShowCents: true)).font(W.rounded(12, .semibold))
                        Image(systemName: "plus").font(.system(size: 10, weight: .heavy)).foregroundStyle(W.mint)
                    }
                    .padding(.horizontal, 8).frame(height: 32)
                    .background(W.ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                stat("DAILY LIMIT", limit)
                stat("SPENT TODAY", Money.format(entry.spentCents, alwaysShowCents: true))
                stat("\(entry.date.formatted(.dateTime.month(.wide).locale(AppLanguage.locale)).uppercased()) LEFT",
                     Money.format(entry.monthLeftCents, alwaysShowCents: true))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(W.ink)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(W.secondary)
            Text(value).font(W.rounded(17))
        }
    }

    private var circular: some View {
        Gauge(value: entry.fraction) {
            Text("Left")
        } currentValueLabel: {
            Text(Money.format(entry.leftCents)).minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.isOver ? "Over today" : "Left today").font(.caption2.weight(.semibold))
            Text(entry.isOver ? Money.format(-entry.leftCents, alwaysShowCents: true) : left)
                .font(W.rounded(22)).widgetAccentable()
            Text("Limit \(limit)").font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Color {
    /// The category colour: as is by day, mixed toward white at night.
    init(widgetHex hex: UInt32) {
        func mix(_ c: UInt32) -> UInt32 { UInt32(Double(c) + (255 - Double(c)) * 0.45) }
        let night = (mix((hex >> 16) & 0xFF) << 16) | (mix((hex >> 8) & 0xFF) << 8) | mix(hex & 0xFF)
        self = W.dyn(hex, night)
    }
}

/// A widget button: queues the expense for the app and updates the ring straight away.
struct QuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick add"
    static let isDiscoverable = false

    @Parameter(title: "Note") var note: String
    @Parameter(title: "Category") var category: String
    @Parameter(title: "Amount in cents") var cents: Int

    init() {}

    init(item: WidgetQuickItem) {
        note = item.note
        category = item.category
        cents = item.cents
    }

    func perform() async throws -> some IntentResult {
        guard cents > 0 else { return .result() }
        let pending = PendingExpense(id: UUID(), cents: cents, category: category, note: note, date: .now)
        QuickAddQueue.append(pending)
        QuickAddQueue.applyToSnapshot(pending, countsAsLiving: QuickAddQueue.countsAsLiving(category))
        return .result()
    }
}

/// Control Center / Lock Screen button: adds your most-used expense (e.g. your usual coffee).
@available(iOS 18.0, *)
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickAddControl") {
            ControlWidgetButton(action: QuickAddTopIntent()) {
                Label("Quick add", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Quick add")
        .description("Adds the expense you log most often.")
    }
}

/// Control Center / Lock Screen button: opens Daily Budget on the + screen.
@available(iOS 18.0, *)
struct NewExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "NewExpenseControl") {
            ControlWidgetButton(action: NewExpenseFromControlIntent()) {
                Label("New expense", systemImage: "square.and.pencil")
            }
        }
        .displayName("New expense")
        .description("Opens Daily Budget ready to add an expense.")
    }
}
